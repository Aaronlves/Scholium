#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
PACKAGE_MODE="${SCHOLIUM_PACKAGE_MODE:-release}"
case "${PACKAGE_MODE}" in
  release)
    # Release artifacts never belong in the source checkout. Override this for
    # a release job with SCHOLIUM_PACKAGE_OUTPUT, but keep the default external.
    OUTPUT="${SCHOLIUM_PACKAGE_OUTPUT:-${HOME}/Applications/Scholium Builds}"
    ;;
  diagnostic)
    [[ -n "${SCHOLIUM_PACKAGE_OUTPUT:-}" ]] || {
      print -u2 "A diagnostic package requires SCHOLIUM_PACKAGE_OUTPUT under .build/."
      exit 64
    }
    OUTPUT="${SCHOLIUM_PACKAGE_OUTPUT:A}"
    case "${OUTPUT}" in
      "${ROOT}/.build"/*) ;;
      *)
        print -u2 "Diagnostic packages must remain under ${ROOT}/.build/."
        exit 65
        ;;
    esac
    ;;
  *)
    print -u2 "SCHOLIUM_PACKAGE_MODE must be release or diagnostic."
    exit 64
    ;;
esac
APP="${OUTPUT}/Scholium.app"
SCRATCH="${ROOT}/.build/release"
STAGING_APP="${SCRATCH}/Scholium.app"
CLI_STAGE="${SCRATCH}/Scholium-CLI"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
DEPLOYMENT_TARGET="26.0"
SDK_VERSION="${SCHOLIUM_SDK_VERSION:-$(xcrun --sdk macosx --show-sdk-version)}"
LICENSE_SOURCE="${ROOT}/Tools/Packaging/Licenses"
[[ -s "${LICENSE_SOURCE}/Mermaid-and-transitive-NOTICES.txt" ]] || {
  print -u2 "Missing bundled Mermaid runtime notices. Run Tools/Scripts/build-editor.sh."
  exit 66
}
GIT_COMMIT="$(git -C "${ROOT}" rev-parse HEAD)"
GIT_EXACT_TAG="$(git -C "${ROOT}" describe --tags --exact-match 2>/dev/null || true)"
WORKTREE_PATCH_SHA256="$(
  {
    git -C "${ROOT}" diff --binary HEAD
    git -C "${ROOT}" ls-files --others --exclude-standard \
      | LC_ALL=C sort \
      | while IFS= read -r untracked_path; do
          print -r -- "untracked-path=${untracked_path}"
          stat -f 'untracked-mode=%p untracked-size=%z' \
            "${ROOT}/${untracked_path}"
          shasum -a 256 "${ROOT}/${untracked_path}" \
            | awk '{print "untracked-sha256=" $1}'
        done
  } | shasum -a 256 | awk '{print $1}'
)"
if [[ -z "$(git -C "${ROOT}" status --porcelain)" ]]; then
  SOURCE_CLEAN=true
else
  SOURCE_CLEAN=false
fi
if [[ "${PACKAGE_MODE}" == release ]]; then
  [[ "${SOURCE_CLEAN}" == true ]] || {
    print -u2 "Refusing to package a release from a dirty worktree."
    exit 65
  }
  [[ -n "${GIT_EXACT_TAG}" ]] || {
    print -u2 "Refusing to package a release without an exact Git tag."
    exit 65
  }
  RELEASE_LABEL="${SCHOLIUM_RELEASE_LABEL:-${GIT_EXACT_TAG}}"
  [[ "${RELEASE_LABEL}" == "${GIT_EXACT_TAG}" ]] || {
    print -u2 "The release label must exactly match the current Git tag."
    exit 65
  }
else
  RELEASE_LABEL="${SCHOLIUM_RELEASE_LABEL:-diagnostic-${GIT_COMMIT[1,12]}}"
fi

[[ "${RELEASE_LABEL}" =~ '^[A-Za-z0-9][A-Za-z0-9._-]*$' ]] || {
  print -u2 "Invalid SCHOLIUM_RELEASE_LABEL: ${RELEASE_LABEL}"
  exit 64
}
[[ -d "${LICENSE_SOURCE}" ]] || {
  print -u2 "Missing packaged third-party licenses: ${LICENSE_SOURCE}"
  exit 66
}
rm -rf \
  "${APP}" \
  "${OUTPUT}/Scholium-CLI-macos.zip" \
  "${OUTPUT}/Scholium-CLI-macos.zip.sha256" \
  "${SCRATCH}"
mkdir -p "${STAGING_APP}/Contents/MacOS" "${STAGING_APP}/Contents/Resources" \
  "${CLI_STAGE}" "${OUTPUT}"

swift build --package-path "${ROOT}" -c release --scratch-path "${SCRATCH}"
cp "${SCRATCH}/release/ScholiumApp" "${STAGING_APP}/Contents/MacOS/Scholium"
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
cp "${SCRATCH}/release/scholium" "${CLI_STAGE}/scholium"
chmod +x "${CLI_STAGE}/scholium"
cp -R "${CORE_RESOURCE_BUNDLE}" "${CLI_STAGE}/Scholium_ScholiumCore.bundle"
cp "${ROOT}/Tools/Packaging/install-scholium-cli.sh" "${CLI_STAGE}/install.sh"
chmod +x "${CLI_STAGE}/install.sh"
for core_resource in \
  "${STAGING_APP}/Contents/Resources/Scholium_ScholiumCore.bundle/Contents/Resources/Skills/README.md" \
  "${STAGING_APP}/Contents/Resources/Scholium_ScholiumCore.bundle/Contents/Resources/Skills/Scholium System Skills/scholium-core-protocol/SKILL.md" \
  "${STAGING_APP}/Contents/Resources/Scholium_ScholiumCore.bundle/Contents/Resources/Skills/Scholium Method Skills/scholium-analyze/SKILL.md" \
  "${CLI_STAGE}/Scholium_ScholiumCore.bundle/Contents/Resources/Skills/README.md" \
  "${CLI_STAGE}/Scholium_ScholiumCore.bundle/Contents/Resources/Skills/Scholium System Skills/scholium-core-protocol/SKILL.md" \
  "${CLI_STAGE}/Scholium_ScholiumCore.bundle/Contents/Resources/Skills/Scholium Method Skills/scholium-analyze/SKILL.md"; do
  [[ -s "${core_resource}" ]] || {
    print -u2 "Missing packaged current research-method resource: ${core_resource}"
    exit 66
  }
done
cp "${ROOT}/Tools/Packaging/Info.plist" "${STAGING_APP}/Contents/Info.plist"
MARKETING_VERSION="$(plutil -extract CFBundleShortVersionString raw "${STAGING_APP}/Contents/Info.plist")"
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "${STAGING_APP}/Contents/Info.plist")"
cp "${ROOT}/Tools/Packaging/ScholiumIcon.icns" "${STAGING_APP}/Contents/Resources/ScholiumIcon.icns"
mkdir -p "${STAGING_APP}/Contents/Resources/Licenses"
cp "${ROOT}/LICENSE" "${STAGING_APP}/Contents/Resources/Licenses/GPL-3.0-or-later.txt"
cp "${ROOT}/THIRD_PARTY_NOTICES.md" "${STAGING_APP}/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
cp -R "${LICENSE_SOURCE}/." "${STAGING_APP}/Contents/Resources/Licenses/"
mkdir -p "${CLI_STAGE}/Licenses"
cp "${ROOT}/LICENSE" "${CLI_STAGE}/Licenses/GPL-3.0-or-later.txt"
cp "${ROOT}/THIRD_PARTY_NOTICES.md" "${CLI_STAGE}/Licenses/THIRD_PARTY_NOTICES.md"
cp -R "${LICENSE_SOURCE}/." "${CLI_STAGE}/Licenses/"
PROVENANCE="${STAGING_APP}/Contents/Resources/ScholiumBuildProvenance.plist"
plutil -create xml1 "${PROVENANCE}"
plutil -insert schema -string scholium-build-provenance-v1 "${PROVENANCE}"
plutil -insert git_commit -string "${GIT_COMMIT}" "${PROVENANCE}"
plutil -insert git_exact_tag -string "${GIT_EXACT_TAG}" "${PROVENANCE}"
plutil -insert source_clean -bool "${SOURCE_CLEAN}" "${PROVENANCE}"
plutil -insert release_label -string "${RELEASE_LABEL}" "${PROVENANCE}"
plutil -insert marketing_version -string "${MARKETING_VERSION}" "${PROVENANCE}"
plutil -insert build_number -string "${BUILD_NUMBER}" "${PROVENANCE}"
plutil -insert package_mode -string "${PACKAGE_MODE}" "${PROVENANCE}"
plutil -insert worktree_patch_sha256 -string "${WORKTREE_PATCH_SHA256}" "${PROVENANCE}"
plutil -insert sdk_version -string "${SDK_VERSION}" "${PROVENANCE}"
cp "${PROVENANCE}" \
  "${STAGING_APP}/Contents/Resources/Scholium_ScholiumCore.bundle/Contents/Resources/ScholiumBuildProvenance.plist"
cp "${PROVENANCE}" \
  "${CLI_STAGE}/Scholium_ScholiumCore.bundle/Contents/Resources/ScholiumBuildProvenance.plist"

[[ "${MARKETING_VERSION}" == "0.1.0" ]]
[[ "${BUILD_NUMBER}" == "1" ]]
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

# SwiftPM release binaries retain source and object paths in symbol metadata.
# Strip that non-runtime metadata before signing so a distributed package does
# not disclose the builder's home-directory path.
xcrun strip -S -x "${STAGING_APP}/Contents/MacOS/Scholium"
xcrun strip -S -x "${CLI_STAGE}/scholium"
xcrun vtool -show-build "${STAGING_APP}/Contents/MacOS/Scholium" | rg -q "sdk ${SDK_VERSION}"
if LC_ALL=C grep -aEq '/Users/[^/]+/' \
  "${STAGING_APP}/Contents/MacOS/Scholium" \
  "${CLI_STAGE}/scholium"; then
  print -u2 "Refusing to package binaries containing a user home-directory path."
  exit 65
fi
xattr -cr "${STAGING_APP}"
xattr -cr "${CLI_STAGE}"

# The CLI is an independent executable, not nested App code. Sign it without
# App Sandbox entitlements, then sign the App with its bounded sandbox profile.
codesign --force --options runtime \
  --sign "${IDENTITY}" "${CLI_STAGE}/scholium"
codesign --verify --strict --verbose=2 \
  "${CLI_STAGE}/scholium"
CLI_ENTITLEMENTS="${SCRATCH}/cli-entitlements.plist"
codesign -d --entitlements :- \
  "${CLI_STAGE}/scholium" \
  > "${CLI_ENTITLEMENTS}" 2>/dev/null || true
if rg -q 'com\.apple\.security\.app-sandbox' "${CLI_ENTITLEMENTS}"; then
  print -u2 "Refusing to package the standalone CLI with App Sandbox entitlements."
  exit 65
fi
if rg -q 'com\.apple\.security\.application-groups' "${CLI_ENTITLEMENTS}"; then
  print -u2 "Refusing to package the standalone CLI with an App Group entitlement."
  exit 65
fi
codesign --force --options runtime \
  --entitlements "${ROOT}/Tools/Packaging/Scholium.entitlements" \
  --sign "${IDENTITY}" "${STAGING_APP}"
codesign --verify --deep --strict --verbose=2 "${STAGING_APP}"
APP_ENTITLEMENTS="${SCRATCH}/app-entitlements.plist"
codesign -d --entitlements :- "${STAGING_APP}" \
  > "${APP_ENTITLEMENTS}" 2>/dev/null || true
if ! rg -q 'com\.apple\.security\.app-sandbox' "${APP_ENTITLEMENTS}"; then
  print -u2 "Refusing to package Scholium without App Sandbox."
  exit 65
fi
if rg -q 'com\.apple\.security\.application-groups' "${APP_ENTITLEMENTS}"; then
  print -u2 "Refusing to package Scholium with an App Group entitlement."
  exit 65
fi
if rg -q '/\.local/' "${APP_ENTITLEMENTS}"; then
  print -u2 "Refusing to grant Scholium access to the CLI installation directory."
  exit 65
fi
if [[ -e "${STAGING_APP}/Contents/Helpers/scholium" ]]; then
  print -u2 "Refusing to embed the independently distributed CLI in Scholium.app."
  exit 65
fi

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
PACKAGED_CLI_SMOKE="${SCRATCH}/packaged-cli-version.json"
SCHOLIUM_HOME="${SCRATCH}/cli-smoke-home" \
  "${CLI_STAGE}/scholium" version --format json > "${PACKAGED_CLI_SMOKE}"
if ! jq -e \
  --arg marketing "${MARKETING_VERSION}" \
  --arg label "${RELEASE_LABEL}" \
  --arg build "${BUILD_NUMBER}" \
  '.schema_version == 1 and .product == "Scholium"
    and .cli_version == $marketing
    and .release_label == $label
    and .build_number == $build' \
  "${PACKAGED_CLI_SMOKE}" >/dev/null; then
  print -u2 "Packaged standalone CLI did not return the current version contract."
  exit 66
fi
ARCHITECTURES="$(lipo -archs "${APP}/Contents/MacOS/Scholium")"
if [[ "${ARCHITECTURES}" == "arm64 x86_64" || "${ARCHITECTURES}" == "x86_64 arm64" ]]; then
  ARCHITECTURE_LABEL="universal"
else
  ARCHITECTURE_LABEL="${ARCHITECTURES// /-}"
fi
ZIP_NAME="Scholium-${RELEASE_LABEL}-macos-${ARCHITECTURE_LABEL}.zip"
ZIP_PATH="${OUTPUT}/${ZIP_NAME}"
CHECKSUM_PATH="${ZIP_PATH}.sha256"
CLI_ZIP_NAME="Scholium-CLI-macos.zip"
CLI_ZIP_PATH="${OUTPUT}/${CLI_ZIP_NAME}"
CLI_CHECKSUM_PATH="${CLI_ZIP_PATH}.sha256"
rm -f "${ZIP_PATH}" "${CHECKSUM_PATH}" "${CLI_ZIP_PATH}" "${CLI_CHECKSUM_PATH}"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
  "${APP}" "${ZIP_PATH}"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
  "${CLI_STAGE}" "${CLI_ZIP_PATH}"
(
  cd "${OUTPUT}"
  shasum -a 256 "${ZIP_NAME}" > "${ZIP_NAME}.sha256"
  shasum -a 256 "${CLI_ZIP_NAME}" > "${CLI_ZIP_NAME}.sha256"
)

# Exercise the exact delivered CLI archive from an unrelated working directory.
CLI_ARCHIVE_SMOKE="${SCRATCH}/cli-archive-smoke"
CLI_INSTALL_PREFIX="${CLI_ARCHIVE_SMOKE}/installed"
mkdir -p "${CLI_ARCHIVE_SMOKE}/expanded"
ditto -x -k "${CLI_ZIP_PATH}" "${CLI_ARCHIVE_SMOKE}/expanded"
SCHOLIUM_HOME="${CLI_ARCHIVE_SMOKE}/home" \
SCHOLIUM_CLI_PREFIX="${CLI_INSTALL_PREFIX}" \
  "${CLI_ARCHIVE_SMOKE}/expanded/Scholium-CLI/install.sh" \
  > "${CLI_ARCHIVE_SMOKE}/install.log"
PACKAGED_CLI_PATH_SMOKE="${CLI_ARCHIVE_SMOKE}/path-version.json"
(
  cd /
  SCHOLIUM_HOME="${CLI_ARCHIVE_SMOKE}/path-home" \
    PATH="${CLI_INSTALL_PREFIX}/bin:/usr/bin:/bin" \
    scholium version --format json > "${PACKAGED_CLI_PATH_SMOKE}"
)
jq -e \
  --arg marketing "${MARKETING_VERSION}" \
  --arg label "${RELEASE_LABEL}" \
  --arg build "${BUILD_NUMBER}" \
  '.product == "Scholium"
    and .cli_version == $marketing
    and .release_label == $label
    and .build_number == $build' \
  "${PACKAGED_CLI_PATH_SMOKE}" >/dev/null

echo "Packaged: ${APP}"
echo "Package ZIP: ${ZIP_PATH}"
echo "Checksum: ${CHECKSUM_PATH}"
echo "CLI package: ${CLI_ZIP_PATH}"
echo "CLI checksum: ${CLI_CHECKSUM_PATH}"
if [[ "${IDENTITY}" == "-" ]]; then
  echo "Signing: ad hoc (not Developer ID signed or notarized)"
else
  echo "Signing identity: ${IDENTITY} (notarization not performed by this script)"
fi
