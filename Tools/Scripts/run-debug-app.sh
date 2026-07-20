#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
STAGING_ROOT="${ROOT}/.build/debug-app"
SCRATCH="${STAGING_ROOT}/swiftpm"
APP="${STAGING_ROOT}/Scholium-Debug.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# A raw `swift run` process does not have an application-bundle or
# LaunchServices lifecycle. Keep local GUI development on the same native
# launch path as a packaged app while retaining an incremental SwiftPM build.
pkill -f "${APP}/Contents/MacOS/Scholium" 2>/dev/null || true
"${LSREGISTER}" -u "${APP}" 2>/dev/null || true
rm -rf "${APP}"

DEVELOPER_DIR="${DEVELOPER_DIR}" swift build \
  --package-path "${ROOT}" \
  --scratch-path "${SCRATCH}" \
  --configuration debug \
  --product ScholiumApp
DEVELOPER_DIR="${DEVELOPER_DIR}" swift build \
  --package-path "${ROOT}" \
  --scratch-path "${SCRATCH}" \
  --configuration debug \
  --product scholium

mkdir -p \
  "${APP}/Contents/MacOS" \
  "${APP}/Contents/Helpers" \
  "${APP}/Contents/Resources"
cp "${SCRATCH}/debug/ScholiumApp" "${APP}/Contents/MacOS/Scholium"
cp "${SCRATCH}/debug/scholium" "${APP}/Contents/Helpers/scholium"
chmod +x "${APP}/Contents/MacOS/Scholium" "${APP}/Contents/Helpers/scholium"
cp -R \
  "${SCRATCH}/debug/Scholium_ScholiumApp.bundle" \
  "${APP}/Contents/Resources/"
cp -R \
  "${SCRATCH}/debug/Scholium_ScholiumCore.bundle" \
  "${APP}/Contents/Resources/"
find "${SCRATCH}/debug/Scholium_ScholiumApp.bundle" \
  -type d -name '*.lproj' | while IFS= read -r localization; do
    cp -R "${localization}" "${APP}/Contents/Resources/"
  done
cp "${ROOT}/Tools/Packaging/Info.plist" "${APP}/Contents/Info.plist"
cp "${ROOT}/Tools/Packaging/ScholiumIcon.icns" "${APP}/Contents/Resources/"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier com.scholium.debug" \
  -c "Set :CFBundleName Scholium Debug" \
  "${APP}/Contents/Info.plist"
xattr -cr "${APP}"
codesign --force --deep --sign - "${APP}"
codesign --verify --deep --strict "${APP}"
"${LSREGISTER}" -f -R -trusted "${APP}"
/usr/bin/open "${APP}"

print "Opened Debug app through LaunchServices: ${APP}"
