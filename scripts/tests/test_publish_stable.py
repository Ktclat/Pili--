"""Exercise public release channels without network access or signing credentials."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    'publisher', Path(__file__).resolve().parents[1] / 'publish_android_prerelease.py'
)
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)
PIN = 'f' * 64
SHA = 'a' * 40


class StableReleaseTests(unittest.TestCase):
    def test_source_archive_rejects_android_keystores_in_any_directory_or_case(self):
        for name in ('keys/signing.JkS', 'upload.kEyStOrE', 'certs/store.p12', 'store.P12',
                     'android/keys/backup.PfX', 'android/Key.Properties'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                with patch.object(publisher, 'ROOT', root):
                    publisher.command('git', 'init', '-q')
                    store = root / name
                    store.parent.mkdir(parents=True, exist_ok=True)
                    store.touch()
                    publisher.command('git', 'add', '--force', '--', name)
                    tree = publisher.command('git', 'write-tree').strip()
                    with self.assertRaisesRegex(ValueError, 'signing files'):
                        publisher.source_archive(root, tree, '0.6.2', 9)
                self.assertEqual(list(root.glob('*.tar.gz')), [])

    def test_channel_requires_the_correct_signing_artifact(self):
        for tag in ('v0.6.2', 'v0.6.2-beta.1'):
            with self.subTest(tag=tag):
                prerelease, pin, artifact = publisher.release_settings(tag, PIN.upper())
                self.assertEqual(prerelease, 'beta' in tag)
                self.assertEqual(pin, PIN)
                self.assertEqual(artifact, publisher.SIGNED_ARTIFACT)
        self.assertEqual(publisher.release_settings('v0.6.2-rc.1', ''),
                         (True, None, publisher.TEST_ARTIFACT))
        for tag, pin in [('v0.6.2', ''), ('v0.6.2', 'aabb'), ('v0.6.2-beta.1', 'aabb'),
                         ('v0.6.02', PIN), ('v0.6.2-SNAPSHOT', PIN)]:
            with self.subTest(tag=tag, pin=pin), self.assertRaises(ValueError):
                publisher.release_settings(tag, pin)

    def test_unconfigured_optional_signing_job_only_skips_for_test_channel(self):
        def jobs(status='skipped', build_status='success'):
            return {'total_count': 2, 'jobs': [
                {'name': 'android', 'conclusion': build_status, 'status': 'completed'},
                {'name': publisher.SIGN_JOB, 'conclusion': status, 'status': 'completed'},
            ]}
        publisher.validate_jobs(jobs(), False)
        publisher.validate_jobs(jobs('success'), True)
        for response, pinned in [(jobs(), True), (jobs('failure'), False),
                                 (jobs('success', 'skipped'), True)]:
            with self.subTest(response=response), self.assertRaises(ValueError):
                publisher.validate_jobs(response, pinned)

    def test_all_apks_must_match_the_pin_and_have_architecture_stable_names(self):
        for abi in publisher.ABIS:
            self.assertEqual(publisher.apk_name(abi, '0.6.2', 9, False, True), f'PiliMinus-{abi}.apk')
        self.assertIn('release-signed', publisher.apk_name('x86_64', '0.6.2', 9, True, True))
        self.assertIn('test-signed', publisher.apk_name('x86_64', '0.6.2', 9, True, False))
        records = [{'signer_certificate_sha256': PIN}] * 3
        self.assertEqual(publisher.verify_signers(records, PIN), PIN)
        for invalid in ([{'signer_certificate_sha256': 'd' * 64}] * 3,
                        records[:2] + [{'signer_certificate_sha256': 'd' * 64}]):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                publisher.verify_signers(invalid, PIN)

    def test_stable_version_code_and_signer_must_continue_public_history(self):
        previous = {'draft': False, 'prerelease': False, 'tag_name': 'v0.6.2', 'id': 12}
        previous_info = {'release_tag': 'v0.6.2', 'source_commit': SHA, 'version': '0.6.2+9',
                         'signing': {'certificate_sha256': PIN}}
        with patch.object(publisher, 'list_releases', return_value=[previous]), \
                patch.object(publisher, 'tag_commit', return_value=SHA), \
                patch.object(publisher, 'source_version', return_value=('0.6.2', 9)), \
                patch.object(publisher, 'assets_from_release', return_value={'BUILD_INFO.json':
                             {'id': 42, 'state': 'uploaded'}}), \
                patch.object(publisher, 'command', return_value=json.dumps(previous_info)):
            publisher.verify_upgrade_path('v0.6.3', '0.6.3', 10, PIN, 'b' * 40, 19)
            for version, code, pin in [('0.6.2', 10, PIN), ('0.5.0', 20, PIN),
                                       ('0.6.3', 9, PIN), ('0.6.3', 11, 'd' * 64)]:
                with self.subTest(version=version, code=code, pin=pin), self.assertRaises(ValueError):
                    publisher.verify_upgrade_path(f'v{version}-rc.1', version, code, pin, 'b' * 40, 19)

    def test_promoting_the_same_signed_beta_build_preserves_upgrade_continuity(self):
        tag = 'v0.6.2-beta.1'
        beta = {'draft': False, 'prerelease': True, 'tag_name': tag, 'id': 12,
                'assets': [{'name': 'PiliMinus-0.6.2+9-arm64-v8a-release-signed.apk'}]}
        info = {'release_tag': tag, 'source_commit': SHA, 'version': '0.6.2+9', 'workflow_run_id': 15,
                'signing': {'certificate_sha256': PIN}}
        with patch.object(publisher, 'list_releases', return_value=[beta]), \
                patch.object(publisher, 'tag_commit', return_value=SHA), \
                patch.object(publisher, 'source_version', return_value=('0.6.2', 9)), \
                patch.object(publisher, 'assets_from_release', return_value={
                    'BUILD_INFO.json': {'id': 42, 'state': 'uploaded'}}), \
                patch.object(publisher, 'command', return_value=json.dumps(info)):
            publisher.verify_upgrade_path('v0.6.2', '0.6.2', 9, PIN, SHA, 15)
            with self.assertRaises(ValueError):
                publisher.verify_upgrade_path('v0.6.2', '0.6.2', 9, PIN, SHA, 16)
            with self.assertRaises(ValueError):
                publisher.verify_upgrade_path('v0.6.2-beta.2', '0.6.2', 10, None, SHA, 16)

    def test_stable_publication_sets_latest_and_verifies_the_tag(self):
        tag = 'v0.6.2'
        draft = {'id': 5, 'tag_name': tag, 'target_commitish': SHA, 'draft': True, 'prerelease': False}
        published = {**draft, 'draft': False, 'html_url': 'https://example.test/release'}
        with tempfile.TemporaryDirectory() as folder:
            notes = Path(folder) / 'notes.md'
            notes.write_text('Test release notes.')
            with patch.object(publisher, 'tag_commit', side_effect=[None, None, SHA]), \
                    patch.object(publisher, 'find_release', return_value=None), \
                    patch.object(publisher, 'assets_from_release', return_value={}), \
                    patch.object(publisher, 'api', return_value=published) as api, \
                    patch.object(publisher, 'command', return_value=json.dumps(draft)) as cli:
                url = publisher.publish(tag, SHA, notes, [], prerelease=False, pinned=True)
                self.assertEqual(url, published['html_url'])
                self.assertIn('--latest=true', cli.call_args_list[-1].args)
                self.assertIn('--prerelease=false', cli.call_args_list[-1].args)
                self.assertFalse(json.loads(cli.call_args_list[0].kwargs['input_text'])['prerelease'])
                api.assert_any_call('releases/latest', allow_missing=True)
            for immutable in [{**draft, 'draft': False}, {**draft, 'prerelease': True}]:
                with patch.object(publisher, 'tag_commit', return_value=SHA), \
                     patch.object(publisher, 'find_release', return_value=immutable), \
                     patch.object(publisher, 'command') as cli, self.assertRaises(ValueError):
                    publisher.publish(tag, SHA, notes, [], prerelease=False, pinned=True)
                cli.assert_not_called()


if __name__ == '__main__':
    unittest.main()
