#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
# Release artifacts never belong in the source checkout. Override this for a
# release job with SCHOLIUM_PACKAGE_OUTPUT, but keep the default external.
OUTPUT="${SCHOLIUM_PACKAGE_OUTPUT:-${HOME}/Applications/Scholium Builds}"
APP="${OUTPUT}/Scholium.app"
SCRATCH="${TMPDIR:-/tmp}/scholium-release"
STAGING_APP="${SCRATCH}/Scholium.app"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
DEPLOYMENT_TARGET="26.0"
SDK_VERSION="${SCHOLIUM_SDK_VERSION:-$(xcrun --sdk macosx --show-sdk-version)}"
RELEASE_LABEL="${SCHOLIUM_RELEASE_LABEL:-0.1.0-beta.1}"
LICENSE_SOURCE="${ROOT}/Tools/Packaging/Licenses"

[[ "${RELEASE_LABEL}" =~ '^[A-Za-z0-9][A-Za-z0-9._-]*$' ]] || {
  print -u2 "Invalid SCHOLIUM_RELEASE_LABEL: ${RELEASE_LABEL}"
  exit 64
}
[[ -d "${LICENSE_SOURCE}" ]] || {
  print -u2 "Missing packaged third-party licenses: ${LICENSE_SOURCE}"
  exit 66
}
if [[ "${SCHOLIUM_REQUIRE_CLEAN:-0}" == "1" ]] && [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  print -u2 "Refusing to package a release from a dirty worktree."
  exit 65
fi

rm -rf "${APP}" "${OUTPUT}/KB Manager.app" "${OUTPUT}/scholium" "${SCRATCH}"
mkdir -p "${STAGING_APP}/Contents/MacOS" "${STAGING_APP}/Contents/Resources" "${OUTPUT}"

swift build --package-path "${ROOT}" -c release --scratch-path "${SCRATCH}"
cp "${SCRATCH}/release/ScholiumApp" "${STAGING_APP}/Contents/MacOS/Scholium"
if [[ -d "${SCRATCH}/release/Scholium_ScholiumApp.bundle" ]]; then
  cp -R "${SCRATCH}/release/Scholium_ScholiumApp.bundle" "${STAGING_APP}/Contents/Resources/Scholium_ScholiumApp.bundle"
fi
cp "${SCRATCH}/release/scholium" "${OUTPUT}/scholium"
chmod +x "${OUTPUT}/scholium"
cp "${ROOT}/Tools/Packaging/Info.plist" "${STAGING_APP}/Contents/Info.plist"
cp "${ROOT}/Tools/Packaging/ScholiumIcon.icns" "${STAGING_APP}/Contents/Resources/ScholiumIcon.icns"
mkdir -p "${STAGING_APP}/Contents/Resources/Licenses"
cp "${ROOT}/LICENSE" "${STAGING_APP}/Contents/Resources/Licenses/GPL-3.0-or-later.txt"
cp "${ROOT}/THIRD_PARTY_NOTICES.md" "${STAGING_APP}/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
cp -R "${LICENSE_SOURCE}/." "${STAGING_APP}/Contents/Resources/Licenses/"

[[ "$(plutil -extract CFBundleShortVersionString raw "${STAGING_APP}/Contents/Info.plist")" == "0.1.0" ]]
[[ "$(plutil -extract CFBundleVersion raw "${STAGING_APP}/Contents/Info.plist")" == "1" ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw "${STAGING_APP}/Contents/Info.plist")" == "26.0" ]]

# The beta SwiftPM linker may record the deployment target as both minOS and SDK
# in LC_BUILD_VERSION. Preserve the product's macOS 26 minimum while recording
# the SDK that actually compiled the app.
xcrun vtool \
  -set-build-version macos "${DEPLOYMENT_TARGET}" "${SDK_VERSION}" \
  -replace \
  -output "${STAGING_APP}/Contents/MacOS/Scholium.sdk-fixed" \
  "${STAGING_APP}/Contents/MacOS/Scholium"
mv "${STAGING_APP}/Contents/MacOS/Scholium.sdk-fixed" "${STAGING_APP}/Contents/MacOS/Scholium"
xcrun vtool -show-build "${STAGING_APP}/Contents/MacOS/Scholium" | rg -q "sdk ${SDK_VERSION}"
xattr -cr "${STAGING_APP}"

codesign --force --deep --options runtime \
  --entitlements "${ROOT}/Tools/Packaging/Scholium.entitlements" \
  --sign "${IDENTITY}" "${STAGING_APP}"
codesign --verify --deep --strict --verbose=2 "${STAGING_APP}"

# Sign away from Desktop/File Provider, then copy the completed bundle into
# place. File Provider metadata is not part of the signature and is removed
# after the copy before strict verification of the delivered bundle.
cp -R "${STAGING_APP}" "${APP}"
# Desktop File Provider can attach Finder metadata to both the outer app and
# embedded SwiftPM resource bundles during the copy. Remove only those approved
# metadata keys from every bundle directory before validating the signature.
while IFS= read -r -d '' directory; do
  xattr -d 'com.apple.fileprovider.fpfs#P' "${directory}" 2>/dev/null || true
  xattr -d com.apple.FinderInfo "${directory}" 2>/dev/null || true
done < <(find "${APP}" -type d -print0)
codesign --verify --deep --strict --verbose=2 "${APP}"
codesign --force --options runtime --sign "${IDENTITY}" "${OUTPUT}/scholium"
codesign --verify --strict --verbose=2 "${OUTPUT}/scholium"

ARCHITECTURES="$(lipo -archs "${APP}/Contents/MacOS/Scholium")"
if [[ "${ARCHITECTURES}" == "arm64 x86_64" || "${ARCHITECTURES}" == "x86_64 arm64" ]]; then
  ARCHITECTURE_LABEL="universal"
else
  ARCHITECTURE_LABEL="${ARCHITECTURES// /-}"
fi
ZIP_NAME="Scholium-${RELEASE_LABEL}-macos-${ARCHITECTURE_LABEL}.zip"
ZIP_PATH="${OUTPUT}/${ZIP_NAME}"
CHECKSUM_PATH="${ZIP_PATH}.sha256"
rm -f "${ZIP_PATH}" "${CHECKSUM_PATH}"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
  "${APP}" "${ZIP_PATH}"
(
  cd "${OUTPUT}"
  shasum -a 256 "${ZIP_NAME}" > "${ZIP_NAME}.sha256"
)

echo "Packaged: ${APP}"
echo "CLI: ${OUTPUT}/scholium"
echo "Beta ZIP: ${ZIP_PATH}"
echo "Checksum: ${CHECKSUM_PATH}"
if [[ "${IDENTITY}" == "-" ]]; then
  echo "Signing: ad hoc (not Developer ID signed or notarized)"
else
  echo "Signing identity: ${IDENTITY} (notarization not performed by this script)"
fi
