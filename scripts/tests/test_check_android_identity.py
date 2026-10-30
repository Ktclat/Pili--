"""Regression cases for package/provider and explicit shortcut isolation."""
import importlib.util
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

SPEC = importlib.util.spec_from_file_location(
    'identity', Path(__file__).resolve().parents[1] / 'check_android_identity.py'
)
identity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(identity)


class AndroidIdentityTests(unittest.TestCase):
    def manifest(self, *, package=identity.APP_ID, authorities=None, exported='false'):
        authorities = authorities or package + '.flutter.share_provider'
        return ET.fromstring(f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android"
            package="{package}">
            <application android:allowBackup="false" android:fullBackupContent="false">
                <provider android:name="plugin.ShareProvider" android:authorities="{authorities}"
                    android:exported="{exported}" />
            </application>
        </manifest>''')

    def test_release_and_debug_provider_sandboxes_are_distinct(self):
        for suffix in ('', '.debug', '.dev'):
            package = identity.APP_ID + suffix
            identity.check_manifest(self.manifest(package=package), package, packaged=True)

    def test_upstream_authority_and_prefix_lookalike_are_rejected(self):
        for authority in (identity.UPSTREAM_ID + '.provider', identity.APP_ID + 'x.provider'):
            with self.assertRaisesRegex(ValueError, 'authority is not package-scoped'):
                identity.check_manifest(self.manifest(authorities=authority), identity.APP_ID, packaged=True)

    def test_exported_provider_cannot_expose_private_app_files(self):
        with self.assertRaisesRegex(ValueError, 'Exported provider'):
            identity.check_manifest(self.manifest(exported='true'), identity.APP_ID, packaged=True)

    def test_shared_uid_is_rejected_even_with_independent_package(self):
        root = self.manifest()
        root.set(identity.ANDROID + 'sharedUserId', identity.UPSTREAM_ID)
        with self.assertRaisesRegex(ValueError, 'sharedUserId'):
            identity.check_manifest(root, identity.APP_ID, packaged=True)

    def test_explicit_shortcuts_follow_the_installed_variant(self):
        for suffix in ('', '.debug', '.dev'):
            package = identity.APP_ID + suffix
            root = ET.fromstring(f'''<shortcuts xmlns:android="http://schemas.android.com/apk/res/android">
                <shortcut><intent android:action="android.intent.action.VIEW"
                    android:targetPackage="{package}" android:targetClass="{identity.ACTIVITY}"
                    android:data="bilibili://search" /></shortcut></shortcuts>''')
            identity.check_shortcuts(root, package)
            with self.assertRaisesRegex(ValueError, 'targetPackage'):
                identity.check_shortcuts(root, identity.UPSTREAM_ID)
            root.find('.//intent').attrib.pop(identity.ANDROID + 'targetPackage')
            with self.assertRaisesRegex(ValueError, 'targetPackage'):
                identity.check_shortcuts(root, package)

    def test_shortcut_component_resource_references_are_rejected(self):
        for target in ('@string/shortcut_target_package', '@0x7f1100b6', '@2131820726'):
            root = ET.fromstring(f'''<shortcuts xmlns:android="http://schemas.android.com/apk/res/android">
                <shortcut><intent android:action="android.intent.action.VIEW"
                    android:targetPackage="{target}" android:targetClass="{identity.ACTIVITY}" />
                </shortcut></shortcuts>''')
            with self.assertRaisesRegex(ValueError, 'literal targetPackage'):
                identity.check_shortcuts(root, identity.APP_ID)

    def test_android_xml_dump_includes_binary_boolean_and_resource_reference(self):
        root = identity.parse_xmltree('''N: android=http://schemas.android.com/apk/res/android
  E: manifest (line=1)
    A: package="io.github.ktclat.piliminus" (Raw: "io.github.ktclat.piliminus")
    E: application (line=2)
      A: android:allowBackup(0x01010280)=(type 0x12)0x0
      A: android:fullBackupContent(0x010104eb)=(type 0x12)0x0
      A: android:label(0x01010001)=@0x7f100001
      E: provider (line=3)
        A: android:name(0x01010003)="plugin.ShareProvider"
        A: android:authorities(0x01010018)="io.github.ktclat.piliminus.share"
        A: android:exported(0x01010010)=(type 0x12)0x0
''')
        identity.check_manifest(root, identity.APP_ID, packaged=True)
        self.assertEqual(identity.attr(root.find('application'), 'label'), '@0x7f100001')

    def test_aapt2_expanded_namespace_and_plain_boolean(self):
        root = identity.parse_xmltree('''N: android=http://schemas.android.com/apk/res/android (line=1)
  E: manifest (line=1)
    A: package="io.github.ktclat.piliminus"
      E: application (line=1)
        A: http://schemas.android.com/apk/res/android:allowBackup(0x01010280)=false
        A: http://schemas.android.com/apk/res/android:fullBackupContent(0x010104eb)=false
          E: provider (line=1)
            A: http://schemas.android.com/apk/res/android:name(0x01010003)="plugin.ShareProvider"
            A: http://schemas.android.com/apk/res/android:exported(0x01010010)=false
            A: http://schemas.android.com/apk/res/android:authorities(0x01010018)="io.github.ktclat.piliminus.share"
''')
        identity.check_manifest(root, identity.APP_ID, packaged=True)

    def test_shortcuts_follow_metadata_id_after_resource_path_shortening(self):
        manifest = self.manifest()
        ET.SubElement(manifest.find('application'), 'meta-data', {
            identity.ANDROID + 'name': 'android.app.shortcuts',
            identity.ANDROID + 'resource': '@0x7f140004',
        })
        for dump in ('''    resource 0x7f140004 xml/shortcuts
      (v25) (file) res/K7.xml type=XML
      (v26) (file) res/qZ.xml type=XML
    resource 0x7f140005 xml/other
      () (file) res/xml/shortcuts.xml type=XML
''', '''    spec resource 0x7f140004 io.github.ktclat.piliminus:xml/shortcuts: flags=0x00000000
      config v25:
        resource 0x7f140004 io.github.ktclat.piliminus:xml/shortcuts: t=0x03 d=0x00000149
          (string8) "res/K7.xml"
      config v26:
        resource 0x7f140004 io.github.ktclat.piliminus:xml/shortcuts: t=0x03 d=0x00000150
          (string8) "res/qZ.xml"
'''):
            self.assertEqual(identity.shortcut_files(manifest, identity.xml_resources(dump)), {'res/K7.xml', 'res/qZ.xml'})

    def test_missing_shortcuts_resource_is_rejected(self):
        manifest = self.manifest()
        ET.SubElement(manifest.find('application'), 'meta-data', {
            identity.ANDROID + 'name': 'android.app.shortcuts',
            identity.ANDROID + 'resource': '@0x7f140004',
        })
        with self.assertRaisesRegex(ValueError, 'Cannot resolve'):
            identity.shortcut_files(manifest, {'@0x7f140005': {'res/xml/shortcuts.xml'}})


if __name__ == '__main__':
    unittest.main()
