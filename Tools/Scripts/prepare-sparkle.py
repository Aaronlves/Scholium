#!/usr/bin/env python3
"""Embed and individually sign the resolved Sparkle distribution in an app."""

from __future__ import annotations

import argparse
import base64
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIBRARY_VALIDATION = "com.apple.security.cs.disable-library-validation"


def public_key(value: str) -> str:
    value = value.strip()
    try:
        decoded = base64.b64decode(value, validate=True)
    except ValueError as error:
        raise ValueError("Sparkle public key must be base64 encoded") from error
    if len(decoded) != 32:
        raise ValueError("Sparkle public key must decode to 32 bytes")
    return value


def distribution(scratch: Path) -> tuple[Path, Path]:
    artifact = scratch / "artifacts/sparkle/Sparkle"
    frameworks = list(artifact.glob("**/Sparkle.framework"))
    if len(frameworks) != 1:
        raise ValueError(f"Expected one resolved Sparkle.framework under {artifact}")
    framework = frameworks[0]
    licenses = list(artifact.glob("**/LICENSE"))
    if not licenses:
        # SwiftPM also checks out the pinned package's license.
        licenses = [scratch / "checkouts/Sparkle/LICENSE"]
    if not licenses[0].is_file():
        raise ValueError("Missing Sparkle third-party license")
    return framework, licenses[0]


def signing_entitlements(mode: str, identity: str, bundle_id: str,
                         allow_adhoc: bool) -> dict[str, object]:
    if mode == "qa":
        return {}
    with (ROOT / "Tools/Packaging/Scholium.entitlements").open("rb") as source:
        result = plistlib.load(source)
    result["com.apple.security.temporary-exception.mach-lookup.global-name"] = [
        f"{bundle_id}-spks", f"{bundle_id}-spki",
    ]
    if identity == "-":
        if mode == "release" and not allow_adhoc:
            raise ValueError(
                "Ad-hoc release signing cannot load Sparkle with Library Validation enabled. "
                "Provide CODE_SIGN_IDENTITY, or explicitly set SCHOLIUM_ALLOW_ADHOC_DISTRIBUTION=1 "
                "to disable Library Validation for this app only. That opt-in does not provide "
                "Apple Developer ID trust or notarization."
            )
        result[LIBRARY_VALIDATION] = True
    return result


def run(argv: list[str]) -> None:
    subprocess.run(argv, check=True)


def swiftpm_framework_rpaths(load_commands: str, scratch: Path) -> list[str]:
    """Select only this build's SwiftPM framework search paths for removal."""
    result: list[str] = []
    for command in re.split(r"(?m)^Load command [0-9]+\s*$", load_commands):
        if not re.search(r"(?m)^\s*cmd LC_RPATH\s*$", command):
            continue
        paths = re.findall(r"(?m)^\s*path (.+) \(offset [0-9]+\)\s*$", command)
        if len(paths) != 1:
            raise ValueError("Cannot parse Mach-O LC_RPATH; refusing to package an unknown runtime search path")
        path = paths[0]
        if not Path(path).is_absolute():
            continue
        resolved = Path(path).resolve()
        if resolved.name == "PackageFrameworks":
            if not resolved.is_relative_to(scratch.resolve()):
                raise ValueError("SwiftPM PackageFrameworks runtime path points outside this build's scratch directory")
            if path not in result:
                result.append(path)
        elif resolved.is_relative_to(ROOT):
            raise ValueError("Unexpected absolute runtime search path into the source checkout")
    return result


