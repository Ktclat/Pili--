"""Exercise the native Android authorization inbox with the build JDK."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
PACKAGE = Path("com/example/piliplus")


class ExternalAuthorizationTests(unittest.TestCase):
    def test_dedicated_action_has_its_own_official_https_filter(self):
        manifest = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml")
        ns = {"a": "http://schemas.android.com/apk/res/android"}
        action = "io.github.ktclat.piliminus.action.AUTHORIZE_LOGIN"
        filters = [
            entry for entry in manifest.findall(".//activity/intent-filter")
            if entry.find(f"action[@a:name='{action}']", ns) is not None
        ]
        self.assertEqual(len(filters), 1)
        entry = filters[0]
        name = "{%s}name" % ns["a"]
        self.assertEqual([item.get(name) for item in entry.findall("action")], [action])
        self.assertEqual([item.get(name) for item in entry.findall("category")], ["android.intent.category.DEFAULT"])
        self.assertEqual(
            {(item.get("{%s}scheme" % ns["a"]), item.get("{%s}host" % ns["a"])) for item in entry.findall("data")},
            {("https", "account.bilibili.com"), ("https", "passport.bilibili.com")},
        )

    def test_native_targets_expiry_and_single_use(self):
        sources = [
            ROOT / "android/app/src/main/java" / PACKAGE / "ExternalLoginAuthorization.java",
            Path(__file__).parent / "java/ExternalLoginAuthorizationTest.java",
        ]
        with tempfile.TemporaryDirectory() as classes:
            subprocess.run(["javac", "-d", classes, *sources], check=True)
            subprocess.run(
                ["java", "-cp", classes, "com.example.piliplus.ExternalLoginAuthorizationTest"],
                check=True,
            )
