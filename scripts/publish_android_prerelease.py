#!/usr/bin/env python3
"""Verify a successful main-branch Android build and publish a test prerelease.

Run in GitHub Actions with GH_TOKEN, Android build-tools 37 and JDK 17.
No signing keys are generated or exported here. Assets are reused only when
their byte count and SHA-256 match; published releases are never overwritten.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
from urllib.parse import quote
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'Ktclat/Pili--'
APPLICATION_ID = 'io.github.ktclat.piliminus'
ABIS = ('arm64-v8a', 'armeabi-v7a', 'x86_64')
ARTIFACT_NAME = 'Pili--Android-test-signed'
TAG_PATTERN = re.compile(r'v(\d+\.\d+\.\d+)-(?:alpha|beta|rc)\.[1-9]\d*')
SHA_PATTERN = re.compile(r'[0-9a-f]{40}')


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def command(*args: object) -> str:
    result = subprocess.run([str(x) for x in args], cwd=ROOT, text=True,
                            capture_output=True)
    if result.returncode:
        # Keep CLI diagnostics useful without dumping environments or large logs.
        # No command arguments contain tokens; GH_TOKEN remains in the environment.
        diagnostic = (result.stderr.strip() or result.stdout.strip())[-2000:]
        raise RuntimeError(f'{Path(str(args[0])).name} failed ({result.returncode}): {diagnostic}')
    return result.stdout


def api(path: str, *, allow_missing: bool = False):
    result = subprocess.run(['gh', 'api', f'repos/{REPOSITORY}/{path}'],
                            cwd=ROOT, text=True, capture_output=True)
    if allow_missing and result.returncode and '(HTTP 404)' in result.stderr:
        return None
    if result.returncode:
        raise RuntimeError(f'GitHub API failed for {path}: {result.stderr.strip()[-2000:]}')
    return json.loads(result.stdout)


def sha256(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_version(commit: str) -> tuple[str, int]:
    pubspec = command('git', 'show', f'{commit}:pubspec.yaml')
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', pubspec, re.M)
    require(match is not None, 'Build source must declare a stable core version and build number')
    return match[1], int(match[2])


def validate_run(run: dict) -> str:
    require(run.get('status') == 'completed' and run.get('conclusion') == 'success',
            'Build must have completed successfully')
    require(run.get('head_branch') == 'main', 'Only main-branch builds may be published')
    require(run.get('head_repository', {}).get('full_name') == REPOSITORY,
            'Build source must be this repository, not a fork')
    require(run.get('event') in ('push', 'workflow_dispatch'), 'PR and other build events are not publishable')
    require(run.get('path') == '.github/workflows/build.yml', 'Unexpected build workflow')
    commit = run.get('head_sha', '')
    require(bool(SHA_PATTERN.fullmatch(commit)), 'Invalid build source commit')
    require(bool(run.get('updated_at')), 'Build completion metadata is missing')
    return commit


def tag_commit(tag: str) -> str | None:
    ref = api(f'git/ref/tags/{quote(tag, safe="")}', allow_missing=True)
    if ref is None:
        return None
    obj = ref['object']
    for _ in range(5):
        if obj['type'] == 'commit':
            return obj['sha']
        require(obj['type'] == 'tag', 'Release tag does not reference a commit')
        obj = api(f'git/tags/{obj["sha"]}')['object']
    raise ValueError('Release tag is nested too deeply')


def inspect_apk(path: Path, abi: str, version: str, code: int,
                commit: str, build_tools: Path) -> dict:
    badging = command(build_tools / 'aapt', 'dump', 'badging', path)
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    require(package is not None and package.groups() == (APPLICATION_ID, str(code), version),
            f'{path.name}: unexpected package/version')
    require(bool(re.search(r"^sdkVersion:'24'$", badging, re.M)), f'{path.name}: unexpected minSdk')
    native = re.search(r'^native-code:(.*)$', badging, re.M)
    require(native is not None and re.findall(r"'([^']+)'", native[1]) == [abi],
            f'{path.name}: unexpected native ABI')
    signature = command(build_tools / 'apksigner', 'verify', '--verbose', '--print-certs', path)
    require(bool(re.search(r'^Number of signers: 1$', signature, re.M)),
            f'{path.name}: expected one verified signer')
    # New build-tools print "V2 Signer", older versions print "Signer #1".
    # A signer may be reported once per verified signature scheme.
    certificates = set(re.findall(
        r'^(?:Signer #\d+|V\d+(?:\.\d+)? Signer):? certificate SHA-256 digest: ([0-9a-fA-F]{64})$',
        signature, re.M))
    require(len(certificates) == 1, f'{path.name}: expected one consistent signer certificate')
    with zipfile.ZipFile(path) as archive:
        app = archive.read(f'lib/{abi}/libapp.so')
        require(commit.encode() in app, f'{path.name}: embedded source commit does not match CI')
        require((commit + '-dirty').encode() not in app, f'{path.name}: dirty source build')
    print(f'Verified {path.name}: identity, version, ABI, source and signature')
    return {
        'file': path.name, 'abi': abi, 'application_id': APPLICATION_ID,
        'version_name': version, 'version_code': code, 'min_sdk': 24,
        'sha256': sha256(path), 'size_bytes': path.stat().st_size,
        'embedded_source_commit': commit,
        'signer_certificate_sha256': next(iter(certificates)).lower(),
    }


def source_archive(destination: Path, commit: str, version: str, code: int) -> Path:
    prefix = f'PiliMinus-{version}+{code}-source/'
    path = destination / f'PiliMinus-{version}+{code}-source.tar.gz'
    command('git', 'archive', '--format=tar.gz', f'--prefix={prefix}', f'--output={path}', commit)
    with tarfile.open(path) as archive:
        names = {entry.name for entry in archive.getmembers()}
    required = {
        'LICENSE', 'NOTICE', 'pubspec.yaml', 'pubspec.lock', 'docs/BUILD.md',
        'scripts/build_android.ps1', 'scripts/prepare_android.ps1',
        'lib/utils/accounts/account_manager/LICENSE', 'assets/shaders/LICENSE',
        '.github/workflows/build.yml',
    }
    require(all(prefix + name in names for name in required), 'Source archive is missing licensing/build materials')
    require(any(name.startswith(prefix + 'lib/scripts/') and name.endswith('.patch') for name in names),
            'Source archive is missing Flutter framework patches')
    require(not any('/.tools/' in name or '/.artifacts/' in name or name.endswith('/android/key.properties')
                    or name.endswith(('.jks', '.keystore')) for name in names),
            'Source archive contains local tooling or signing files')
    return path


def extract_changelog_entry(changelog: str, version: str, code: int) -> str:
    """Read one exact version's body without borrowing an adjacent release."""
    target = f'{version}+{code}'
    heading = re.compile(r'^ {0,3}##[ \t]+(\d+\.\d+\.\d+\+\d+)(?=[ \t]|$)')
    next_heading = re.compile(r'^ {0,3}##(?:[ \t]+|$)')
    sections = []
    lines = changelog.splitlines()
    for start, line in enumerate(lines):
        match = heading.match(line)
        if match is None or match[1] != target:
            continue
        end = next((i for i in range(start + 1, len(lines))
                    if next_heading.match(lines[i])), len(lines))
        sections.append('\n'.join(lines[start + 1:end]).strip())
    require(len(sections) == 1, f'Expected one CHANGELOG entry for {target}')
    # Comments or subsection titles alone are not release notes.
    visible = re.sub(r'<!--[\s\S]*?-->', '', sections[0])
    visible = re.sub(r'^ {0,3}#{1,6}(?:[ \t]+.*)?$', '', visible, flags=re.M).strip()
    require(bool(visible), f'CHANGELOG entry for {target} has no release content')
    return sections[0]


