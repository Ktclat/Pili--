"""Operate an installed APK and save real UI evidence (no mocked app services).

Examples:
  python scripts/android_acceptance.py --serial emulator-5556 snapshot home
  python scripts/android_acceptance.py --serial emulator-5556 tap 扫一扫
  python scripts/android_acceptance.py --serial emulator-5556 fixtures

Fixtures additionally require qrcode and Pillow. Never clears app data,
logs into an account, submits a purchase, or changes a performance baseline.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET


class Device:
    def __init__(self, serial, out):
        self.serial, self.out = serial, Path(out)
        self.out.mkdir(parents=True, exist_ok=True)

    def adb(self, *args, binary=False):
        result = subprocess.run(
            ['adb', '-s', self.serial, *args], check=True,
            capture_output=True, timeout=30,
        ).stdout
        return result if binary else result.decode('utf-8', errors='replace')

    def ui(self):
        self.adb('shell', 'uiautomator', 'dump', '/sdcard/piliminus-acceptance.xml')
        raw = self.adb('exec-out', 'cat', '/sdcard/piliminus-acceptance.xml')
        return raw, ET.fromstring(raw)

    def snapshot(self, name):
        # Let the native activity transition finish before collecting evidence.
        time.sleep(1)
        raw, root = self.ui()
        (self.out / f'{name}.xml').write_text(raw, encoding='utf-8')
        (self.out / f'{name}.png').write_bytes(self.adb('exec-out', 'screencap', '-p', binary=True))
        labels = [n.get('text') or n.get('content-desc') for n in root.iter('node')]
        print(json.dumps([label for label in labels if label], ensure_ascii=False))

    def tap(self, label):
        _, root = self.ui()
        found = [n for n in root.iter('node') if label in (n.get('text'), n.get('content-desc'))]
        if not found:
            raise AssertionError(f'Visible UI element not found: {label}')
        node = next((n for n in found if n.get('clickable') == 'true'), found[0])
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
        self.adb('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
        print(f'Tapped visible UI: {label}')

    def fixtures(self):
        import qrcode
        from PIL import Image
        fixtures = {
            'bilibili': 'https://www.bilibili.com/video/BV1xx411c7mD',
            'text': 'Pili-- offline QR acceptance',
            'unsafe': 'javascript:alert(1)',
            'lookalike': 'https://bilibili.com.example.org/video/BV1xx411c7mD',
        }
        folder = self.out / 'fixtures'
        folder.mkdir(exist_ok=True)
        self.adb('shell', 'mkdir', '-p', '/sdcard/Pictures/PiliMinusAcceptance')
        for name, value in fixtures.items():
            file = folder / f'{name}.png'
            qrcode.make(value, box_size=16, border=4).save(file)
            target = f'/sdcard/Pictures/PiliMinusAcceptance/{file.name}'
            self.adb('push', str(file), target)
            self.adb('shell', 'am', 'broadcast', '-a', 'android.intent.action.MEDIA_SCANNER_SCAN_FILE', '-d', f'file://{target}')
        file = folder / 'blank.png'
        Image.new('RGB', (800, 800), 'white').save(file)
        self.adb('push', str(file), '/sdcard/Pictures/PiliMinusAcceptance/blank.png')
        (folder / 'contents.json').write_text(json.dumps(fixtures, indent=2), encoding='utf-8')
        print(f'Created real QR images in {folder.resolve()}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--out', default='.artifacts/acceptance')
    parser.add_argument('action', choices=['snapshot', 'tap', 'fixtures', 'back'])
    parser.add_argument('value', nargs='?')
    args = parser.parse_args()
    device = Device(args.serial, args.out)
    if args.action == 'snapshot':
        device.snapshot(args.value or str(int(time.time())))
    elif args.action == 'tap':
        device.tap(args.value)
    elif args.action == 'fixtures':
        device.fixtures()
    else:
        device.adb('shell', 'input', 'keyevent', 'KEYCODE_BACK')


if __name__ == '__main__':
    main()
