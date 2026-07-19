#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
MANIFEST_TOOL="${ROOT}/Tools/Scripts/qa-upgrade-manifest.py"
DEFAULT_ALLOWLIST="${ROOT}/Tools/Fixtures/qa-upgrade-portable-allowlist.txt"
BASELINE=""
CANDIDATE=""
FIXTURE_SOURCE="${SCHOLIUM_TEST_VAULTS:-${HOME}/Desktop/TestVaults}"
OUTPUT=""
ALLOWLIST="${DEFAULT_ALLOWLIST}"

usage() {
  print -u2 "Usage: verify-qa-upgrade-safety.sh --baseline APP --candidate APP --output DIR [--fixture ROOT] [--portable-allowlist FILE]"
}

while (( $# > 0 )); do
  case "$1" in
    --baseline) BASELINE="$2"; shift 2 ;;
    --candidate) CANDIDATE="$2"; shift 2 ;;
    --fixture) FIXTURE_SOURCE="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --portable-allowlist) ALLOWLIST="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "Unknown argument: $1"; usage; exit 64 ;;
  esac
done

[[ -n "${BASELINE}" && -n "${CANDIDATE}" && -n "${OUTPUT}" ]] || {
  usage
  exit 64
}

BASELINE="${BASELINE:P}"
CANDIDATE="${CANDIDATE:P}"
FIXTURE_SOURCE="${FIXTURE_SOURCE:P}"
OUTPUT="${OUTPUT:A}"
ALLOWLIST="${ALLOWLIST:P}"

for app in "${BASELINE}" "${CANDIDATE}"; do
  [[ -d "${app}" && -x "${app}/Contents/MacOS/Scholium" ]] || {
    print -u2 "Invalid Scholium app bundle: ${app}"
    exit 66
  }
  codesign --verify --deep --strict "${app}"
