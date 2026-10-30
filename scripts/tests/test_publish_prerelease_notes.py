"""Keep published notes tied to the APK source and its complete version."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    'publisher', Path(__file__).resolve().parents[1] / 'publish_android_prerelease.py'
)
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)


class PrereleaseNotesTests(unittest.TestCase):
    def test_build_number_and_core_version_must_match_exactly(self):
        changelog = '''# Changes
## 0.6.0+70 — next build
- Wrong build number.
## 0.6.0+7 — current
- Current navigation behavior.
## 0.6.1+7 — next version
- Wrong core version.
'''
        self.assertEqual(publisher.extract_changelog_entry(changelog, '0.6.0', 7),
                         '- Current navigation behavior.')

    def test_subsections_are_preserved_but_next_release_is_excluded(self):
        changelog = '''## 0.6.0+7 — Beta
### Navigation
- Dragging previews without changing pages.

### Validation
- Device acceptance is recorded separately.

## Previous release
- Must stay out of the new notes.
'''
        body = publisher.extract_changelog_entry(changelog, '0.6.0', 7)
        self.assertIn('### Navigation', body)
        self.assertIn('### Validation', body)
        self.assertNotIn('Previous release', body)
        self.assertNotIn('Must stay out', body)

    def test_missing_empty_and_duplicate_entries_refuse_publication(self):
        for changelog in (
            '## 0.6.0+70\n- Another build.\n',
            '## 0.6.0+7\n\n## 0.5.0+6\n- Previous changes.\n',
            '## 0.6.0+7\n<!-- TODO -->\n### Changes\n',
            '## 0.6.0+7\n- First.\n## 0.6.0+7\n- Second.\n',
        ):
            with self.subTest(changelog=changelog), self.assertRaises(ValueError):
                publisher.extract_changelog_entry(changelog, '0.6.0', 7)

    def test_notes_use_the_build_commit_instead_of_the_working_tree(self):
        commit = 'a' * 40
        with patch.object(publisher, 'command', return_value='## 0.6.0+7\n- Built source changes.\n') as command:
            notes = publisher.release_notes('v0.6.0-beta.1', '0.6.0', 7, commit,
                                            {'html_url': 'https://example.test/build'})
        command.assert_called_once_with('git', 'show', f'{commit}:CHANGELOG.md')
        self.assertIn('- Built source changes.', notes)
        self.assertIn(commit, notes)
        self.assertIn('测试签名', notes)
        self.assertIn('真实账号网页／TV 授权', notes)


if __name__ == '__main__':
    unittest.main()
