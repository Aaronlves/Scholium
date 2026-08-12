#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
OUTPUT=""

usage() {
  print -u2 "Usage: prepare-performance-driver.sh --output DIR"
}

while (( $# > 0 )); do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
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
[[ -z "$(git -C "${ROOT}" status --porcelain)" ]] || {
  print -u2 "Driver preparation requires a clean worktree."
  exit 65
}
GIT_EXACT_TAG="$(git -C "${ROOT}" describe --tags --exact-match 2>/dev/null || true)"
[[ -n "${GIT_EXACT_TAG}" ]] || {
  print -u2 "Driver preparation requires an exact tagged commit."
  exit 65
}

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
plutil -insert git_commit -string "$(git -C "${ROOT}" rev-parse HEAD)" "${MANIFEST}"
plutil -insert git_exact_tag -string "${GIT_EXACT_TAG}" "${MANIFEST}"
plutil -insert source_clean -bool true "${MANIFEST}"
plutil -insert xcode_build -string "${XCODE_BUILD}" "${MANIFEST}"
plutil -insert architecture -string "$(uname -m)" "${MANIFEST}"

print "Prepared performance driver: ${OUTPUT}"
print "Commit: $(git -C "${ROOT}" rev-parse HEAD)"
print "Tag: ${GIT_EXACT_TAG}"
print "Xcode build: ${XCODE_BUILD}"
print "Cool the reference machine before invoking run-performance-benchmarks.sh --gate."
