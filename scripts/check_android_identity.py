#!/usr/bin/env python3
"""Check source/packaged Android identity without installing or clearing apps."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ANDROID = '{http://schemas.android.com/apk/res/android}'
UPSTREAM_ID = 'com.example.piliplus'
APP_ID = 'io.github.ktclat.piliminus'
ACTIVITY = 'com.example.piliplus.MainActivity'


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def attr(node: ET.Element, name: str, default: str = '') -> str:
    return node.get(ANDROID + name, default)


def check_manifest(root: ET.Element, package: str, *, packaged: bool) -> None:
    if packaged:
        require(root.get('package') == package, 'APK package does not match its expected identity')
    require(not attr(root, 'sharedUserId'), 'sharedUserId can share the app sandbox')
    app = root.find('application')
    require(app is not None, 'Manifest has no application')
    for flag in ('allowBackup', 'fullBackupContent'):
        require(attr(app, flag) == 'false', f'{flag} must be explicitly false')
    for node in [app, *app.findall('activity'), *app.findall('activity-alias')]:
        affinity = attr(node, 'taskAffinity')
        require(not affinity or affinity == package, f'Foreign task affinity: {affinity}')
    authorities: set[str] = set()
    for provider in app.findall('provider'):
        require('BiliDocumentsProvider' not in attr(provider, 'name'), 'Private data DocumentsProvider must remain removed')
        require(attr(provider, 'exported') == 'false', f'Exported provider: {attr(provider, "name")}')
        values = attr(provider, 'authorities').split(';')
        for value in values:
            resolved = value.replace('${applicationId}', package)
            require(resolved.startswith(package + '.'), f'Provider authority is not package-scoped: {resolved}')
            require(resolved not in authorities, f'Duplicate authority: {resolved}')
            authorities.add(resolved)
    for permission in root.findall('permission'):
        name = attr(permission, 'name').replace('${applicationId}', package)
        require(name.startswith(package + '.'), f'Private permission is not package-scoped: {name}')
    actions = [attr(node, 'name') for node in app.findall('.//intent-filter/action')]
    require(UPSTREAM_ID + '.SHORTCUT' not in actions, 'Upstream private shortcut action must not be registered')


def check_shortcuts(root: ET.Element, package: str) -> None:
    intents = root.findall('.//intent')
    require(bool(intents), 'No launcher shortcut intents found')
    for intent in intents:
        # Intent.parseIntent uses non-resource strings for component names.
        # Resolving @string here would falsely pass an unusable launcher intent.
        require(attr(intent, 'targetPackage') == package, 'Shortcut needs a literal targetPackage matching its installed app')
        require(attr(intent, 'targetClass') == ACTIVITY, 'Shortcut needs the literal retained MainActivity class')
        require(attr(intent, 'action') == 'android.intent.action.VIEW', 'Shortcut must use ACTION_VIEW with an explicit component')


def check_source() -> set[str]:
    gradle = (ROOT / 'android/app/build.gradle.kts').read_text()
    app_id = re.search(r'applicationId\s*=\s*"([^"]+)"', gradle)
    require(app_id is not None and app_id[1] == APP_ID, 'Android applicationId must retain the independent Pili-- identity')
    require(APP_ID != UPSTREAM_ID, 'Pili-- cannot use the upstream installation ID')
    namespace = re.search(r'namespace\s*=\s*"([^"]+)"', gradle)
    require(namespace is not None and namespace[1] == UPSTREAM_ID, 'Changing the JNI namespace requires regenerating bindings; do not rename it to applicationId')
    check_manifest(ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml').getroot(), APP_ID, packaged=False)
    shortcuts = ROOT / 'android/app/shortcut_templates/shortcuts.xml'
    require(shortcuts.is_file(), 'No launcher shortcuts template found')
    check_shortcuts(ET.parse(shortcuts).getroot(), '__APPLICATION_ID__')
    require(not list((ROOT / 'android/app/src').glob('*/res/xml*/shortcuts.xml')),
            'Static shortcuts would override or conflict with variant-generated resources')
    values = ET.parse(ROOT / 'android/app/src/main/res/values/string.xml').getroot()
    label = values.find("string[@name='app_name']")
    require(label is not None and label.text == 'Pili--', 'Launcher label must distinguish Pili-- from PiliPlus')
    return {APP_ID, *(APP_ID + suffix for suffix in re.findall(r'applicationIdSuffix\s*=\s*"([^"]+)"', gradle))}


def parse_xmltree(output: str) -> ET.Element:
    """Read the XML nodes/attributes printed by Android's aapt or aapt2."""
    stack: list[tuple[int, ET.Element]] = []
    root = None
    for line in output.splitlines():
        element = re.match(r'^(\s*)E: ([^\s(]+)', line)
        if element:
            depth = len(element[1])
            node = ET.Element(element[2])
            while stack and stack[-1][0] >= depth:
                stack.pop()
            if stack:
                stack[-1][1].append(node)
            else:
                require(root is None, 'Multiple roots in aapt XML output')
                root = node
            stack.append((depth, node))
            continue
        attribute = re.match(r'\s*A: ([^\s(=]+)(?:\(0x[0-9a-fA-F]+\))?=(.*)', line)
        if not attribute or not stack:
            continue
        name, raw = attribute.groups()
        if name.startswith('android:'):
            name = ANDROID + name.removeprefix('android:')
        elif name.startswith('http://schemas.android.com/apk/res/android:'):
            name = ANDROID + name.removeprefix('http://schemas.android.com/apk/res/android:')
        quoted = re.search(r'"(?:\\.|[^"\\])*"', raw)
        if quoted:
            value = json.loads(quoted[0])
        elif raw.startswith('(type 0x12)'):
            value = 'false' if int(raw.split(')')[1], 16) == 0 else 'true'
        else:
            value = raw.strip()
        stack[-1][1].set(name, value)
    require(root is not None, 'Could not parse aapt XML output')
    return root


