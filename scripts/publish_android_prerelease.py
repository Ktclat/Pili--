#!/usr/bin/env python3
"""Verify a successful main-branch Android build and publish an Android release.

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
TEST_ARTIFACT = 'Pili--Android-test-signed'
SIGNED_ARTIFACT = 'Pili--Android-release-signed'
SIGN_JOB = 'Sign Android release APKs'
NUMBER = r'(?:0|[1-9][0-9]*)'
TAG_PATTERN = re.compile(rf'v({NUMBER}\.{NUMBER}\.{NUMBER})(-(?:alpha|beta|rc)\.[1-9][0-9]*)?')
SHA_PATTERN = re.compile(r'[0-9a-f]{40}')


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def command(*args: object, input_text: str | None = None) -> str:
    result = subprocess.run([str(x) for x in args], cwd=ROOT, text=True,
                            input=input_text, capture_output=True)
    if result.returncode:
        # Keep CLI diagnostics useful without dumping environments or large logs.
        # No command arguments contain tokens; GH_TOKEN remains in the environment.
        diagnostic = re.sub(r'(https?://[^?\s"]+)\?[^\s"]+', r'\1?[redacted]',
                            result.stderr.strip() or result.stdout.strip())[-2000:]
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


def release_settings(tag: str, pin: str) -> tuple[bool, str | None, str]:
    match = TAG_PATTERN.fullmatch(tag)
    require(match is not None, 'Tag must be vX.Y.Z or vX.Y.Z-(alpha|beta|rc).N')
    prerelease = bool(match[2])
    pin = pin.strip().lower()
    if pin:
        require(bool(re.fullmatch(r'[0-9a-f]{64}', pin)), 'Invalid ANDROID_RELEASE_CERT_SHA256')
    require(prerelease or bool(pin), 'A stable release requires a pinned Android release signer')
    return prerelease, pin or None, SIGNED_ARTIFACT if pin else TEST_ARTIFACT


def validate_jobs(response: dict, use_release_signer: bool) -> None:
    jobs = response.get('jobs', [])
    require(response.get('total_count') == len(jobs) and jobs, 'Incomplete build job list')
    successes = {job['name'] for job in jobs if job.get('conclusion') == 'success'}
    require('android' in successes, 'Android validation job must have succeeded')
    if use_release_signer:
        require(SIGN_JOB in successes, 'The maintained signing job must have succeeded')
    for job in jobs:
        optional = not use_release_signer and job['name'] == SIGN_JOB and job.get('conclusion') == 'skipped'
        require(job.get('status') == 'completed' and (optional or job.get('conclusion') == 'success'),
                f'Build job did not succeed: {job["name"]}')


def verify_signers(records: list[dict], pin: str | None) -> str:
    signers = {item['signer_certificate_sha256'] for item in records}
    require(len(signers) == 1, 'APK signers differ between ABIs')
    signer = signers.pop()
    require(not pin or signer == pin, 'APK certificate does not match ANDROID_RELEASE_CERT_SHA256')
    return signer


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


def is_local_build_material(member: str) -> bool:
    name = member.lower()
    return ('/.tools/' in name or '/.artifacts/' in name
            or name.endswith(('/android/key.properties', '.jks', '.keystore', '.p12', '.pfx')))


def source_archive(destination: Path, commit: str, version: str, code: int) -> Path:
    prefix = f'PiliMinus-{version}+{code}-source/'
    path = destination / f'PiliMinus-{version}+{code}-source.tar.gz'
    command('git', 'archive', '--format=tar.gz', f'--prefix={prefix}', f'--output={path}', commit)
    with tarfile.open(path) as archive:
        names = {entry.name for entry in archive.getmembers()}
    if any(is_local_build_material(name) for name in names):
        path.unlink()
        raise ValueError('Source archive contains local tooling or signing files')
    required = {
        'LICENSE', 'NOTICE', 'pubspec.yaml', 'pubspec.lock', 'docs/BUILD.md',
        'scripts/build_android.ps1', 'scripts/prepare_android.ps1',
        'lib/utils/accounts/account_manager/LICENSE', 'assets/shaders/LICENSE',
        '.github/workflows/build.yml',
    }
    require(all(prefix + name in names for name in required), 'Source archive is missing licensing/build materials')
    require(any(name.startswith(prefix + 'lib/scripts/') and name.endswith('.patch') for name in names),
            'Source archive is missing Flutter framework patches')
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


def apk_name(abi: str, version: str, code: int, prerelease: bool, pinned: bool) -> str:
    if not prerelease:
        return f'PiliMinus-{abi}.apk'
    suffix = 'release-signed' if pinned else 'test-signed'
    return f'PiliMinus-{version}+{code}-{abi}-{suffix}.apk'


def release_notes(tag: str, version: str, code: int, commit: str, run: dict,
                  *, prerelease: bool = True, pinned: bool = False) -> str:
    changes = source_changes(commit, version, code)
    if pinned:
        signing = '使用本仓库固定的 Android 发行证书签名。相同包名和证书的安装可以原位升级。'
    else:
        signing = '本包使用临时测试签名，不同构建的证书可能不同。'
    if prerelease:
        channel = '预发布，需在本页手动下载。'
    else:
        channel = f'稳定版，可通过应用内更新或[稳定下载页](https://github.com/{REPOSITORY}/releases/latest)获取。'
    return f'''# Pili-- {tag}

Android **{version}+{code}**。{channel}{signing}

## 本次更新

{changes}

## 下载与升级

- 多数手机使用 `arm64-v8a`，兼容的 32 位 ARM 设备使用 `armeabi-v7a`，x86_64 设备或模拟器使用 `x86_64`。最低 Android 7.0 / API 24。
- 独立安装 ID 为 `{APPLICATION_ID}`，可与上游 PiliPlus 同时安装。
- 早期临时测试包的签名可能不同，Android 会拒绝跨签名覆盖安装。遇到签名冲突，请先备份自己的数据。
- `SHA256SUMS.txt` 提供附件校验值，`BUILD_INFO.json` 记录包名、版本、签名证书摘要及源码提交。

## 来源与验证

- 构建源码为 `{commit}`。[Actions 构建]({run['html_url']}) 已通过回归测试和三个 ABI 的 APK 身份检查。
- 设备验收范围见[验证记录](https://github.com/{REPOSITORY}/blob/{commit}/docs/VALIDATION.md)，其中列出 ARM64 真机和真实账号网页／TV 授权的验证状态。
- `PiliMinus-{version}+{code}-source.tar.gz` 来自该提交，包含 GPL、NOTICE、第三方声明、锁文件、构建脚本与 Flutter 补丁。
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


def list_releases():
    for page in range(1, 21):
        releases = api(f'releases?per_page=100&page={page}')
        yield from releases
        if len(releases) < 100:
            return
    raise ValueError('Too many releases to verify publication history')


def verify_upgrade_path(tag: str, version: str, code: int, pin: str | None, commit: str, run_id: int) -> None:
    candidate = tuple(map(int, version.split('.')))
    for release in list_releases():
        previous_tag = release['tag_name']
        if release['draft'] or previous_tag == tag:
            continue
        if release['prerelease'] and not any(
                item['name'].endswith('-release-signed.apk') for item in release.get('assets', [])):
            continue  # Legacy test certificates were local to individual builds.
        require(bool(pin), 'A maintained signing channel already exists; restore its certificate pin')
        previous = TAG_PATTERN.fullmatch(previous_tag)
        require(previous and bool(previous[2]) == release['prerelease'],
                f'Unrecognized published release: {previous_tag}')
        if not release['prerelease']:
            require(candidate > tuple(map(int, previous[1].split('.'))),
                    f'Stable version must increase from {previous_tag}')
        previous_sha = tag_commit(previous_tag)
        require(previous_sha is not None, f'Missing tag: {previous_tag}')
        previous_version, previous_code = source_version(previous_sha)
        manifest = assets_from_release(release).get('BUILD_INFO.json')
        require(manifest and manifest.get('state') == 'uploaded', f'{previous_tag}: missing signing metadata')
        raw = command('gh', 'api', f'repos/{REPOSITORY}/releases/assets/{int(manifest["id"])}',
                      '-H', 'Accept: application/octet-stream')
        info = json.loads(raw)
        require(previous_version == previous[1] and info.get('release_tag') == previous_tag
                and info.get('source_commit') == previous_sha
                and info.get('version') == f'{previous_version}+{previous_code}'
                and info.get('signing', {}).get('certificate_sha256') == pin,
                f'{previous_tag}: signing history does not match the configured certificate')
        promotes_same_build = (release['prerelease'] and '-' not in tag and commit == previous_sha
                               and info.get('workflow_run_id') == run_id and code == previous_code)
        require(code > previous_code or promotes_same_build,
                f'Android versionCode must increase from {previous_tag} ({previous_code})')


def find_release(tag: str) -> dict | None:
    # Tag lookup omits drafts. Resolve them through the authenticated release collection.
    matches = [release for release in list_releases() if release.get('tag_name') == tag]
    require(len(matches) <= 1, 'Multiple releases use the requested tag; review before publishing')
    return api(f'releases/{matches[0]["id"]}') if matches else None


def publish(tag: str, commit: str, notes: Path, files: list[Path], *,
            prerelease: bool = True, pinned: bool = False) -> str:
    existing_tag = tag_commit(tag)
    require(existing_tag in (None, commit), 'Existing release tag points to different source')
    release = find_release(tag)
    if release is None:
        # The release collection may not immediately include a newly created
        # draft. Use the POST response instead of depending on that index.
        payload = {
            'tag_name': tag, 'target_commitish': commit,
            'name': f'Pili-- {tag}' + ('' if pinned else '（测试签名）'),
            'body': notes.read_text(encoding='utf-8'),
            'draft': True, 'prerelease': prerelease,
        }
        release = json.loads(command(
            'gh', 'api', '--method', 'POST', f'repos/{REPOSITORY}/releases',
            '--input', '-', input_text=json.dumps(payload, ensure_ascii=False)))
        require(isinstance(release.get('id'), int) and release.get('tag_name') == tag,
                'Created release response has an unexpected identity')
    require(release.get('draft') is True, 'Refusing to modify a published release')
    require(release.get('prerelease') is prerelease, 'Existing draft belongs to a different release channel')
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
    require(tag_commit(tag) in (None, commit), 'Release tag changed while uploading assets')
    command('gh', 'release', 'edit', tag, '--repo', REPOSITORY, '--draft=false',
            f'--prerelease={str(prerelease).lower()}', f'--latest={str(not prerelease).lower()}',
            '--notes-file', notes)
    for attempt in range(10):
        published = api(f'releases/{release["id"]}')
        latest = None if prerelease else api('releases/latest', allow_missing=True)
        if (published.get('draft') is False and published.get('prerelease') is prerelease
                and tag_commit(tag) == commit
                and (prerelease or (latest or {}).get('id') == release['id'])):
            break
        if attempt == 9:
            raise ValueError('Published release, tag or latest channel could not be verified')
        time.sleep(2)
    return published['html_url']


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id', required=True, type=int)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--prepare-only', action='store_true', help='Verify and prepare assets without changing any release')
    args = parser.parse_args()
    require(args.run_id > 0, 'Run ID must be positive')
    prerelease, pin, artifact_name = release_settings(args.tag, os.environ.get('ANDROID_RELEASE_CERT_SHA256', ''))
    require(os.environ.get('GH_REPO', REPOSITORY) == REPOSITORY, 'Unexpected GH_REPO')
    require(os.environ.get('GITHUB_REPOSITORY', REPOSITORY) == REPOSITORY, 'Unexpected Actions repository')
    run = api(f'actions/runs/{args.run_id}')
    commit = validate_run(run)
    # Branch names alone persist on runs whose source was later removed from main.
    command('git', 'merge-base', '--is-ancestor', commit, 'refs/remotes/origin/main')
    validate_jobs(api(f'actions/runs/{args.run_id}/jobs?per_page=100'), bool(pin))
    version, code = source_version(commit)
    require(0 < code <= 2100000000 and args.tag.split('-')[0] == f'v{version}',
            'Release tag or versionCode does not match the Android source version')
    verify_upgrade_path(args.tag, version, code, pin, commit, args.run_id)
    artifacts = api(f'actions/runs/{args.run_id}/artifacts?per_page=100')
    selected = [item for item in artifacts.get('artifacts', []) if item['name'] == artifact_name]
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
            '--name', artifact_name, '--dir', downloads)
    expected_originals = {f'app-{abi}-release.apk' for abi in ABIS}
    require({path.relative_to(downloads).as_posix() for path in downloads.rglob('*') if path.is_file()} == expected_originals,
            'Unexpected downloaded APK set')
    require(all((downloads / name).is_file() for name in expected_originals), 'APK artifact layout changed')
    records = []
    apks = []
    for abi in ABIS:
        path = destination / apk_name(abi, version, code, prerelease, bool(pin))
        shutil.copyfile(downloads / f'app-{abi}-release.apk', path)
        records.append(inspect_apk(path, abi, version, code, commit, build_tools))
        apks.append(path)
    signer = verify_signers(records, pin)
    print(command(sys.executable, ROOT / 'scripts/check_android_identity.py',
                  '--aapt', build_tools / 'aapt', *[arg for path in apks for arg in ('--apk', path)]))
    source = source_archive(destination, commit, version, code)
    info = {
        'schema_version': 1, 'release_tag': args.tag, 'prerelease': prerelease,
        'version': f'{version}+{code}', 'source_commit': commit,
        'workflow_run_id': args.run_id, 'workflow_run_url': run['html_url'],
        'workflow_run_updated_at': run['updated_at'], 'artifact_id': selected[0]['id'],
        'artifact_digest': selected[0].get('digest'), 'build_mode': 'release',
        'signing': {
            'kind': 'maintained release signing' if pin else 'CI-generated Android test signing',
            'certificate_sha256': signer,
            'pinned_distribution_signer': bool(pin),
            'in_place_upgrade_requires_matching_certificate': True,
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
    notes.write_text(release_notes(args.tag, version, code, commit, run, prerelease=prerelease, pinned=bool(pin)))
    print(f'Verified assets prepared in {destination}')
    if args.prepare_only:
        return 0
    url = publish(args.tag, commit, notes, files, prerelease=prerelease, pinned=bool(pin))
    print(url)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with Path(summary).open('a') as stream:
            stream.write(f'## Android release\n\n[{args.tag}]({url})\n\n'
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
