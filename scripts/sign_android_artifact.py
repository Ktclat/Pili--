"""Re-sign the three verified CI APKs using the repository owner's certificate."""
import argparse
import base64
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from publish_android_prerelease import ABIS, command, inspect_apk, require, source_version


def sign_packages(source: Path, destination: Path) -> None:
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    require(bool(sdk), 'Android build tools 37.0.0 are required')
    build_tools = Path(sdk) / 'build-tools/37.0.0'
    pin = os.environ.get('ANDROID_RELEASE_CERT_SHA256', '').lower()
    require(re.fullmatch(r'[0-9a-f]{64}', pin), 'Expected a SHA-256 certificate fingerprint')
    alias = os.environ.get('ANDROID_RELEASE_KEY_ALIAS')
    encoded = os.environ.pop('ANDROID_RELEASE_KEYSTORE_BASE64', '')
    require(all((alias, encoded, os.environ.get('ANDROID_RELEASE_STORE_PASSWORD'),
                 os.environ.get('ANDROID_RELEASE_KEY_PASSWORD'))), 'Missing distribution signing configuration')
    version_commit = command('git', 'rev-parse', 'HEAD').strip()
    version, code = source_version(version_commit)
    filenames = {f'app-{abi}-release.apk': abi for abi in ABIS}
    require({path.name for path in source.iterdir()} == set(filenames), 'Unexpected input APK set')
    require(not destination.exists(), 'Output directory already exists')

    # Keep the key out of the checkout and discard all outputs if any check fails.
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        working = Path(temporary)
        keystore = working / 'signing.keystore'
        keystore.write_bytes(base64.b64decode(encoded, validate=True))
        output = working / 'apks'
        output.mkdir()
        for name, abi in filenames.items():
            original, signed = source / name, output / name
            require(original.is_file() and not original.is_symlink(), f'Expected a regular APK: {name}')
            inspect_apk(original, abi, version, code, version_commit, build_tools)
            subprocess.run([
                build_tools / 'apksigner', 'sign', '--ks', keystore, '--ks-key-alias', alias,
                '--ks-pass', 'env:ANDROID_RELEASE_STORE_PASSWORD',
                '--key-pass', 'env:ANDROID_RELEASE_KEY_PASSWORD',
                '--v4-signing-enabled', 'false', '--out', signed, original,
            ], check=True)
            verified = inspect_apk(signed, abi, version, code, version_commit, build_tools)
            require(verified['signer_certificate_sha256'] == pin, 'APK signer differs from the distribution certificate')
        output.rename(destination)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input_directory', type=Path)
    parser.add_argument('output_directory', type=Path)
    args = parser.parse_args()
    try:
        sign_packages(args.input_directory.resolve(), args.output_directory.resolve())
    except (KeyError, OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