def source_changes(commit: str, version: str, code: int) -> str:
    changelog = command('git', 'show', f'{commit}:CHANGELOG.md')
    return extract_changelog_entry(changelog, version, code)


def release_notes(tag: str, version: str, code: int, commit: str, run: dict) -> str:
    changes = source_changes(commit, version, code)
    return f'''# Pili-- {tag}

Android **{version}+{code}**，测试签名预发布；不是固定发行密钥签名的稳定版。

## 本次更新

{changes}

## 下载与升级

- 多数手机使用 `arm64-v8a`，兼容的 32 位 ARM 设备使用 `armeabi-v7a`，x86_64 设备／模拟器使用 `x86_64`。最低 Android 7.0 / API 24。
- 独立安装 ID 为 `{APPLICATION_ID}`，可与上游 PiliPlus 同时安装。
- APK 文件名包含 `test-signed`；`SHA256SUMS.txt` 用于核对附件，`BUILD_INFO.json` 记录实际包身份、签名证书摘要与构建来源。
- **临时测试签名可能与旧测试包不同，不保证覆盖升级。** 签名冲突时先核对来源并备份数据，不要直接清除应用数据，无需卸载 PiliPlus。
- 本次为 Pre-release，应用内稳定版更新检查不会提示，请在此页面手动下载。

## 来源与验证

- 精确构建源码：`{commit}`。
- [通过的 Actions 构建]({run['html_url']})：分析与回归、三个 ABI 构建及实际 APK 隔离检查全部成功。具体测试数以该次日志为准。
- 发布前再次校验三个 APK 的包名、版本、ABI、嵌入源码提交和签名；三包使用同一证书。
- [设备记录](https://github.com/{REPOSITORY}/blob/{commit}/docs/VALIDATION.md) 按各自源码提交和安装包记录，历史设备结果不代表本次 CI 包重新安装验收。
- **真实账号网页／TV 授权、ARM64 真机、长时间播放／下载仍待验收。** 假响应测试、接口研究及构建通过不等于实际授权成功。

## 源码与许可

`PiliMinus-{version}+{code}-source.tar.gz` 来自上述精确提交，包含 GPL、NOTICE、第三方声明、锁文件、构建脚本与 Flutter 补丁；构建步骤见其中的 `docs/BUILD.md`。依赖保留各自许可。GitHub 的 Source code 链接也对应本版本标签。
'''


