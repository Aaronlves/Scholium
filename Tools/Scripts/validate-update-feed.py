#!/usr/bin/env python3
"""Validate the static Scholium appcast before it is deployed."""

from __future__ import annotations

import argparse
import base64
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlsplit

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DOWNLOAD_PREFIX = "https://github.com/Aaronlves/Scholium/releases/download/"
ROOT = Path(__file__).resolve().parents[2]


def validate(path: Path, allow_empty: bool = False) -> list[ET.Element]:
    root = ET.parse(path).getroot()
    if root.tag != "rss" or root.get("version") != "2.0":
        raise ValueError("Expected an RSS 2.0 appcast")
    channels = root.findall("channel")
    if len(channels) != 1:
        raise ValueError("Appcast must contain exactly one channel")
    items = channels[0].findall("item")
    if not items and not allow_empty:
        raise ValueError("Appcast has no signed releases")
    versions: set[str] = set()
    for item in items:
        enclosure = item.find("enclosure")
        if enclosure is None:
            raise ValueError("Update item has no archive enclosure")
        version = item.findtext(f"{{{SPARKLE}}}version") or enclosure.get(f"{{{SPARKLE}}}version", "")
        if not re.fullmatch(r"[0-9]+", version) or int(version) <= 0:
            raise ValueError("Update requires a positive integer build number")
        if version in versions:
            raise ValueError(f"Duplicate update build: {version}")
        versions.add(version)
        url = enclosure.get("url", "")
        parts = urlsplit(url)
        if not url.startswith(DOWNLOAD_PREFIX) or parts.query or parts.fragment:
            raise ValueError("Update archives must use this repository's HTTPS GitHub Release assets")
        components = unquote(url[len(DOWNLOAD_PREFIX):]).split("/")
        if len(components) != 2 or any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", c) for c in components):
            raise ValueError("Release asset URL must contain a safe tag and filename")
        if not components[1].endswith((".dmg", ".zip")):
            raise ValueError("Only full DMG or ZIP application updates are published")
        signature = enclosure.get(f"{{{SPARKLE}}}edSignature", "")
        try:
            signature_bytes = base64.b64decode(signature, validate=True)
        except ValueError as error:
            raise ValueError("Invalid archive EdDSA signature encoding") from error
        if len(signature_bytes) != 64:
            raise ValueError("Every update archive requires a 64-byte EdDSA signature")
        length = enclosure.get("length", "")
        if not length.isdecimal() or int(length) <= 0:
            raise ValueError("Every update archive requires a positive byte length")
        minimum = item.findtext(f"{{{SPARKLE}}}minimumSystemVersion", "")
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", minimum):
            raise ValueError("Every update must declare its minimum macOS version")
    return items


class HTTPSRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        if urlsplit(newurl).scheme != "https":
            raise ValueError("Release asset redirects must remain on HTTPS")
        return super().redirect_request(request, response, code, message, headers, newurl)


def download_archive(url: str, destination: Path, expected_length: int,
                     opener=None) -> None:
    if opener is None:
        opener = urllib.request.build_opener(HTTPSRedirects()).open
    request = urllib.request.Request(url, headers={"User-Agent": "Scholium-Update-Verification", "Accept-Encoding": "identity"})
    with opener(request, timeout=30) as response, destination.open("wb") as output:
        declared = response.headers.get("Content-Length")
        if declared is not None and (not declared.isdecimal() or int(declared) != expected_length):
            raise ValueError("Downloaded archive Content-Length differs from the appcast")
        downloaded = 0
        while True:
            # Read one extra byte at the boundary so a dishonest or absent
            # Content-Length cannot make an oversized download look complete.
            chunk = response.read(min(65536, expected_length - downloaded + 1))
            if not chunk:
                break
            downloaded += len(chunk)
            if downloaded > expected_length:
                raise ValueError("Downloaded archive exceeds the appcast byte length")
            output.write(chunk)
        if downloaded != expected_length:
            raise ValueError("Downloaded archive is shorter than the appcast byte length")


def verify_downloads(items: list[ET.Element], public_key_file: Path,
                     openssl: str = "openssl", opener=None) -> None:
    if not items:
        return
    key_text = public_key_file.read_text().strip()
    try:
        key = base64.b64decode(key_text, validate=True)
    except ValueError as error:
        raise ValueError("Invalid committed update public key encoding") from error
    if len(key) != 32:
        raise ValueError("Committed update public key must decode to 32 bytes")
    work = ROOT / ".build/update-feed"
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="download-verification-", dir=work) as temporary:
        stage = Path(temporary)
        public_der = stage / "public.der"
        # RFC 8410 SubjectPublicKeyInfo for Ed25519 (OID 1.3.101.112),
        # followed by the raw 32-byte public key embedded in the App.
        public_der.write_bytes(bytes.fromhex("302a300506032b6570032100") + key)
        for index, item in enumerate(items):
            enclosure = item.find("enclosure")
            archive = stage / f"archive-{index}"
            download_archive(enclosure.get("url"), archive, int(enclosure.get("length")), opener)
            signature = stage / "signature"
            signature.write_bytes(base64.b64decode(enclosure.get(f"{{{SPARKLE}}}edSignature"), validate=True))
            # Sparkle signs the complete file with pure Ed25519, not Ed25519ph.
            result = subprocess.run([
                openssl, "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER",
                "-inkey", str(public_der), "-sigfile", str(signature), "-in", str(archive),
            ], capture_output=True, text=True, timeout=60)
            if result.returncode:
                raise ValueError("Downloaded archive failed Ed25519 verification with the committed public key (OpenSSL 3 is required)")
            archive.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("feed", type=Path)
    parser.add_argument("--allow-empty", action="store_true")
    parser.add_argument("--verify-downloads", action="store_true", help="Download Release assets and cryptographically verify them before deployment")
    parser.add_argument("--public-key-file", type=Path, default=ROOT / "Updates/public-key.txt")
    parser.add_argument("--openssl", default="openssl", help="OpenSSL 3 executable (Ubuntu CI provides it)")
    args = parser.parse_args()
    try:
        items = validate(args.feed, args.allow_empty)
        if args.verify_downloads:
            verify_downloads(items, args.public_key_file, args.openssl)
    except (OSError, ValueError, ET.ParseError, urllib.error.URLError, subprocess.SubprocessError) as error:
        print(f"Appcast validation failed: {error}", file=sys.stderr)
        return 65
    if args.verify_downloads:
        print(f"Appcast passed: {len(items)} Release archive(s) verified against committed public key and exact byte length")
    else:
        print(f"Appcast structure passed: {len(items)} signed release(s); archive signatures require cryptographic verification")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
