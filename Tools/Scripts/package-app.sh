#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
# Release artifacts never belong in the source checkout. Override this for a
# release job with SCHOLIUM_PACKAGE_OUTPUT, but keep the default external.
OUTPUT="${SCHOLIUM_PACKAGE_OUTPUT:-${HOME}/Applications/Scholium Builds}"
APP="${OUTPUT}/Scholium.app"
SCRATCH="${ROOT}/.build/release"
STAGING_APP="${SCRATCH}/Scholium.app"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
DEPLOYMENT_TARGET="26.0"
SDK_VERSION="${SCHOLIUM_SDK_VERSION:-$(xcrun --sdk macosx --show-sdk-version)}"
RELEASE_LABEL="${SCHOLIUM_RELEASE_LABEL:-0.1.0-beta.1}"
LICENSE_SOURCE="${ROOT}/Tools/Packaging/Licenses"
[[ -s "${LICENSE_SOURCE}/Mermaid-and-transitive-NOTICES.txt" ]] || {
  print -u2 "Missing bundled Mermaid runtime notices. Run Tools/Scripts/build-editor.sh."
  exit 66
}
GIT_COMMIT="$(git -C "${ROOT}" rev-parse HEAD)"
GIT_EXACT_TAG="$(git -C "${ROOT}" describe --tags --exact-match 2>/dev/null || true)"
if [[ -z "$(git -C "${ROOT}" status --porcelain)" ]]; then
  SOURCE_CLEAN=true
else
  SOURCE_CLEAN=false
fi

[[ "${RELEASE_LABEL}" =~ '^[A-Za-z0-9][A-Za-z0-9._-]*$' ]] || {
  print -u2 "Invalid SCHOLIUM_RELEASE_LABEL: ${RELEASE_LABEL}"
  exit 64
}
[[ -d "${LICENSE_SOURCE}" ]] || {
  print -u2 "Missing packaged third-party licenses: ${LICENSE_SOURCE}"
  exit 66
}
if [[ "${SCHOLIUM_REQUIRE_CLEAN:-0}" == "1" ]] && [[ "${SOURCE_CLEAN}" != true ]]; then
  print -u2 "Refusing to package a release from a dirty worktree."
  exit 65
fi

rm -rf \
  "${APP}" \
  "${OUTPUT}/scholium" \
  "${OUTPUT}/Scholium_ScholiumCore.bundle" \
  "${SCRATCH}"
mkdir -p "${STAGING_APP}/Contents/MacOS" "${STAGING_APP}/Contents/Helpers" "${STAGING_APP}/Contents/Resources" "${OUTPUT}"

swift build --package-path "${ROOT}" -c release --scratch-path "${SCRATCH}"
cp "${SCRATCH}/release/ScholiumApp" "${STAGING_APP}/Contents/MacOS/Scholium"
cp "${SCRATCH}/release/scholium" "${STAGING_APP}/Contents/Helpers/scholium"
chmod +x "${STAGING_APP}/Contents/Helpers/scholium"
if [[ -d "${SCRATCH}/release/Scholium_ScholiumApp.bundle" ]]; then
  cp -R "${SCRATCH}/release/Scholium_ScholiumApp.bundle" "${STAGING_APP}/Contents/Resources/Scholium_ScholiumApp.bundle"
  find "${SCRATCH}/release/Scholium_ScholiumApp.bundle" -type d -name '*.lproj' | while IFS= read -r localization; do
    cp -R "${localization}" "${STAGING_APP}/Contents/Resources/"
  done
fi
CORE_RESOURCE_BUNDLE="${SCRATCH}/release/Scholium_ScholiumCore.bundle"
[[ -d "${CORE_RESOURCE_BUNDLE}" ]] || {
  print -u2 "Missing packaged ScholiumCore resource bundle."
  exit 66
}
cp -R \
  "${CORE_RESOURCE_BUNDLE}" \
  "${STAGING_APP}/Contents/Resources/Scholium_ScholiumCore.bundle"
EDITOR_RESOURCES="${STAGING_APP}/Contents/Resources/Scholium_ScholiumApp.bundle/Contents/Resources"
if [[ ! -d "${EDITOR_RESOURCES}" ]]; then
  EDITOR_RESOURCES="${STAGING_APP}/Contents/Resources/Scholium_ScholiumApp.bundle"
fi
for editor_resource in index.html editor.bundle.js editor.css callouts.css tables.css footnotes.css previews.css math.bundle.js katex.min.css mermaid.bundle.js mermaid.css; do
  [[ -s "${EDITOR_RESOURCES}/${editor_resource}" ]] || {
    print -u2 "Missing packaged editor resource: ${editor_resource}"
    exit 66
  }
done
if [[ "$(find "${EDITOR_RESOURCES}" -maxdepth 1 -type f -name 'KaTeX_*.woff2' | wc -l | tr -d ' ')" -ne 20 ]]; then
  print -u2 "The packaged KaTeX font set is incomplete."
  exit 66
fi
cp "${SCRATCH}/release/scholium" "${OUTPUT}/scholium"
chmod +x "${OUTPUT}/scholium"
cp -R "${CORE_RESOURCE_BUNDLE}" "${OUTPUT}/Scholium_ScholiumCore.bundle"
for core_catalog in \
  "${STAGING_APP}/Contents/Resources/Scholium_ScholiumCore.bundle/Contents/Resources/Skills/catalog.yaml" \
  "${OUTPUT}/Scholium_ScholiumCore.bundle/Contents/Resources/Skills/catalog.yaml"; do
  [[ -s "${core_catalog}" ]] || {
    print -u2 "Missing packaged protected Skill catalog: ${core_catalog}"
    exit 66
  }