done
[[ -d "${FIXTURE_SOURCE}/01-analyses" && -d "${FIXTURE_SOURCE}/02-topics" && -d "${FIXTURE_SOURCE}/03-works" ]] || {
  print -u2 "Fixture root is not a Triptych: ${FIXTURE_SOURCE}"
  exit 66
}
[[ -f "${ALLOWLIST}" ]] || {
  print -u2 "Missing portable allowlist: ${ALLOWLIST}"
  exit 66
}
case "${OUTPUT}" in
  "${ROOT}"|"${ROOT}"/*|"${FIXTURE_SOURCE}"|"${FIXTURE_SOURCE}"/*)
    print -u2 "Upgrade evidence must be outside the repository and source fixture."
    exit 65
    ;;
esac
if [[ -e "${OUTPUT}" && -n "$(find "${OUTPUT}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  print -u2 "Refusing to overwrite a nonempty evidence directory: ${OUTPUT}"
  exit 65
fi
if pgrep -f '/Contents/MacOS/Scholium( |$)' >/dev/null 2>&1; then
  print -u2 "Refusing to run while another Scholium process is active."
  exit 65
fi

RUN_ID="upgrade_$(date -u +%Y%m%dT%H%M%SZ)_$$"
SCRATCH="${ROOT}/.build/${RUN_ID}"
TRIPTYCH="${SCRATCH}/Triptych"
HOME_ROOT="${SCRATCH}/home"
DERIVED="${SCRATCH}/derived-data"
MANIFESTS="${OUTPUT}/manifests"
RESULTS="${OUTPUT}/xcresults"

cleanup() {
  local exit_code=$?
  local pid
  for app in "${BASELINE}" "${CANDIDATE}"; do
    for pid in $(pgrep -f "^${app}/Contents/MacOS/Scholium( |$)" 2>/dev/null || true); do
      kill "${pid}" 2>/dev/null || true
    done
  done
  if (( exit_code == 0 )); then
    rm -rf "${SCRATCH}"
  else
    print -u2 "Incomplete test-owned scratch retained at ${SCRATCH}"
  fi
}
trap cleanup EXIT

mkdir -p "${OUTPUT}" "${MANIFESTS}" "${RESULTS}" "${HOME_ROOT}"
mkdir -p "${TRIPTYCH}"
for vault_root in 01-analyses 02-topics 03-works; do
  ditto --norsrc --noextattr --noqtn --noacl \
    "${FIXTURE_SOURCE}/${vault_root}" \
    "${TRIPTYCH}/${vault_root}"
done
if [[ -d "${FIXTURE_SOURCE}/.scholium" ]]; then
  ditto --norsrc --noextattr --noqtn --noacl \
    "${FIXTURE_SOURCE}/.scholium" \
    "${TRIPTYCH}/.scholium"
fi
# Upgrade verification consumes the same static fixture snapshot as UI tests.
# The fixture authoring generator is deliberately excluded from the test run.
python3 "${MANIFEST_TOOL}" seed --root "${TRIPTYCH}"
python3 "${MANIFEST_TOOL}" capture --root "${TRIPTYCH}" --output "${MANIFESTS}/before.json"
python3 "${MANIFEST_TOOL}" capture --root "${HOME_ROOT}" --output "${MANIFESTS}/home-before.json"

baseline_hash="$(shasum -a 256 "${BASELINE}/Contents/MacOS/Scholium" | awk '{print $1}')"
candidate_hash="$(shasum -a 256 "${CANDIDATE}/Contents/MacOS/Scholium" | awk '{print $1}')"
baseline_id="$(plutil -extract CFBundleIdentifier raw "${BASELINE}/Contents/Info.plist")"
candidate_id="$(plutil -extract CFBundleIdentifier raw "${CANDIDATE}/Contents/Info.plist")"
{
  print "run_id=${RUN_ID}"
  print "baseline_path=${BASELINE}"
  print "baseline_bundle_id=${baseline_id}"
  print "baseline_executable_sha256=${baseline_hash}"
  print "candidate_path=${CANDIDATE}"
  print "candidate_bundle_id=${candidate_id}"
  print "candidate_executable_sha256=${candidate_hash}"
  if [[ "${baseline_hash}" == "${candidate_hash}" ]]; then
    print "evidence_class=harness-proof-identical-builds"
  else
    print "evidence_class=differential-upgrade-check"
  fi
} > "${OUTPUT}/run.properties"
cp "${ALLOWLIST}" "${OUTPUT}/portable-allowlist.txt"

"${DEVELOPER_DIR}/usr/bin/xcodebuild" \
  -project "${ROOT}/ScholiumUITests.xcodeproj" \
  -scheme ScholiumUITests \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "${DERIVED}" \
  build-for-testing \
  > "${OUTPUT}/build-ui-driver.log"
BASE_XCTESTRUN="$(find "${DERIVED}/Build/Products" -maxdepth 1 -name '*.xctestrun' -print -quit)"
[[ -f "${BASE_XCTESTRUN}" ]] || {
  print -u2 "Xcode did not produce an .xctestrun file."
  exit 70
}

set_test_environment() {
  local plist="$1"
  local key="$2"
  local value="$3"
  /usr/libexec/PlistBuddy \
    -c "Add :ScholiumUITests:EnvironmentVariables:${key} string ${value}" \
    "${plist}"
}

run_app() {
  local label="$1"
  local app="$2"
  local run_file="${DERIVED}/Build/Products/ScholiumUpgrade-${label}.xctestrun"
  cp "${BASE_XCTESTRUN}" "${run_file}"
  set_test_environment "${run_file}" SCHOLIUM_UPGRADE_DRIVER_APP_PATH "${app}"
  set_test_environment "${run_file}" SCHOLIUM_UPGRADE_DRIVER_FIXTURE_ROOT "${TRIPTYCH}"
  set_test_environment "${run_file}" SCHOLIUM_UPGRADE_DRIVER_HOME_ROOT "${HOME_ROOT}"
  set_test_environment "${run_file}" SCHOLIUM_UPGRADE_DRIVER_LABEL "${label}"
  "${DEVELOPER_DIR}/usr/bin/xcodebuild" \
    -xctestrun "${run_file}" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -parallel-testing-enabled NO \
    -maximum-parallel-testing-workers 1 \
    -resultBundlePath "${RESULTS}/${label}.xcresult" \
    test-without-building \
    -only-testing:ScholiumUITests/ScholiumUpgradeSafetyUITests/testReadOnlyLaunch \
    > "${OUTPUT}/${label}.log"
}

run_app baseline "${BASELINE}"
python3 "${MANIFEST_TOOL}" capture --root "${TRIPTYCH}" --output "${MANIFESTS}/after-baseline.json"
python3 "${MANIFEST_TOOL}" capture --root "${HOME_ROOT}" --output "${MANIFESTS}/home-after-baseline.json"
python3 "${MANIFEST_TOOL}" compare \
  --before "${MANIFESTS}/before.json" \
  --after "${MANIFESTS}/after-baseline.json" \
  --portable-allowlist "${ALLOWLIST}" \
  > "${OUTPUT}/baseline-comparison.log"

run_app candidate "${CANDIDATE}"
python3 "${MANIFEST_TOOL}" capture --root "${TRIPTYCH}" --output "${MANIFESTS}/after-candidate.json"
python3 "${MANIFEST_TOOL}" capture --root "${HOME_ROOT}" --output "${MANIFESTS}/home-after-candidate.json"
python3 "${MANIFEST_TOOL}" compare \
  --before "${MANIFESTS}/before.json" \
  --after "${MANIFESTS}/after-candidate.json" \
  --portable-allowlist "${ALLOWLIST}" \
  > "${OUTPUT}/candidate-comparison.log"

print "Upgrade-safety evidence: ${OUTPUT}"
if [[ "${baseline_hash}" == "${candidate_hash}" ]]; then
  print "Evidence class: harness proof with identical builds (not a differential upgrade result)"
else
  print "Evidence class: differential baseline/candidate upgrade check"
fi
