#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
QA_APP="/tmp/Scholium-QA.app"
FIXTURES="/tmp/scholium-workbench-qa"
QA_HOME="/tmp/scholium-workbench-home"
QA_BUILD_DERIVED="/tmp/Scholium-Xcode-QA"
UI_TEST_DERIVED="/tmp/Scholium-UITests"
REGISTERED_QA="${HOME}/Applications/Scholium-Codex-QA-Do-Not-Use.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
QA_RUN_LOCK="/tmp/com.kbmanager.qa.ui-tests.lock"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"

ensure_ui_host_is_unlocked() {
  # XCUITest's macOS AutomationMode cannot be enabled while the console is
  # locked. Check the session before building the disposable app so a locked
  # host fails fast without spending CPU on a run that cannot start.
  local locked_state=""
  locked_state="$(ioreg -n Root -d 1 -a 2>/dev/null \
    | plutil -extract 'IOConsoleUsers.0.CGSSessionScreenIsLocked' raw -o - - 2>/dev/null \
    || true)"
  if [[ "${locked_state}" == "true" ]]; then
    print -u2 "Scholium UI tests require an unlocked macOS console. Unlock the Mac, then rerun this command."
    exit 78
  fi
}

acquire_qa_run_lock() {
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
}

cleanup() {
  local result_staging="/tmp/Scholium-XCResults-$$"
  local result_bundles=("${UI_TEST_DERIVED}/Logs/Test/"*.xcresult(N))
  if [[ "${SCHOLIUM_QA_KEEP_ARTIFACTS:-0}" != "1" ]] && (( ${#result_bundles[@]} > 0 )); then
    mkdir -p "${result_staging}"
    cp -R "${result_bundles[@]}" "${result_staging}/"
  fi

  terminate_qa_instances
  "${LSREGISTER}" -u "${REGISTERED_QA}" 2>/dev/null || true
  defaults delete com.kbmanager.qa 2>/dev/null || true
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

ensure_ui_host_is_unlocked

DEVELOPER_DIR="${DEVELOPER_DIR}" "${ROOT}/Tools/Scripts/build-qa-app.sh"
[[ -d "${QA_APP}" && -d "${FIXTURES}" ]] || {
  print -u2 "The isolated QA app or disposable fixture copy was not created."
  exit 1
}

if [[ -d "${REGISTERED_QA}" ]]; then
  existing_id="$(plutil -extract CFBundleIdentifier raw "${REGISTERED_QA}/Contents/Info.plist" 2>/dev/null || true)"
  [[ "${existing_id}" == "com.kbmanager.qa" ]] || {
    print -u2 "Refusing to replace non-QA application at ${REGISTERED_QA}."
    exit 1
  }
  "${LSREGISTER}" -u "${REGISTERED_QA}" || true
  rm -rf "${REGISTERED_QA}"
fi
mkdir -p "${HOME}/Applications"
cp -R "${QA_APP}" "${REGISTERED_QA}"
"${LSREGISTER}" -f -R -trusted "${REGISTERED_QA}"
# Register the disposable bundle so XCUIApplication can resolve its bundle
# identifier. The test process must perform the only launch; pre-opening the
# app here would create a second window before launchEnvironment is applied.
test_arguments=("$@")
if (( ${#test_arguments[@]} == 0 )); then
  # The default acceptance run deliberately launches one QA application once.
  # Individual journeys remain addressable with an explicit xcodebuild selector
  # when a failing behavior needs focused diagnosis.
  test_arguments=(
    "-only-testing:ScholiumUITests/ScholiumUITests/testCanonicalAcceptanceJourney"
  )
fi
DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild \
  -project "${ROOT}/ScholiumUITests.xcodeproj" \
  -scheme ScholiumUITests \
  -destination "platform=macOS" \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -derivedDataPath "${UI_TEST_DERIVED}" \
  test \
  "${test_arguments[@]}"