done
cp "${ROOT}/Tools/Packaging/Info.plist" "${STAGING_APP}/Contents/Info.plist"
cp "${ROOT}/Tools/Packaging/ScholiumIcon.icns" "${STAGING_APP}/Contents/Resources/ScholiumIcon.icns"
mkdir -p "${STAGING_APP}/Contents/Resources/Licenses"
cp "${ROOT}/LICENSE" "${STAGING_APP}/Contents/Resources/Licenses/GPL-3.0-or-later.txt"
cp "${ROOT}/THIRD_PARTY_NOTICES.md" "${STAGING_APP}/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
cp -R "${LICENSE_SOURCE}/." "${STAGING_APP}/Contents/Resources/Licenses/"
PROVENANCE="${STAGING_APP}/Contents/Resources/ScholiumBuildProvenance.plist"
plutil -create xml1 "${PROVENANCE}"
plutil -insert schema -string scholium-build-provenance-v1 "${PROVENANCE}"
plutil -insert git_commit -string "${GIT_COMMIT}" "${PROVENANCE}"
plutil -insert git_exact_tag -string "${GIT_EXACT_TAG}" "${PROVENANCE}"
plutil -insert source_clean -bool "${SOURCE_CLEAN}" "${PROVENANCE}"
plutil -insert release_label -string "${RELEASE_LABEL}" "${PROVENANCE}"
plutil -insert sdk_version -string "${SDK_VERSION}" "${PROVENANCE}"

[[ "$(plutil -extract CFBundleShortVersionString raw "${STAGING_APP}/Contents/Info.plist")" == "0.1.0" ]]
[[ "$(plutil -extract CFBundleVersion raw "${STAGING_APP}/Contents/Info.plist")" == "1" ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw "${STAGING_APP}/Contents/Info.plist")" == "26.0" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' \
  "${ROOT}/Tools/Packaging/Scholium.entitlements")" == "true" ]]

# The beta SwiftPM linker may record the deployment target as both minOS and SDK
# in LC_BUILD_VERSION. Preserve the product's macOS 26 minimum while recording
# the SDK that actually compiled the app.
xcrun vtool \
  -set-build-version macos "${DEPLOYMENT_TARGET}" "${SDK_VERSION}" \
  -replace \
  -output "${STAGING_APP}/Contents/MacOS/Scholium.sdk-fixed" \
  "${STAGING_APP}/Contents/MacOS/Scholium"
mv "${STAGING_APP}/Contents/MacOS/Scholium.sdk-fixed" "${STAGING_APP}/Contents/MacOS/Scholium"

# SwiftPM release binaries retain source and object paths in symbol metadata.
# Strip that non-runtime metadata before signing so a distributed package does
# not disclose the builder's home-directory path.
xcrun strip -S -x "${STAGING_APP}/Contents/MacOS/Scholium"
xcrun strip -S -x "${STAGING_APP}/Contents/Helpers/scholium"
xcrun strip -S -x "${OUTPUT}/scholium"
xcrun vtool -show-build "${STAGING_APP}/Contents/MacOS/Scholium" | rg -q "sdk ${SDK_VERSION}"
if LC_ALL=C grep -aEq '/Users/[^/]+/' \
  "${STAGING_APP}/Contents/MacOS/Scholium" \
  "${STAGING_APP}/Contents/Helpers/scholium" \
  "${OUTPUT}/scholium"; then
  print -u2 "Refusing to package binaries containing a user home-directory path."
  exit 65
fi
xattr -cr "${STAGING_APP}"
xattr -cr "${OUTPUT}/Scholium_ScholiumCore.bundle"

# Sign nested code from the inside out. The bundled CLI is intentionally a
# standalone command-line executable and must not inherit the app sandbox
# entitlements: it has no application bundle identifier and is launched from
# the shell. The outer Scholium app alone receives the application
# entitlements. Keep --deep for verification, not for applying entitlements to
# nested code.
codesign --force --options runtime \
  --sign "${IDENTITY}" "${STAGING_APP}/Contents/Helpers/scholium"
codesign --verify --strict --verbose=2 \
  "${STAGING_APP}/Contents/Helpers/scholium"
BUNDLED_CLI_ENTITLEMENTS="${SCRATCH}/bundled-cli-entitlements.plist"
codesign -d --entitlements :- \
  "${STAGING_APP}/Contents/Helpers/scholium" \
  > "${BUNDLED_CLI_ENTITLEMENTS}" 2>/dev/null || true
if rg -q 'com\.apple\.security\.app-sandbox' "${BUNDLED_CLI_ENTITLEMENTS}"; then
  print -u2 "Refusing to package the bundled CLI with application sandbox entitlements."
  exit 65
fi
codesign --force --options runtime \
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
PACKAGED_CATALOG_SMOKE="${SCRATCH}/packaged-skill-catalog.json"
SCHOLIUM_HOME="${SCRATCH}/cli-smoke-home" \
  "${OUTPUT}/scholium" skills catalog --format json > "${PACKAGED_CATALOG_SMOKE}"
[[ -s "${PACKAGED_CATALOG_SMOKE}" ]] || {
  print -u2 "Packaged CLI could not load the protected Skill catalog."
  exit 66
}
SCHOLIUM_HOME="${SCRATCH}/bundled-cli-smoke-home" \
  "${APP}/Contents/Helpers/scholium" skills catalog --format json >/dev/null

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
