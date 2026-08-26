#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
QA_ROOT="${ROOT}/.build/qa-runtime"
QA_APP="${QA_ROOT}/Scholium-QA.app"
FIXTURES="${QA_ROOT}/fixtures"
QA_HOME="${QA_ROOT}/home"
QA_BUILD_DERIVED="${ROOT}/.build/qa-swiftpm"
UI_TEST_DERIVED="${ROOT}/.build/qa-ui-derived-data"
REGISTERED_QA="${QA_ROOT}/registered/Scholium-Codex-QA-Do-Not-Use.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
QA_RUN_LOCK="${ROOT}/.build/com.scholium.qa.ui-tests.lock"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
export SCHOLIUM_QA_FIXTURES="${FIXTURES}"

require_qa_free_space() {
  local available_kb minimum_kb
  available_kb="$(df -Pk "${ROOT}" | awk 'NR == 2 { print $4 }')"
  minimum_kb=$((20 * 1024 * 1024))
  if [[ ! "${available_kb}" =~ '^[0-9]+$' ]] || (( available_kb < minimum_kb )); then
    print -u2 "Scholium UI automation requires at least 20 GiB free on the workspace volume."
    print -u2 "Run Tools/Scripts/manage-development-storage.sh clean-all --delete, then retry."
    exit 74
  fi
}

acquire_qa_run_lock() {
  mkdir -p "${ROOT}/.build"
  if mkdir "${QA_RUN_LOCK}" 2>/dev/null; then
    print "$$" > "${QA_RUN_LOCK}/pid"
    return
  fi

  local previous_pid=""
  previous_pid="$(<"${QA_RUN_LOCK}/pid" 2>/dev/null || true)"
  if [[ -n "${previous_pid}" ]] && kill -0 "${previous_pid}" 2>/dev/null; then
    print -u2 "A Scholium QA run is already active (PID ${previous_pid}). Refusing to launch another instance."
    exit 75
  fi

  rm -rf "${QA_RUN_LOCK}"
  mkdir "${QA_RUN_LOCK}" || {
    print -u2 "Unable to acquire the Scholium QA run lock."
    exit 75
  }
  print "$$" > "${QA_RUN_LOCK}/pid"
}

terminate_qa_instances() {
  pkill -f "${QA_APP}/Contents/MacOS/Scholium" 2>/dev/null || true
  pkill -f "/private${QA_APP}/Contents/MacOS/Scholium" 2>/dev/null || true
  pkill -f "${REGISTERED_QA}/Contents/MacOS/Scholium" 2>/dev/null || true

  # Also catch this checkout's QA image when its command was launched with a
  # relative path and therefore does not contain QA_APP in `ps` output.
  local qa_pid executable
  local qa_pids=("${(@f)$(pgrep -x Scholium 2>/dev/null || true)}")
  for qa_pid in "${qa_pids[@]}"; do
    [[ -n "${qa_pid}" ]] || continue
    executable="$(
      /usr/sbin/lsof -a -p "${qa_pid}" -d txt -Fn 2>/dev/null \
        | sed -n 's/^n//p' \
        | head -n 1
    )"
    case "${executable}" in
      "${QA_APP}/Contents/MacOS/Scholium"|\
      "/private${QA_APP}/Contents/MacOS/Scholium"|\
      "${REGISTERED_QA}/Contents/MacOS/Scholium")
        kill "${qa_pid}" 2>/dev/null || true
        ;;
    esac
  done
}

