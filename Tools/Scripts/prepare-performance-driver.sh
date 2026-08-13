#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
OUTPUT=""
EVIDENCE_CLASS=product_gate

usage() {
  print -u2 "Usage: prepare-performance-driver.sh --output DIR [--scenario]"
}

while (( $# > 0 )); do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --scenario) EVIDENCE_CLASS=scenario_only; shift ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "Unknown argument: $1"; usage; exit 64 ;;
  esac
done

[[ -n "${OUTPUT}" ]] || { usage; exit 64; }
OUTPUT="${OUTPUT:A}"
case "${OUTPUT}" in
  "${ROOT}/.build"/*) ;;
  *)
    print -u2 "Prepared performance drivers must remain under ${ROOT}/.build."
    exit 65
    ;;
esac
if [[ -e "${OUTPUT}" && -n "$(find "${OUTPUT}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  print -u2 "Refusing to overwrite a nonempty prepared-driver directory: ${OUTPUT}"
  exit 65
fi
WORKTREE_STATUS="$(git -C "${ROOT}" status --porcelain)"
if [[ "${EVIDENCE_CLASS}" == product_gate && -n "${WORKTREE_STATUS}" ]]; then
  print -u2 "Product-gate driver preparation requires a clean worktree."
  exit 65
fi
if [[ "${EVIDENCE_CLASS}" == scenario_only && -n "$(git -C "${ROOT}" ls-files --others --exclude-standard)" ]]; then
  print -u2 "Scenario driver preparation refuses untracked source inputs."
  exit 65
fi
GIT_EXACT_TAG="$(git -C "${ROOT}" describe --tags --exact-match 2>/dev/null || true)"
if [[ "${EVIDENCE_CLASS}" == product_gate && -z "${GIT_EXACT_TAG}" ]]; then
  print -u2 "Driver preparation requires an exact tagged commit."
  exit 65
fi
WORKTREE_PATCH_SHA256="$(git -C "${ROOT}" diff --binary HEAD | shasum -a 256 | awk '{print $1}')"

export DEVELOPER_DIR
DERIVED="${OUTPUT}/derived-data"
mkdir -p "${OUTPUT}"
"${DEVELOPER_DIR}/usr/bin/xcodebuild" \
  -project "${ROOT}/ScholiumUITests.xcodeproj" \
  -scheme ScholiumUITests \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "${DERIVED}" \
  build-for-testing \
  >"${OUTPUT}/build-ui-driver.log"

BASE_XCTESTRUN="$(find "${DERIVED}/Build/Products" -maxdepth 1 -name '*.xctestrun' -print -quit)"
RUNNER="$(find "${DERIVED}/Build/Products" -path '*/ScholiumUITests-Runner.app' -print -quit)"
[[ -f "${BASE_XCTESTRUN}" && -d "${RUNNER}" ]] || {
  print -u2 "Xcode did not produce the signed performance UI driver."
  exit 70
}
codesign --verify --deep --strict "${RUNNER}"

MANIFEST="${OUTPUT}/ScholiumPerformanceDriver.plist"
XCODE_BUILD="$("${DEVELOPER_DIR}/usr/bin/xcodebuild" -version | awk '/Build version/{print $3}')"
plutil -create xml1 "${MANIFEST}"
plutil -insert schema -string scholium-performance-driver-v1 "${MANIFEST}"
plutil -insert evidence_class -string "${EVIDENCE_CLASS}" "${MANIFEST}"
plutil -insert git_commit -string "$(git -C "${ROOT}" rev-parse HEAD)" "${MANIFEST}"
plutil -insert git_exact_tag -string "${GIT_EXACT_TAG}" "${MANIFEST}"
if [[ -z "${WORKTREE_STATUS}" ]]; then
  plutil -insert source_clean -bool true "${MANIFEST}"
else
  plutil -insert source_clean -bool false "${MANIFEST}"
fi
plutil -insert worktree_patch_sha256 -string "${WORKTREE_PATCH_SHA256}" "${MANIFEST}"
plutil -insert xcode_build -string "${XCODE_BUILD}" "${MANIFEST}"
plutil -insert architecture -string "$(uname -m)" "${MANIFEST}"

print "Prepared performance driver: ${OUTPUT}"
print "Evidence class: ${EVIDENCE_CLASS}"
print "Commit: $(git -C "${ROOT}" rev-parse HEAD)"
print "Tag: ${GIT_EXACT_TAG}"
print "Worktree patch SHA-256: ${WORKTREE_PATCH_SHA256}"
print "Xcode build: ${XCODE_BUILD}"
print "Cool the reference machine before invoking run-performance-benchmarks.sh."