def xml_resources(output: str) -> dict[str, set[str]]:
    """Resolve resource IDs to all XML configurations, including shrunk paths."""
    files: dict[str, set[str]] = {}
    current = None
    for line in output.splitlines():
        resource = re.search(r'\bresource (0x[0-9a-fA-F]+)\s+(?:[^\s:]+:)?([^\s:]+/[^\s:]+)', line)
        if resource:
            current = resource[1] if resource[2].startswith('xml/') else None
        elif current:
            # aapt2 prints (file) res/K7.xml; aapt prints (string8) "res/K7.xml".
            path = re.search(r'\(file\)\s+(res/\S+)', line)
            quoted = re.search(r'"(?:\\.|[^"\\])*"', line)
            value = path[1] if path else json.loads(quoted[0]) if quoted else ''
            if value.startswith('res/') and value.endswith('.xml'):
                files.setdefault('@' + current, set()).add(value)
    return files


def shortcut_files(manifest: ET.Element, files: dict[str, set[str]]) -> set[str]:
    metadata = [node for node in manifest.findall('.//meta-data')
                if attr(node, 'name') == 'android.app.shortcuts']
    require(bool(metadata), 'APK has no launcher shortcuts metadata')
    result: set[str] = set()
    for node in metadata:
        reference = attr(node, 'resource')
        paths = files.get(reference, set())
        require(bool(paths), f'Cannot resolve launcher shortcuts resource: {reference}')
        result.update(paths)
    return result


def find_aapt(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit)
        require(path.is_file(), f'aapt not found: {path}')
        return path
    candidates = []
    for variable in ('ANDROID_HOME', 'ANDROID_SDK_ROOT'):
        sdk = os.environ.get(variable)
        if sdk:
            candidates.extend((Path(sdk) / 'build-tools').glob('*/aapt*'))
    candidates = [p for p in candidates if p.name in ('aapt', 'aapt.exe', 'aapt2', 'aapt2.exe')]
    if candidates:
        return max(candidates, key=lambda p: (tuple(map(int, re.findall(r'\d+', p.parent.name))), p.name.startswith('aapt2')))
    for name in ('aapt2', 'aapt'):
        found = shutil.which(name)
        if found:
            return Path(found)
    raise ValueError('Set ANDROID_HOME/ANDROID_SDK_ROOT or pass --aapt /path/to/build-tools/VERSION/aapt2')


def check_apk(apk: Path, aapt: Path, allowed_packages: set[str]) -> str:
    require(apk.is_file(), f'APK not found: {apk}')
    modern = aapt.stem == 'aapt2'

    def dump(kind: str, file: str | None = None) -> str:
        if kind == 'xmltree':
            arguments = ['dump', 'xmltree', '--file', file, str(apk)] if modern else ['dump', 'xmltree', str(apk), file]
        else:
            arguments = ['dump', 'resources', str(apk)] if modern else ['dump', '--values', 'resources', str(apk)]
        result = subprocess.run([str(aapt), *arguments], text=True, capture_output=True, check=True)
        return result.stdout

    manifest = parse_xmltree(dump('xmltree', 'AndroidManifest.xml'))
    package = manifest.get('package', '')
    require(package in allowed_packages, f'Unexpected APK package: {package}')
    check_manifest(manifest, package, packaged=True)
    resources = dump('resources')
    shortcuts = shortcut_files(manifest, xml_resources(resources))
    with zipfile.ZipFile(apk) as archive:
        require(shortcuts.issubset(set(archive.namelist())), 'APK is missing a referenced launcher shortcuts XML file')
    for file in sorted(shortcuts):
        check_shortcuts(parse_xmltree(dump('xmltree', file)), package)
    return package


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, action='append', default=[], help='Inspect a built APK; repeat for multiple ABIs/variants')
    parser.add_argument('--aapt', help='Android SDK aapt/aapt2 path (otherwise discover from SDK environment/PATH)')
    args = parser.parse_args()
    try:
        packages = check_source()
        print('PASS: source identity, backup isolation and explicit launcher shortcuts')
        if args.apk:
            aapt = find_aapt(args.aapt)
            for apk in args.apk:
                package = check_apk(apk, aapt, packages)
                print(f'PASS: {apk.name}: {package}; package-scoped providers and compiled shortcut targets')
        else:
            print('APK contents were not checked; pass --apk after building to include merged plugin providers.')
    except (OSError, ValueError, ET.ParseError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