def assets_from_release(release: dict) -> dict:
    assets = api(f'releases/{release["id"]}/assets?per_page=100')
    require(len(assets) < 100, 'Too many draft assets to verify safely')
    result = {asset['name']: asset for asset in assets}
    require(len(result) == len(assets), 'Duplicate release asset names')
    return result


def matching_asset(remote: dict, path: Path) -> bool:
    return (remote.get('size') == path.stat().st_size
            and remote.get('digest') == 'sha256:' + sha256(path)
            and remote.get('state') == 'uploaded')


def find_release(tag: str) -> dict | None:
    # GET /releases/tags/{tag} deliberately omits drafts even for their author.
    # Authenticated collection reads include drafts, so resolve their numeric ID.
    matches = []
    for page in range(1, 21):
        releases = api(f'releases?per_page=100&page={page}')
        matches.extend(release for release in releases if release.get('tag_name') == tag)
        if len(releases) < 100:
            break
    else:
        raise ValueError('Too many release pages to resolve a draft safely')
    require(len(matches) <= 1, 'Multiple releases use the requested tag; review before publishing')
    return api(f'releases/{matches[0]["id"]}') if matches else None


def publish(tag: str, commit: str, notes: Path, files: list[Path]) -> str:
    existing_tag = tag_commit(tag)
    require(existing_tag in (None, commit), 'Existing release tag points to different source')
    release = find_release(tag)
    if release is None:
        command('gh', 'release', 'create', tag, '--repo', REPOSITORY, '--target', commit,
                '--draft', '--prerelease', '--title', f'Pili-- {tag}（测试签名）', '--notes-file', notes)
        release = find_release(tag)
        require(release is not None, 'Created release draft could not be resolved')
    require(release.get('draft') is True, 'Refusing to modify a published release')
    require(release.get('prerelease') is True, 'Existing draft is not a prerelease')
    require(release.get('target_commitish') == commit, 'Existing draft targets different source')
    existing = assets_from_release(release)
    expected = {path.name for path in files}
    require(set(existing).issubset(expected), 'Draft contains unexpected assets; review before publishing')
    for path in files:
        if path.name in existing:
            require(matching_asset(existing[path.name], path), f'Draft asset differs: {path.name}')
            print(f'Reusing verified draft asset {path.name}')
        else:
            command('gh', 'release', 'upload', tag, path, '--repo', REPOSITORY)
            print(f'Uploaded {path.name}')
    for attempt in range(10):
        actual = assets_from_release(release)
        if set(actual) == expected and all(matching_asset(actual[path.name], path) for path in files):
            break
        if attempt == 9:
            raise ValueError('Remote release assets do not match local bytes/SHA-256')
        time.sleep(2)
    command('gh', 'release', 'edit', tag, '--repo', REPOSITORY, '--draft=false',
            '--prerelease', '--latest=false', '--notes-file', notes)
    published = api(f'releases/tags/{quote(tag, safe="")}')
    require(published.get('draft') is False and published.get('prerelease') is True,
            'Release did not become a public prerelease')
    require(tag_commit(tag) == commit, 'Published tag does not match the APK source')
    return published['html_url']


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id', required=True, type=int)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--prepare-only', action='store_true', help='Verify and prepare assets without changing any release')
    args = parser.parse_args()
    require(args.run_id > 0, 'Run ID must be positive')
    tag_match = TAG_PATTERN.fullmatch(args.tag)
    require(tag_match is not None, 'Tag must be vX.Y.Z-alpha.N, -beta.N or -rc.N')
    require(os.environ.get('GH_REPO', REPOSITORY) == REPOSITORY, 'Unexpected GH_REPO')
    require(os.environ.get('GITHUB_REPOSITORY', REPOSITORY) == REPOSITORY, 'Unexpected Actions repository')
    run = api(f'actions/runs/{args.run_id}')
    commit = validate_run(run)
    jobs = api(f'actions/runs/{args.run_id}/jobs?per_page=100')
    require(jobs.get('total_count', 0) == len(jobs.get('jobs', [])) and bool(jobs.get('jobs'))
            and all(job['status'] == 'completed' and job['conclusion'] == 'success' for job in jobs['jobs']),
            'Every build job must have succeeded')
    version, code = source_version(commit)
    require(tag_match[1] == version, 'Prerelease tag does not match the build source version')
    artifacts = api(f'actions/runs/{args.run_id}/artifacts?per_page=100')
    selected = [item for item in artifacts.get('artifacts', []) if item['name'] == ARTIFACT_NAME]
    require(len(selected) == 1 and selected[0].get('expired') is False, 'Expected one unexpired Android artifact')
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    require(bool(sdk), 'ANDROID_HOME or ANDROID_SDK_ROOT is required')
    build_tools = Path(sdk) / 'build-tools/37.0.0'
    require(all((build_tools / tool).is_file() for tool in ('aapt', 'apksigner')), 'Install Android build-tools 37.0.0 first')
    work = (args.output_dir.resolve() if args.output_dir else
            Path(tempfile.mkdtemp(prefix='pili-prerelease-', dir=os.environ.get('RUNNER_TEMP'))))
    work.mkdir(parents=True, exist_ok=True)
    downloads = Path(tempfile.mkdtemp(prefix='download-', dir=work))
    destination = work / 'assets'
    destination.mkdir(exist_ok=True)
    command('gh', 'run', 'download', args.run_id, '--repo', REPOSITORY,
            '--name', ARTIFACT_NAME, '--dir', downloads)
    expected_originals = {f'app-{abi}-release.apk' for abi in ABIS}
    require({path.name for path in downloads.rglob('*.apk')} == expected_originals,
            'Unexpected downloaded APK set')
    require(all((downloads / name).is_file() for name in expected_originals), 'APK artifact layout changed')
    records = []
    apks = []
    for abi in ABIS:
        path = destination / f'PiliMinus-{version}+{code}-{abi}-test-signed.apk'
        shutil.copyfile(downloads / f'app-{abi}-release.apk', path)
        records.append(inspect_apk(path, abi, version, code, commit, build_tools))
        apks.append(path)
    require(len({item['signer_certificate_sha256'] for item in records}) == 1, 'APK signers differ between ABIs')
    print(command(sys.executable, ROOT / 'scripts/check_android_identity.py',
                  '--aapt', build_tools / 'aapt', *[arg for path in apks for arg in ('--apk', path)]))
    source = source_archive(destination, commit, version, code)
    info = {
        'schema_version': 1, 'release_tag': args.tag, 'prerelease': True,
        'version': f'{version}+{code}', 'source_commit': commit,
        'workflow_run_id': args.run_id, 'workflow_run_url': run['html_url'],
        'workflow_run_updated_at': run['updated_at'], 'artifact_id': selected[0]['id'],
        'artifact_digest': selected[0].get('digest'), 'build_mode': 'release',
        'signing': {
            'kind': 'CI-generated Android test signing, not a stable distribution key',
            'certificate_sha256': records[0]['signer_certificate_sha256'],
            'in_place_upgrade_from_other_CI_runs_guaranteed': False,
        },
        'apks': records,
        'source_archive': {'file': source.name, 'sha256': sha256(source)},
        'validation': {
            'all_CI_jobs_succeeded': True, 'packaged_identity_and_signature_rechecked': True,
            'test_counts': 'See linked CI logs; not inferred by the publisher',
            'real_account_web_tv_authorization_tested': False,
            'arm64_real_device_tested': False, 'CI_APK_device_acceptance_completed': False,
        },
    }
    build_info = destination / 'BUILD_INFO.json'
    build_info.write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n')
    checksums = destination / 'SHA256SUMS.txt'
    content_files = sorted([*apks, source, build_info], key=lambda path: path.name)
    checksums.write_text(''.join(f'{sha256(path)}  {path.name}\n' for path in content_files))
    files = sorted([*content_files, checksums], key=lambda path: path.name)
    notes = work / 'release-notes.md'
    notes.write_text(release_notes(args.tag, version, code, commit, run))
    print(f'Verified assets prepared in {destination}')
    if args.prepare_only:
        return 0
    url = publish(args.tag, commit, notes, files)
    print(url)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with Path(summary).open('a') as stream:
            stream.write(f'## Test-signed Android prerelease\n\n[{args.tag}]({url})\n\n'
                         f'Build source: `{commit}` · [Actions run]({run["html_url"]})\n\n'
                         'Three APKs, exact source, build metadata and SHA-256 sums verified and published.\n')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, KeyError, subprocess.CalledProcessError,
            tarfile.TarError, zipfile.BadZipFile) as error:
        # Commands never contain authentication tokens. Do not dump process env.
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
