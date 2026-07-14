#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
XCODE="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED="/tmp/Scholium-Xcode-QA"
APP="/tmp/Scholium-QA.app"
FIXTURE_SOURCE="${SCHOLIUM_TEST_VAULTS:-${HOME}/Desktop/TestVaults}"
FIXTURE_COPY="/tmp/scholium-workbench-qa"

[[ -d "${FIXTURE_SOURCE}" ]] || { print -u2 "Missing fixture vault root: ${FIXTURE_SOURCE}"; exit 1; }

terminate_qa_instances() {
  pkill -f "${APP}/Contents/MacOS/Scholium" 2>/dev/null || true
  pkill -f "/private${APP}/Contents/MacOS/Scholium" 2>/dev/null || true
  pkill -f "${HOME}/Applications/Scholium-Codex-QA-Do-Not-Use.app/Contents/MacOS/Scholium" 2>/dev/null || true
}

# Rebuilding a running bundle can leave several stale QA processes alive.
# Terminate only known test-owned bundle paths before replacing the artifact.
terminate_qa_instances
rm -rf "${DERIVED}" "${APP}" "${FIXTURE_COPY}"
cp -R "${FIXTURE_SOURCE}" "${FIXTURE_COPY}"

DEVELOPER_DIR="${XCODE}" swift build \
  --package-path "${ROOT}" \
  --scratch-path "${DERIVED}" \
  --configuration debug \
  --product ScholiumApp

mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${DERIVED}/debug/ScholiumApp" "${APP}/Contents/MacOS/Scholium"
cp -R "${DERIVED}/debug/Scholium_ScholiumApp.bundle" "${APP}/Contents/Resources/"
cp "${ROOT}/Tools/Packaging/Info.plist" "${APP}/Contents/Info.plist"
cp "${ROOT}/Tools/Packaging/ScholiumIcon.icns" "${APP}/Contents/Resources/"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier com.kbmanager.qa" \
  -c "Set :CFBundleName Scholium QA" \
  "${APP}/Contents/Info.plist"
xattr -cr "${APP}"
codesign --force --deep --sign - "${APP}"
codesign --verify --deep --strict "${APP}"

print "QA app: ${APP}"
print "Disposable fixtures: ${FIXTURE_COPY}"
print "This is a SwiftPM Debug test bundle built with the selected Xcode toolchain, not a release package."
