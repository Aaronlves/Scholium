#!/usr/bin/env python3
"""Generate and verify a signed appcast using the pinned Sparkle tools."""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--sparkle-tools", required=True, type=Path, help="Resolved Sparkle bin directory")
    parser.add_argument("--output", type=Path, default=ROOT / "Updates/appcast.xml")
    parser.add_argument("--private-key-file", type=Path, help="Optional exported private key; otherwise use Sparkle's Keychain account")
    parser.add_argument("--account", default="scholium", help="Sparkle Keychain account (default: scholium)")
    parser.add_argument("--diagnostic", action="store_true", help="Only write under .build/; for isolated test keys")
    args = parser.parse_args()
    try:
        if args.diagnostic and args.private_key_file is None:
            raise ValueError("Diagnostic feed generation requires --private-key-file; Keychain fallback is disabled")
        archive = args.archive.resolve(strict=True)
        output = args.output.resolve()
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", args.release_tag):
            raise ValueError("Invalid release tag")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.(?:dmg|zip)", archive.name):
            raise ValueError("Expected a DMG or ZIP with a URL-safe filename")
        if args.diagnostic and not output.is_relative_to(ROOT / ".build"):
            raise ValueError("Diagnostic feeds must remain under .build/")
        tools = args.sparkle_tools.resolve(strict=True)
        for name in ("generate_appcast", "sign_update"):
            if not os.access(tools / name, os.X_OK):
                raise ValueError(f"Missing executable Sparkle tool: {name}")
        spec = importlib.util.spec_from_file_location("feed_validator", ROOT / "Tools/Scripts/validate-update-feed.py")
        validator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(validator)
        key_options = ["--account", args.account]
        if args.private_key_file:
            key_options = ["--ed-key-file", str(args.private_key_file.resolve(strict=True))]
        work = ROOT / ".build/update-feed"
        work.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="generation-", dir=work) as temporary:
            stage = Path(temporary)
            archives = stage / "archives"
            archives.mkdir()
            staged_archive = archives / archive.name
            shutil.copyfile(archive, staged_archive)
            feed = stage / "appcast.xml"
            previous_versions: set[int] = set()
            if output.exists():
                for item in validator.validate(output, allow_empty=True):
                    enclosure = item.find("enclosure")
                    value = item.findtext(f"{{{validator.SPARKLE}}}version") or enclosure.get(f"{{{validator.SPARKLE}}}version")
                    previous_versions.add(int(value))
                shutil.copyfile(output, feed)
            prefix = f"{validator.DOWNLOAD_PREFIX}{args.release_tag}/"
            # Constrain Sparkle's archive extraction/cache to ignored build state.
            environment = {**os.environ, "CFFIXED_USER_HOME": str(stage / "home")}
            (stage / "home").mkdir()
            log = stage / "generate.log"
            with log.open("w") as stream:
                result = subprocess.run([
                    str(tools / "generate_appcast"), *key_options,
                    "--download-url-prefix", prefix, "--maximum-deltas", "0",
                    "--maximum-versions", "0", "-o", str(feed), str(archives),
                ], env=environment, stdout=stream, stderr=subprocess.STDOUT)
            # Keep the full diagnostics local; private keys are never arguments.
            retained_log = work / "latest-generation.log"
            shutil.copyfile(log, retained_log)
            if result.returncode:
                raise ValueError(f"Sparkle generate_appcast failed; inspect {retained_log}")
            items = validator.validate(feed)
            matching = [item for item in items if item.find("enclosure").get("url") == prefix + archive.name]
            if len(matching) != 1:
                raise ValueError("Generated appcast does not contain exactly one matching release asset")
            item = matching[0]
            enclosure = item.find("enclosure")
            version = item.findtext(f"{{{validator.SPARKLE}}}version") or enclosure.get(f"{{{validator.SPARKLE}}}version")
            if previous_versions and int(version) <= max(previous_versions):
                raise ValueError("New archive CFBundleVersion must exceed every published build; never replace a released asset")
            if int(enclosure.get("length")) != archive.stat().st_size:
                raise ValueError("Generated appcast length does not match the archive")
            signature = enclosure.get(f"{{{validator.SPARKLE}}}edSignature")
            subprocess.run([str(tools / "sign_update"), *key_options, "--verify", str(archive), signature],
                           check=True, env=environment)
            output.parent.mkdir(parents=True, exist_ok=True)
            # Only replace the deployable feed after generation and verification.
            replacement = output.with_name(f".{output.name}.new")
            shutil.copyfile(feed, replacement)
            replacement.replace(output)
        print(f"Signed and verified build {version}: {output}")
        print(f"Upload the exact archive to {prefix + archive.name}; then review, commit and manually deploy the feed")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Appcast generation failed: {error}", file=sys.stderr)
        return 65
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
