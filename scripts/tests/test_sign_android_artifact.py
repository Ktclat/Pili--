import base64
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sign_android_artifact as signing


class DistributionSigningTests(unittest.TestCase):
    def test_wrong_certificate_on_last_abi_leaves_no_distributable_files(self):
        pin = '1' * 64
        environment = {
            'ANDROID_HOME': '/test/sdk',
            'ANDROID_RELEASE_CERT_SHA256': pin,
            'ANDROID_RELEASE_KEYSTORE_BASE64': base64.b64encode(b'test fixture').decode(),
            'ANDROID_RELEASE_KEY_ALIAS': 'test',
            'ANDROID_RELEASE_STORE_PASSWORD': 'test',
            'ANDROID_RELEASE_KEY_PASSWORD': 'test',
        }
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            inputs, output = root / 'input', root / 'output'
            inputs.mkdir()
            for abi in signing.ABIS:
                (inputs / f'app-{abi}-release.apk').touch()

            def sign(args, **kwargs):
                self.assertNotIn(environment['ANDROID_RELEASE_KEYSTORE_BASE64'], args)
                Path(args[args.index('--out') + 1]).write_bytes(b'signed fixture')

            def inspect(path, abi, *args):
                fingerprint = pin if path.parent == inputs or abi != signing.ABIS[-1] else '2' * 64
                return {'signer_certificate_sha256': fingerprint}

            with patch.dict(os.environ, environment), patch.object(signing, 'command', return_value='a' * 40), \
                 patch.object(signing, 'source_version', return_value=('0.6.2', 9)), \
                 patch.object(signing, 'inspect_apk', side_effect=inspect), \
                 patch.object(signing.subprocess, 'run', side_effect=sign):
                with self.assertRaisesRegex(ValueError, 'differs from'):
                    signing.sign_packages(inputs, output)
            self.assertEqual(list(root.iterdir()), [inputs])