cleanup() {
  local result_staging="${ROOT}/.build/qa-xcresult-staging-$$"
  local result_bundles=("${UI_TEST_DERIVED}/Logs/Test/"*.xcresult(N))
  if [[ "${SCHOLIUM_QA_KEEP_ARTIFACTS:-0}" != "1" ]] && (( ${#result_bundles[@]} > 0 )); then
    mkdir -p "${result_staging}"
    # Each invocation needs its own newest result as evidence. Carrying every
    # historical bundle through a clean QA run makes cleanup grow without
    # bound and can outlive the test itself.
    cp -R "${result_bundles[-1]}" "${result_staging}/"
  fi

  terminate_qa_instances
  "${LSREGISTER}" -u "${REGISTERED_QA}" 2>/dev/null || true
  defaults delete com.scholium.qa 2>/dev/null || true
  rm -rf "${REGISTERED_QA}"
  if [[ "${SCHOLIUM_QA_KEEP_ARTIFACTS:-0}" != "1" ]]; then
    rm -rf \
      "${QA_APP}" \
      "${FIXTURES}" \
      "${QA_HOME}" \
      "${QA_BUILD_DERIVED}" \
      "${UI_TEST_DERIVED}"
  fi
  if [[ "${SCHOLIUM_QA_KEEP_ARTIFACTS:-0}" != "1" && -d "${result_staging}" ]]; then
    mkdir -p "${UI_TEST_DERIVED}/Logs/Test"
    cp -R "${result_staging}/"*.xcresult "${UI_TEST_DERIVED}/Logs/Test/"
    rm -rf "${result_staging}"
  fi
  if [[ "$(<"${QA_RUN_LOCK}/pid" 2>/dev/null || true)" == "$$" ]]; then
    rm -rf "${QA_RUN_LOCK}"
  fi
}

acquire_qa_run_lock
trap cleanup EXIT

"${ROOT}/Tools/Scripts/require-unlocked-ui-host.sh"
require_qa_free_space

DEVELOPER_DIR="${DEVELOPER_DIR}" "${ROOT}/Tools/Scripts/build-qa-app.sh"
[[ -d "${QA_APP}" && -d "${FIXTURES}" ]] || {
  print -u2 "The isolated QA app or disposable fixture copy was not created."
  exit 1
}

if [[ -d "${REGISTERED_QA}" ]]; then
  existing_id="$(plutil -extract CFBundleIdentifier raw "${REGISTERED_QA}/Contents/Info.plist" 2>/dev/null || true)"
  [[ "${existing_id}" == "com.scholium.qa" ]] || {
    print -u2 "Refusing to replace non-QA application at ${REGISTERED_QA}."
    exit 1
  }
  "${LSREGISTER}" -u "${REGISTERED_QA}" || true
  rm -rf "${REGISTERED_QA}"
fi
mkdir -p "${REGISTERED_QA:h}"
cp -R "${QA_APP}" "${REGISTERED_QA}"
"${LSREGISTER}" -f -R -trusted "${REGISTERED_QA}"
# Register the disposable bundle so XCUIApplication can resolve its bundle
# identifier. The test process must perform the only launch; pre-opening the
# app here would create a second window before launchEnvironment is applied.
profile="${1:-smoke}"
case "${profile}" in
  smoke|complete|focused)
    shift $(( $# > 0 ? 1 : 0 ))
    ;;
  *)
    profile="focused"
    ;;
esac
test_arguments=("$@")
common_arguments=(
  -project "${ROOT}/ScholiumUITests.xcodeproj" \
  -scheme ScholiumUITests \
  -destination "platform=macOS" \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -derivedDataPath "${UI_TEST_DERIVED}"
)

if [[ "${profile}" == "smoke" ]]; then
  test_arguments=(
    "-only-testing:ScholiumUITests/ScholiumUITests/testCanonicalAcceptanceJourney"
    "${test_arguments[@]}"
  )
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild "${common_arguments[@]}" test "${test_arguments[@]}"
elif [[ "${profile}" == "complete" ]]; then
  manifest="${ROOT}/.build/qa-complete-test-manifest.json"
  acceptance_filter="-only-testing:ScholiumUITests/ScholiumUITests"
  rm -f "${manifest}"
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild "${common_arguments[@]}" build-for-testing
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild \
    "${common_arguments[@]}" \
    -enumerate-tests \
    -test-enumeration-style flat \
    -test-enumeration-format json \
    -test-enumeration-output-path "${manifest}" \
    "${acceptance_filter}" \
    "${test_arguments[@]}" \
    test-without-building
  [[ -s "${manifest}" ]] || {
    print -u2 "Complete UI test enumeration produced no manifest."
    exit 1
  }
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild \
    "${common_arguments[@]}" \
    "${acceptance_filter}" \
    "${test_arguments[@]}" \
    test-without-building
else
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild "${common_arguments[@]}" test "${test_arguments[@]}"
fi
