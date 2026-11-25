import base64
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import configure_android_signing as signing


class ConfigureSigningTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'fixture.jks'
        self.path.write_bytes(b'mock private keystore')
        self.pin = None
        self.fail_command = None
        self.calls = []
        self.cert = b'mock public certificate'
        self.digest = hashlib.sha256(self.cert).hexdigest()
        self.store_pass = 'private store password'
        self.key_pass = 'private key password'
        self.alias = 'fixture-alias'
        self.output = io.StringIO()
        self.enterContext(redirect_stdout(self.output))
        self.enterContext(patch.object(signing.getpass, 'getpass',
                                       side_effect=[self.store_pass, self.key_pass]))
        self.enterContext(patch.object(signing.subprocess, 'run', side_effect=self.mock_command))

    def mock_command(self, args, **kwargs):
        self.calls.append((args, kwargs))
        out = b''
        if args[:3] == ['gh', 'api', '--paginate'] and self.pin is not None:
            out = json.dumps({'value': self.pin}).encode()
        elif '-exportcert' in args:
            out = self.cert
        failed = self.fail_command in args if self.fail_command is not None else False
        return subprocess.CompletedProcess(args, int(failed), out,
                                           self.store_pass.encode() if failed else b'')

    def test_provisions_from_stdin_then_creates_pin(self):
        signing.configure(self.path, self.alias)
        writes = [(args, kwargs) for args, kwargs in self.calls if args[:2] == ['gh', 'secret']]
        self.assertEqual({args[3]: kwargs['input'] for args, kwargs in writes}, {
            'ANDROID_RELEASE_KEYSTORE_BASE64': base64.b64encode(self.path.read_bytes()),
            'ANDROID_RELEASE_STORE_PASSWORD': self.store_pass.encode(),
            'ANDROID_RELEASE_KEY_ALIAS': self.alias.encode(),
            'ANDROID_RELEASE_KEY_PASSWORD': self.key_pass.encode(),
        })
        self.assertEqual(self.calls[-1][0][:4], ['gh', 'api', '--method', 'POST'])
        self.assertIn('value=' + self.digest, self.calls[-1][0])
        for args, kwargs in self.calls:
            for password in (self.store_pass, self.key_pass):
                self.assertNotIn(password, args)
                self.assertNotIn(password, self.output.getvalue())
            if args[0] == 'gh':
                self.assertNotIn(self.alias, args)
                self.assertIsNone(kwargs.get('env'))
        self.assertNotIn(self.alias, self.output.getvalue())

    def test_existing_matching_pin_is_preserved(self):
        self.pin = self.digest
        signing.configure(self.path, self.alias)
        self.assertEqual(self.calls[-1][0][3], 'ANDROID_RELEASE_KEY_PASSWORD')

    def test_different_pin_stops_before_writing(self):
        self.pin = '0' * 64
        with self.assertRaisesRegex(RuntimeError, '指纹'):
            signing.configure(self.path, self.alias)
        self.assertFalse(any(args[:2] == ['gh', 'secret'] for args, _ in self.calls))

    def test_variable_read_failure_is_not_an_empty_pin(self):
        self.fail_command = '--paginate'
        with self.assertRaisesRegex(RuntimeError, 'Variables'):
            signing.configure(self.path, self.alias)
        self.assertEqual(len(self.calls), 1)

    def test_wrong_key_password_stops_before_uploading_any_secret(self):
        self.fail_command = '-certreq'
        with self.assertRaises(RuntimeError) as caught:
            signing.configure(self.path, self.alias)
        self.assertFalse(any(args[:2] == ['gh', 'secret'] for args, _ in self.calls))
        self.assertNotIn(self.store_pass, str(caught.exception))

    def test_partial_failure_leaves_pin_unset_and_hides_child_diagnostics(self):
        self.fail_command = 'ANDROID_RELEASE_KEY_ALIAS'
        with self.assertRaises(RuntimeError) as caught:
            signing.configure(self.path, self.alias)
        self.assertEqual(self.calls[-1][0][3], 'ANDROID_RELEASE_KEY_ALIAS')
        self.assertNotIn(self.store_pass, str(caught.exception))
        self.assertNotIn(self.store_pass, self.output.getvalue())