def remove_swiftpm_rpaths(executable: Path, scratch: Path) -> None:
    load_commands = subprocess.check_output(["xcrun", "otool", "-l", str(executable)], text=True)
    paths = swiftpm_framework_rpaths(load_commands, scratch)
    if paths:
        command = ["xcrun", "install_name_tool"]
        for path in paths:
            command.extend(["-delete_rpath", path])
        run([*command, str(executable)])
        remaining = subprocess.check_output(["xcrun", "otool", "-l", str(executable)], text=True)
        if swiftpm_framework_rpaths(remaining, scratch):
            raise ValueError("The packaged executable retains a SwiftPM framework runtime path")
        print("Removed build-local SwiftPM framework runtime search path")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--scratch-path", required=True, type=Path)
    parser.add_argument("--mode", required=True, choices=("release", "diagnostic", "qa"))
    parser.add_argument("--identity", default="-")
    parser.add_argument("--entitlements-output", required=True, type=Path)
    args = parser.parse_args()
    try:
        app = args.app.resolve()
        scratch = args.scratch_path.resolve()
        if args.mode != "release" and not app.is_relative_to(ROOT / ".build"):
            raise ValueError("Diagnostic and QA bundles must remain under .build/")
        if not args.entitlements_output.resolve().is_relative_to(ROOT / ".build"):
            raise ValueError("Generated entitlements must remain under .build/")
        info_path = app / "Contents/Info.plist"
        with info_path.open("rb") as source:
            info = plistlib.load(source)
        entitlements = signing_entitlements(
            args.mode, args.identity, info["CFBundleIdentifier"],
            os.environ.get("SCHOLIUM_ALLOW_ADHOC_DISTRIBUTION") == "1",
        )
        if args.mode == "release":
            key = os.environ.get("SCHOLIUM_SPARKLE_PUBLIC_KEY", "").strip()
            key_file = ROOT / "Updates/public-key.txt"
            if not key and key_file.is_file():
                key = key_file.read_text().strip()
            if not key:
                raise ValueError("Release packaging requires SCHOLIUM_SPARKLE_PUBLIC_KEY or Updates/public-key.txt")
        else:
            # Test bundles never inherit the production update identity.
            key = os.environ.get("SCHOLIUM_SPARKLE_TEST_PUBLIC_KEY", "").strip()
        if key:
            info["SUPublicEDKey"] = public_key(key)
        else:
            info.pop("SUPublicEDKey", None)
        if args.mode != "release":
            info["SUEnableAutomaticChecks"] = False
            info["SUAutomaticallyUpdate"] = False
            info["SCHOLIUMDiagnosticBuild"] = True
            test_feed = os.environ.get("SCHOLIUM_SPARKLE_TEST_FEED_URL", "").strip()
            if test_feed:
                info["SUFeedURL"] = test_feed
        # The existing QA bundle runs outside App Sandbox. It must not opt in
        # to the sandbox-only installer launcher service.
        if args.mode == "qa":
            info["SUEnableInstallerLauncherService"] = False
        remove_swiftpm_rpaths(app / "Contents/MacOS" / info["CFBundleExecutable"], scratch)
        source_framework, license_path = distribution(scratch)
        destination = app / "Contents/Frameworks/Sparkle.framework"
        if destination.exists():
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        run(["ditto", "--norsrc", "--noextattr", "--noqtn", "--noacl",
             str(source_framework), str(destination)])
        licenses = app / "Contents/Resources/Licenses"
        licenses.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(license_path, licenses / "Sparkle-LICENSE.txt")
        with info_path.open("wb") as output:
            plistlib.dump(info, output, sort_keys=False)
        args.entitlements_output.parent.mkdir(parents=True, exist_ok=True)
        with args.entitlements_output.open("wb") as output:
            plistlib.dump(entitlements, output, sort_keys=False)

        # Sparkle's custom-distribution signing order. Never sign with --deep:
        # that can apply the app's sandbox entitlements to installer services.
        version = destination / "Versions/Current"
        for relative in ("XPCServices/Installer.xpc", "XPCServices/Downloader.xpc",
                         "Autoupdate", "Updater.app", "."):
            component = version / relative if relative != "." else destination
            if not component.exists():
                raise ValueError(f"Missing Sparkle installer component: {component}")
            command = ["codesign", "--force", "--options", "runtime", "--sign", args.identity]
            if relative == "XPCServices/Downloader.xpc":
                command.append("--preserve-metadata=entitlements")
            run([*command, str(component)])
        run(["codesign", "--verify", "--deep", "--strict", str(destination)])
        print(f"Sparkle embedded and signed; update key {'configured' if key else 'absent (updates disabled)'}")
        if LIBRARY_VALIDATION in entitlements:
            print("Ad-hoc app: Library Validation disabled for this bundle only; Apple trust and notarization absent")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Sparkle preparation failed: {error}", file=sys.stderr)
        return 65
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
