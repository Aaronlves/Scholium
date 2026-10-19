#!/usr/bin/env python3
"""Regression checks for update signing and static-feed publication boundaries."""

from __future__ import annotations

import base64
import importlib.util
import io
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True


def module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Tools/Scripts" / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


prepare = module("prepare_sparkle", "prepare-sparkle.py")
feed = module("validate_update_feed", "validate-update-feed.py")
generator = module("generate_update_feed", "generate-update-feed.py")


class ArchiveResponse(io.BytesIO):
    def __init__(self, content: bytes, content_length: str | None = None):
        super().__init__(content)
        self.headers = {} if content_length is None else {"Content-Length": content_length}


class UpdateBoundaryTests(unittest.TestCase):
    def test_diagnostic_feed_requires_key_file_before_external_tools(self):
        arguments = ["generate-update-feed.py", "/nonexistent-archive.zip", "--release-tag", "test",
                     "--sparkle-tools", "/nonexistent-tools", "--diagnostic"]
        error = io.StringIO()
        with patch.object(sys, "argv", arguments), patch.object(sys, "stderr", error), \
                patch.object(generator.subprocess, "run") as external:
            self.assertEqual(generator.main(), 65)
            external.assert_not_called()
        self.assertIn("requires --private-key-file", error.getvalue())
        self.assertIn("Keychain fallback is disabled", error.getvalue())

    def test_only_current_swiftpm_framework_rpath_is_removed(self):
        scratch = ROOT / ".build/rpath-test"
        local = str(scratch / "out/Products/Release/PackageFrameworks")

        def commands(paths):
            return "\n".join(f"Load command {i}\n          cmd LC_RPATH\n      cmdsize 96\n         path {path} (offset 12)" for i, path in enumerate(paths))

        paths = ["@loader_path", local, "@executable_path/../Frameworks", "/usr/lib", "/System/Library/Frameworks"]
        self.assertEqual(prepare.swiftpm_framework_rpaths(commands(paths), scratch), [local])
        for unexpected in (str(ROOT / ".build/another-build/PackageFrameworks"),
                           str(scratch / "out/UnexpectedFrameworks")):
            with self.assertRaises(ValueError):
                prepare.swiftpm_framework_rpaths(commands([unexpected]), scratch)
        with self.assertRaisesRegex(ValueError, "Cannot parse"):
            prepare.swiftpm_framework_rpaths("Load command 0\n cmd LC_RPATH\n path undecodable", scratch)

    def test_adhoc_distribution_requires_explicit_optin(self):
        with self.assertRaisesRegex(ValueError, "SCHOLIUM_ALLOW_ADHOC_DISTRIBUTION"):
            prepare.signing_entitlements("release", "-", "com.scholium.app", False)
        opted_in = prepare.signing_entitlements("release", "-", "com.scholium.app", True)
        self.assertIs(opted_in[prepare.LIBRARY_VALIDATION], True)
        self.assertIs(opted_in["com.apple.security.app-sandbox"], True)

    def test_apple_signed_app_preserves_library_validation(self):
        entitlements = prepare.signing_entitlements("release", "Developer ID Application", "com.scholium.app", False)
        self.assertNotIn(prepare.LIBRARY_VALIDATION, entitlements)

    def test_sandbox_installer_lookup_is_bound_to_app_identity(self):
        entitlements = prepare.signing_entitlements("diagnostic", "-", "com.scholium.update-test", False)
        self.assertEqual(entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"], [
            "com.scholium.update-test-spks", "com.scholium.update-test-spki",
        ])

    def test_rejects_malformed_update_identity(self):
        self.assertEqual(prepare.public_key(base64.b64encode(bytes(32)).decode()), base64.b64encode(bytes(32)).decode())
        for key in ("", "invalid", base64.b64encode(bytes(64)).decode()):
            with self.assertRaises(ValueError):
                prepare.public_key(key)

    def test_feed_rejects_untrusted_asset_unsigned_archive_and_duplicate_build(self):
        namespace = feed.SPARKLE
        root = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(root, "channel")
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, f"{{{namespace}}}version").text = "23"
        ET.SubElement(item, f"{{{namespace}}}minimumSystemVersion").text = "26.0"
        enclosure = ET.SubElement(item, "enclosure", {
            "url": feed.DOWNLOAD_PREFIX + "v0.4.3/Scholium-v0.4.3-macos-arm64.dmg",
            "length": "123",
            f"{{{namespace}}}edSignature": base64.b64encode(bytes(64)).decode(),
        })
        with tempfile.TemporaryDirectory(dir=ROOT / ".build", prefix="update-test-") as temporary:
            path = Path(temporary) / "appcast.xml"

            def check():
                ET.ElementTree(root).write(path)
                return feed.validate(path)

            self.assertEqual(len(check()), 1)
            for url in ("http://github.com/Aaronlves/Scholium/releases/download/v1/app.dmg",
                        "https://github.com.attacker.example/Aaronlves/Scholium/releases/download/v1/app.dmg",
                        feed.DOWNLOAD_PREFIX + "v1/../app.dmg",
                        feed.DOWNLOAD_PREFIX + "v1/app.dmg?redirect=https://attacker.example"):
                enclosure.set("url", url)
                with self.assertRaises(ValueError):
                    check()
            enclosure.set("url", feed.DOWNLOAD_PREFIX + "v1/app.dmg")
            enclosure.set(f"{{{namespace}}}edSignature", "")
            with self.assertRaises(ValueError):
                check()
            enclosure.set(f"{{{namespace}}}edSignature", base64.b64encode(bytes(64)).decode())
            channel.append(ET.fromstring(ET.tostring(item)))
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                check()

    def test_download_bounds_reject_long_short_and_false_content_length(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".build", prefix="download-test-") as temporary:
            destination = Path(temporary) / "archive"
            for body, header in ((b"1234", None), (b"12", None), (b"123", "4")):
                with self.assertRaises(ValueError):
                    feed.download_archive("https://example.invalid/unused", destination, 3,
                                          lambda *args, **kwargs: ArchiveResponse(body, header))
            feed.download_archive("https://example.invalid/unused", destination, 3,
                                  lambda *args, **kwargs: ArchiveResponse(b"123", "3"))
            self.assertEqual(destination.read_bytes(), b"123")

    def test_download_verification_uses_public_key_and_rejects_tampering(self):
        candidates = [shutil.which("openssl"), "/opt/homebrew/opt/openssl@3/bin/openssl",
                      "/usr/local/opt/openssl@3/bin/openssl"]
        openssl = None
        for candidate in candidates:
            if candidate and Path(candidate).is_file():
                result = subprocess.run([candidate, "version"], capture_output=True, text=True)
                if result.returncode == 0 and result.stdout.startswith("OpenSSL 3."):
                    openssl = candidate
                    break
        if not openssl:
            self.skipTest("OpenSSL 3 is needed for the deployment's Ed25519 verifier")
        # RFC 8032 section 7.1 test vector 2: public values only, no private key.
        public = bytes.fromhex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
        signature = bytes.fromhex(
            "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da"
            "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")
        item = ET.Element("item")
        ET.SubElement(item, "enclosure", {
            "url": feed.DOWNLOAD_PREFIX + "test/fixture.zip", "length": "1",
            f"{{{feed.SPARKLE}}}edSignature": base64.b64encode(signature).decode(),
        })
        with tempfile.TemporaryDirectory(dir=ROOT / ".build", prefix="signature-test-") as temporary:
            public_key = Path(temporary) / "public-key.txt"
            public_key.write_text(base64.b64encode(public).decode())
            feed.verify_downloads([item], public_key, openssl,
                                  lambda *args, **kwargs: ArchiveResponse(b"r"))
            with self.assertRaisesRegex(ValueError, "Ed25519"):
                feed.verify_downloads([item], public_key, openssl,
                                      lambda *args, **kwargs: ArchiveResponse(b"x"))
            public_key.write_text(base64.b64encode(bytes(32)).decode())
            with self.assertRaisesRegex(ValueError, "Ed25519"):
                feed.verify_downloads([item], public_key, openssl,
                                      lambda *args, **kwargs: ArchiveResponse(b"r"))
        # An initial empty feed does not need a production key or a download.
        feed.verify_downloads([], Path("/nonexistent-key"), openssl)


if __name__ == "__main__":
    (ROOT / ".build").mkdir(exist_ok=True)
    unittest.main()
