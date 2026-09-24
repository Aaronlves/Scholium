#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
DMG=""

usage() {
  print -u2 "Usage: verify-packaged-first-launch.sh --dmg DMG"
}

while (( $# > 0 )); do
  case "$1" in
    --dmg) DMG="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "Unknown argument: $1"; usage; exit 64 ;;
  esac
done

[[ -n "${DMG}" ]] || { usage; exit 64; }
DMG="${DMG:P}"
[[ -f "${DMG}" ]] || { print -u2 "Missing packaged DMG: ${DMG}"; exit 66; }
CHECKSUM="${DMG}.sha256"
[[ -f "${CHECKSUM}" ]] || { print -u2 "Missing packaged checksum: ${CHECKSUM}"; exit 66; }
(
  cd "${DMG:h}"
  shasum -a 256 -c "${CHECKSUM:t}" >/dev/null
)
hdiutil verify "${DMG}" >/dev/null

if pgrep -f '/Contents/MacOS/Scholium( |$)' >/dev/null 2>&1; then
  print -u2 "Refusing to run while another Scholium process is active."
  exit 65
fi

export DEVELOPER_DIR
"${ROOT}/Tools/Scripts/require-unlocked-ui-host.sh"
mkdir -p "${ROOT}/.build"
SCRATCH="$(mktemp -d "${ROOT}/.build/packaged-core-smoke.XXXXXX")"
MOUNT="${SCRATCH}/mounted-dmg"
COPIED_APP="${SCRATCH}/copied/Scholium.app"
PRODUCTION_STATE="${HOME}/Library/Application Support/Scholium/State-v1"
DMG_ATTACHED=false

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
  local app pid
  for app in "${MOUNT}/Scholium.app" "${COPIED_APP}"; do
    for pid in $(pgrep -f "^${app}/Contents/MacOS/Scholium( |$)" 2>/dev/null || true); do
      kill "${pid}" 2>/dev/null || true
    done
  done
  if [[ "${DMG_ATTACHED}" == true ]]; then
    if diskutil eject "${MOUNT}" >/dev/null 2>&1; then
      DMG_ATTACHED=false
    else
      print -u2 "Could not eject the packaged DMG at ${MOUNT}."
      exit_code=1
    fi
  fi
  if [[ "$(state_signature "${PRODUCTION_STATE}")" != "${BEFORE_SIGNATURE}" ]]; then
    print -u2 "The packaged Core smoke mutated production machine state."
    exit_code=1
  fi
  if (( exit_code == 0 )); then
    rm -rf "${SCRATCH}"
  else
    print -u2 "Packaged Core smoke diagnostics retained at ${SCRATCH}"
  fi
  trap - EXIT
  exit "${exit_code}"
}
trap cleanup EXIT
BEFORE_SIGNATURE="$(state_signature "${PRODUCTION_STATE}")"

mkdir -p "${MOUNT}" "${SCRATCH}/copied"
diskutil image attach \
  --readOnly \
  --nobrowse \
  --mountPoint "${MOUNT}" \
  "${DMG}" >/dev/null
DMG_ATTACHED=true
MOUNT_ITEMS=("${MOUNT}"/*(N))
if [[ "${#MOUNT_ITEMS[@]}" -ne 2 \
  || ! -d "${MOUNT}/Scholium.app" \
  || ! -L "${MOUNT}/Applications" \
  || "$(readlink "${MOUNT}/Applications")" != "/Applications" ]]; then
  print -u2 "The mounted DMG must expose only Scholium.app and an Applications alias."
  exit 65
fi
MOUNTED_APP="${MOUNT}/Scholium.app"
ditto --norsrc --noextattr --noqtn --noacl "${MOUNTED_APP}" "${COPIED_APP}"
for app in "${MOUNTED_APP}" "${COPIED_APP}"; do
  [[ -x "${app}/Contents/MacOS/Scholium" ]] || {
    print -u2 "Invalid packaged App: ${app}"
    exit 66
  }
  codesign --verify --deep --strict "${app}"
  bundle_id="$(plutil -extract CFBundleIdentifier raw "${app}/Contents/Info.plist")"
  [[ "${bundle_id}" == com.scholium.app ]] || {
    print -u2 "The packaged Core smoke requires com.scholium.app."
    exit 65
  }
done
cmp "${MOUNTED_APP}/Contents/Resources/ScholiumBuildProvenance.plist" \
  "${COPIED_APP}/Contents/Resources/ScholiumBuildProvenance.plist" >/dev/null

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

set_test_environment() {
  /usr/libexec/PlistBuddy \
    -c "Add :ScholiumUITests:EnvironmentVariables:$2 string $3" \
    "$1"
}

run_smoke() {
  local stage="$1"
  local app="$2"
  local fixture="${SCRATCH}/fixture-${stage}"
  local isolated_home="${SCRATCH}/home-${stage}"
  local run_id="packaged-core-${stage}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  local run_file="${DRIVER_PRODUCTS}/ScholiumPackagedCore-${stage}.xctestrun"
  ditto --norsrc --noextattr --noqtn --noacl "${ROOT}/TestVaults" "${fixture}"
  mkdir -p "${isolated_home}"
  cp "${BASE_XCTESTRUN}" "${run_file}"
  set_test_environment "${run_file}" SCHOLIUM_PACKAGED_CORE_SMOKE 1
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH "${app}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_FIXTURE_ROOT "${fixture}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_HOME_ROOT "${isolated_home}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_RUN_ID "${run_id}"

  "${DEVELOPER_DIR}/usr/bin/xcodebuild" \
    -xctestrun "${run_file}" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -parallel-testing-enabled NO \
    -maximum-parallel-testing-workers 1 \
    -resultBundlePath "${SCRATCH}/packaged-core-${stage}.xcresult" \
    test-without-building \
    -only-testing:ScholiumUITests/ScholiumPerformanceUITests/testPackagedCoreSmoke \
    >"${SCRATCH}/packaged-core-${stage}.log"
  for _ in {1..40}; do
    pgrep -f "^${app}/Contents/MacOS/Scholium( |$)" >/dev/null 2>&1 || break
    sleep 0.25
  done
  if pgrep -f "^${app}/Contents/MacOS/Scholium( |$)" >/dev/null 2>&1; then
    print -u2 "The ${stage} packaged App remained active after the smoke."
    return 1
  fi
  print "Packaged Core smoke (${stage}): Bootstrap, Triptych, exact save, relaunch/readback"
}

run_smoke mounted "${MOUNTED_APP}"
run_smoke copied "${COPIED_APP}"
print "Production machine state: unchanged"
