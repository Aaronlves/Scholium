#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
APP=""

usage() {
  print -u2 "Usage: verify-packaged-first-launch.sh --app APP"
}

while (( $# > 0 )); do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "Unknown argument: $1"; usage; exit 64 ;;
  esac
done

[[ -n "${APP}" ]] || { usage; exit 64; }
APP="${APP:P}"
[[ -d "${APP}" && -x "${APP}/Contents/MacOS/Scholium" ]] || {
  print -u2 "Invalid Scholium app bundle: ${APP}"
  exit 66
}
codesign --verify --deep --strict "${APP}"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "${APP}/Contents/Info.plist")"
[[ "${BUNDLE_ID}" == com.scholium.app ]] || {
  print -u2 "The packaged first-launch proof requires com.scholium.app."
  exit 65
}
if pgrep -f '/Contents/MacOS/Scholium( |$)' >/dev/null 2>&1; then
  print -u2 "Refusing to run while another Scholium process is active."
  exit 65
fi

export DEVELOPER_DIR
"${ROOT}/Tools/Scripts/require-unlocked-ui-host.sh"
mkdir -p "${ROOT}/.build"
SCRATCH="$(mktemp -d "${ROOT}/.build/packaged-first-launch.XXXXXX")"
PRODUCTION_STATE="${HOME}/Library/Application Support/Scholium/State-v1"
RUN_ID="packaged-first-launch-$(date -u +%Y%m%dT%H%M%SZ)-$$"
ISOLATED_HOME="${HOME}/Library/Application Support/Scholium/Test Runs/${RUN_ID}"
mkdir -p "${ISOLATED_HOME}"

state_signature() {
  local state="$1"
  if [[ ! -e "${state}" ]]; then
    print "missing"
    return
  fi
  if [[ ! -d "${state}" ]]; then
    shasum -a 256 "${state}" | awk '{print "file:" $1}'
    return
  fi
  COPYFILE_DISABLE=1 /usr/bin/tar -cf - -C "${state:h}" "${state:t}" \
    | shasum -a 256 \
    | awk '{print "directory:" $1}'
}

cleanup() {
  local exit_code=$?
  local pid
  for pid in $(pgrep -f "^${APP}/Contents/MacOS/Scholium( |$)" 2>/dev/null || true); do
    kill "${pid}" 2>/dev/null || true
  done
  if [[ "$(state_signature "${PRODUCTION_STATE}")" != "${BEFORE_SIGNATURE}" ]]; then
    print -u2 "The packaged first-launch proof mutated production machine state."
    exit_code=1
  fi
  rm -rf "${ISOLATED_HOME}"
  if (( exit_code == 0 )); then
    rm -rf "${SCRATCH}"
  else
    print -u2 "First-launch diagnostics retained at ${SCRATCH}"
  fi
  trap - EXIT
  exit "${exit_code}"
}
trap cleanup EXIT

BEFORE_SIGNATURE="$(state_signature "${PRODUCTION_STATE}")"
DERIVED="${SCRATCH}/derived-data"
"${DEVELOPER_DIR}/usr/bin/xcodebuild" \
  -project "${ROOT}/ScholiumUITests.xcodeproj" \
  -scheme ScholiumUITests \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "${DERIVED}" \
  build-for-testing \
  >"${SCRATCH}/build-ui-driver.log"

DRIVER_PRODUCTS="${DERIVED}/Build/Products"
BASE_XCTESTRUN="$(find "${DRIVER_PRODUCTS}" -maxdepth 1 -name '*.xctestrun' -print -quit)"
[[ -f "${BASE_XCTESTRUN}" ]] || {
  print -u2 "Xcode did not produce an .xctestrun file."
  exit 70
}
RUN_FILE="${DRIVER_PRODUCTS}/ScholiumPackagedFirstLaunch.xctestrun"
cp "${BASE_XCTESTRUN}" "${RUN_FILE}"

set_test_environment() {
  /usr/libexec/PlistBuddy \
    -c "Add :ScholiumUITests:EnvironmentVariables:$2 string $3" \
    "$1"
}

set_test_environment "${RUN_FILE}" SCHOLIUM_PACKAGED_FIRST_LAUNCH_PROOF 1
set_test_environment "${RUN_FILE}" SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH "${APP}"
set_test_environment "${RUN_FILE}" SCHOLIUM_PERFORMANCE_DRIVER_HOME_ROOT "${ISOLATED_HOME}"
set_test_environment "${RUN_FILE}" SCHOLIUM_PERFORMANCE_DRIVER_RUN_ID "${RUN_ID}"

"${DEVELOPER_DIR}/usr/bin/xcodebuild" \
  -xctestrun "${RUN_FILE}" \
  -destination "platform=macOS,arch=$(uname -m)" \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -resultBundlePath "${SCRATCH}/packaged-first-launch.xcresult" \
  test-without-building \
  -only-testing:ScholiumUITests/ScholiumPerformanceUITests/testPackagedFirstLaunchUsesBootstrap \
  >"${SCRATCH}/packaged-first-launch.log"

for _ in {1..40}; do
  pgrep -f "^${APP}/Contents/MacOS/Scholium( |$)" >/dev/null 2>&1 || break
  sleep 0.25
done
print "Packaged first launch: Bootstrap"
print "Production machine state: unchanged"
