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
QA_PREFERENCES_CAPTURED=0
FRAME_SUPERVISOR_PID=""
FRAME_REQUESTS=""

if [[ "${1:-}" == "stress" || "${1:-}" == "visible-editor" ]]; then
  python3 - "${ROOT}" "${SCHOLIUM_TEST_VAULTS:-}" <<'PY'
import json
import os
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
fixture = Path(sys.argv[2]).resolve()
if not fixture.is_relative_to(root / '.build'):
    raise SystemExit('Stress QA requires a generated fixture under repository .build.')
manifest = json.loads((fixture / 'stress-manifest.json').read_text())
if manifest.get('synthetic_nonprivate') is not True or manifest.get('counts', {}).get('notes', 0) < 508:
    raise SystemExit('Stress QA requires the complete synthetic stress scenarios.')
selection = os.environ.get('SCHOLIUM_STRESS_UI_SCENARIOS')
if selection is not None:
    selected = [item.strip() for item in selection.split(',')]
    supported = {'long_prose', 'dense_links', 'nested_callouts', 'image_gallery', 'format_matrix'}
    if not selected or len(set(selected)) != len(selected) or not all(item in supported for item in selected):
        raise SystemExit('SCHOLIUM_STRESS_UI_SCENARIOS requires a nonempty, duplicate-free selection from the five existing stress scenarios.')
PY
fi

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
  local qa_pid executable journey_suffix journey_id bundle_path bundle_id restoration_id
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
      "${QA_ROOT}/journeys/"*/Scholium-Restoration-QA.app/Contents/MacOS/Scholium)
        # Interrupted native restoration can outlive XCTest tearDown. Admit
        # only this checkout's exact generated journey and bundle identities.
        journey_suffix="${executable#${QA_ROOT}/journeys/}"
        journey_id="${journey_suffix%%/*}"
        [[ "${journey_id}" =~ '^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$' ]] || continue
        [[ "${journey_suffix}" == "${journey_id}/Scholium-Restoration-QA.app/Contents/MacOS/Scholium" ]] || continue
        bundle_path="${QA_ROOT}/journeys/${journey_id}/Scholium-Restoration-QA.app"
        bundle_id="$(plutil -extract CFBundleIdentifier raw "${bundle_path}/Contents/Info.plist" 2>/dev/null || true)"
        restoration_id="${bundle_id#com.scholium.qa.restoration.}"
        [[ "${restoration_id}" =~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' ]] || continue
        [[ "${bundle_id}" == "com.scholium.qa.restoration.${restoration_id}" ]] || continue
        kill "${qa_pid}" 2>/dev/null || true
        ;;
    esac
  done
}

cleanup() {
  local exit_code=$?
  if [[ -n "${FRAME_SUPERVISOR_PID}" ]]; then
    kill -TERM "${FRAME_SUPERVISOR_PID}" 2>/dev/null || true
    wait "${FRAME_SUPERVISOR_PID}" || true
  fi
  if [[ -n "${FRAME_REQUESTS}" && "${SCHOLIUM_QA_KEEP_ARTIFACTS:-0}" != 1 && ${exit_code} == 0 ]]; then
    rm -rf "${FRAME_REQUESTS}"
  fi
  if (( ! QA_PREFERENCES_CAPTURED )); then
    if [[ "$(<"${QA_RUN_LOCK}/pid" 2>/dev/null || true)" == "$$" ]]; then
      rm -rf "${QA_RUN_LOCK}"
    fi
    return "${exit_code}"
  fi
  local result_staging="${ROOT}/.build/qa-xcresult-staging-$$"
  local result_bundles=("${UI_TEST_DERIVED}/Logs/Test/"*.xcresult(N))


  terminate_qa_instances
  "${LSREGISTER}" -u "${REGISTERED_QA}" 2>/dev/null || true
  if ! python3 "${ROOT}/Tools/Scripts/preserve-qa-preferences.py" restore --owner-pid "$$"; then
    print -u2 "QA preferences were not verified; original snapshot and QA artifacts retained."
    if [[ "$(<"${QA_RUN_LOCK}/pid" 2>/dev/null || true)" == "$$" ]]; then
      rm -rf "${QA_RUN_LOCK}"
    fi
    trap - EXIT
    exit 1
  fi
  if [[ "${SCHOLIUM_QA_KEEP_ARTIFACTS:-0}" != "1" ]] && (( ${#result_bundles[@]} > 0 )); then
    mkdir -p "${result_staging}"
    # Each invocation needs its own newest result as evidence. Carrying every
    # historical bundle through a clean QA run makes cleanup grow without
    # bound and can outlive the test itself.
    cp -R "${result_bundles[-1]}" "${result_staging}/"
  fi
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
  trap - EXIT
  exit "${exit_code}"
}

acquire_qa_run_lock
trap cleanup EXIT

"${ROOT}/Tools/Scripts/require-unlocked-ui-host.sh"
require_qa_free_space

python3 "${ROOT}/Tools/Scripts/preserve-qa-preferences.py" capture --owner-pid "$$"
QA_PREFERENCES_CAPTURED=1

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
  smoke|complete|focused|stress|tab-stress|visible-editor|foreground-opening)
    shift $(( $# > 0 ? 1 : 0 ))
    ;;
  *)
    profile="focused"
    ;;
esac
test_arguments=("$@")
critical_ui_tests=(
  "-only-testing:ScholiumUITests/ScholiumUITests/testFixtureLaunchWithoutExplicitSessionIDUsesOneWindowSession"
  "-only-testing:ScholiumUITests/ScholiumUITests/testStorageUnavailableRetriesWithoutConstructingWorkspace"
  "-only-testing:ScholiumUITests/ScholiumUITests/testPortableFolderPanelRejectsWrongExactFolderAndRecovers"
  "-only-testing:ScholiumUITests/ScholiumUITests/testRestoreAccessFolderSelectionUsesScenePresenter"
  "-only-testing:ScholiumUITests/ScholiumUITests/testAgentChangesShowsExactUpdateAndRestoresOriginalBytes"
  "-only-testing:ScholiumUITests/ScholiumUITests/testDirtyLivePreviewCommitsBeforeSwitchingNotes"
  "-only-testing:ScholiumUITests/ScholiumUITests/testDocumentModeAndLibrarySwitchHandoffsStayBoundedWithoutSourceExposure"
  "-only-testing:ScholiumUITests/ScholiumUITests/testDirtyExternalEditPreservesTheBufferAndPresentsConflictRecovery"
  "-only-testing:ScholiumUITests/ScholiumUITests/testConflictReloadRejectsADiskRevisionThatChangedAfterComparison"
  "-only-testing:ScholiumUITests/ScholiumUITests/testDirtyEditorBufferSurvivesTheQAFaultRoute"
  "-only-testing:ScholiumUITests/ScholiumUITests/testDirtyExternalRenameRebindsAndPreservesTheUncommittedEditorBuffer"
  "-only-testing:ScholiumUITests/ScholiumUITests/testNativeCommandButtonsPreserveDefaultDisabledAndCancelActions"
  "-only-testing:ScholiumUITests/ScholiumUITests/testMoveNoteFailureRetainsDraftAndAllowsRetry"
  "-only-testing:ScholiumUITests/ScholiumUITests/testDuplicateNoteFailureRetainsDraftAndAllowsRetry"
  "-only-testing:ScholiumUITests/ScholiumUITests/testRenameFolderFailureRetainsDraftAndAllowsRetry"
  "-only-testing:ScholiumUITests/ScholiumUITests/testMoveFolderFailureRetainsDraftAndAllowsRetry"
  "-only-testing:ScholiumUITests/FreshIndexDiagnosticOutputTests"
  "-only-testing:ScholiumUITests/QAClipboardPreservationTests"
  "-only-testing:ScholiumUITests/ScholiumUITests/testNativeTriptychWorkspaceNavigatorUsesSelectionAndArrowKeys"
)
common_arguments=(
  -project "${ROOT}/ScholiumUITests.xcodeproj" \
  -scheme ScholiumUITests \
  -destination "platform=macOS" \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -derivedDataPath "${UI_TEST_DERIVED}"
)

if [[ "${profile}" == "foreground-opening" ]]; then
  label="${SCHOLIUM_FOREGROUND_OPEN_LABEL:-baseline}"
  [[ "${label}" == baseline || "${label}" == candidate ]] || {
    print -u2 "Foreground opening diagnostics require baseline or candidate."
    exit 64
  }
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild "${common_arguments[@]}" build-for-testing
  recorder="${UI_TEST_DERIVED}/qa-window-frame-recorder"
  DEVELOPER_DIR="${DEVELOPER_DIR}" swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "${UI_TEST_DERIVED}/recorder-module-cache" \
    "${ROOT}/Tools/Diagnostics/RecordQAWindowFrames.swift" -o "${recorder}"
  FRAME_REQUESTS="${QA_ROOT}/frame-requests-$$"
  mkdir "${FRAME_REQUESTS}"
  python3 "${ROOT}/Tools/Diagnostics/qa_window_frame_supervisor.py" \
    --requests "${FRAME_REQUESTS}" --recorder "${recorder}" --owner-pid "$$" \
    > "${UI_TEST_DERIVED}/frame-supervisor.log" 2>&1 &
  FRAME_SUPERVISOR_PID=$!
  base_run="$(find "${UI_TEST_DERIVED}/Build/Products" -maxdepth 1 -name '*.xctestrun' -print -quit)"
  foreground_run="${UI_TEST_DERIVED}/Build/Products/ScholiumForegroundOpening.xctestrun"
  python3 - "${base_run}" "${foreground_run}" "${label}" "${FRAME_REQUESTS}" <<'PY'
import os
import plistlib
import sys
source, target, label, requests = sys.argv[1:]
with open(source, 'rb') as stream:
    run = plistlib.load(stream)
environment = run['ScholiumUITests'].setdefault('EnvironmentVariables', {})
environment['SCHOLIUM_FOREGROUND_OPEN_LABEL'] = label
environment['SCHOLIUM_FOREGROUND_FRAME_REQUEST_DIRECTORY'] = requests
environment['SCHOLIUM_FOREGROUND_OPEN_INITIAL_ALTERNATE'] = os.environ.get('SCHOLIUM_FOREGROUND_OPEN_INITIAL_ALTERNATE', '0')
environment['SCHOLIUM_FOREGROUND_OPEN_RETAIN_TARGET'] = os.environ.get('SCHOLIUM_FOREGROUND_OPEN_RETAIN_TARGET', '0')
environment['SCHOLIUM_FOREGROUND_OPEN_NEW_TAB'] = os.environ.get('SCHOLIUM_FOREGROUND_OPEN_NEW_TAB', '0')
with open(target, 'wb') as stream:
    plistlib.dump(run, stream)
PY
  if (( ${#test_arguments[@]} == 0 )); then
    test_arguments=(-only-testing:ScholiumUITests/ScholiumPerformanceUITests/testForegroundNoteOpeningDiagnostic)
  fi
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild \
    -xctestrun "${foreground_run}" -destination "platform=macOS" \
    -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
    -derivedDataPath "${UI_TEST_DERIVED}" "${test_arguments[@]}" test-without-building
elif [[ "${profile}" == "visible-editor" ]]; then
  label="${SCHOLIUM_VISIBLE_EDITOR_LABEL:-baseline}"
  [[ "${label}" == baseline || "${label}" == profile || "${label}" == candidate ]] || {
    print -u2 "Visible editor diagnostics require baseline, profile, or candidate."
    exit 64
  }
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild "${common_arguments[@]}" build-for-testing
  base_run="$(find "${UI_TEST_DERIVED}/Build/Products" -maxdepth 1 -name '*.xctestrun' -print -quit)"
  visible_run="${UI_TEST_DERIVED}/Build/Products/ScholiumVisibleEditor.xctestrun"
  python3 - "${base_run}" "${visible_run}" "${label}" <<'PY'
import plistlib
import sys
source, target, label = sys.argv[1:]
with open(source, 'rb') as stream:
    run = plistlib.load(stream)
run['ScholiumUITests'].setdefault('EnvironmentVariables', {})['SCHOLIUM_VISIBLE_EDITOR_LABEL'] = label
with open(target, 'wb') as stream:
    plistlib.dump(run, stream)
PY
  if (( ${#test_arguments[@]} == 0 )); then
    test_arguments=(
      -only-testing:ScholiumUITests/ScholiumPerformanceUITests/testVisibleStressLongProseDiagnostic
      -only-testing:ScholiumUITests/ScholiumPerformanceUITests/testVisibleStressDenseLinksDiagnostic
      -only-testing:ScholiumUITests/ScholiumPerformanceUITests/testVisibleStressImageGalleryDiagnostic
    )
  fi
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild \
    -xctestrun "${visible_run}" -destination "platform=macOS" \
    -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
    -derivedDataPath "${UI_TEST_DERIVED}" "${test_arguments[@]}" test-without-building
elif [[ "${profile}" == "stress" || "${profile}" == "tab-stress" ]]; then
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild "${common_arguments[@]}" build-for-testing
  base_run="$(find "${UI_TEST_DERIVED}/Build/Products" -maxdepth 1 -name '*.xctestrun' -print -quit)"
  [[ -n "${base_run}" ]] || { print -u2 "No stress QA test driver was built."; exit 1; }
  stress_run="${UI_TEST_DERIVED}/Build/Products/ScholiumStress.xctestrun"
  stress_output="${SCHOLIUM_STRESS_UI_OUTPUT:-}"
  stress_test="testLargeSyntheticVaultDocumentLifecycleStress"
  if [[ "${profile}" == "tab-stress" ]]; then
    stress_output="${SCHOLIUM_TAB_STRESS_OUTPUT:-}"
    stress_test="testRepeatedOpenInNewTabReleasesDocumentOwners"
  fi
  python3 - "${base_run}" "${stress_run}" "${stress_output}" "${profile}" <<'PY'
import os
import plistlib
import sys
from pathlib import Path

source, target, output, profile = sys.argv[1:]
with open(source, 'rb') as stream:
    run = plistlib.load(stream)
environment = run['ScholiumUITests'].setdefault('EnvironmentVariables', {})
prefix = 'SCHOLIUM_TAB_STRESS' if profile == 'tab-stress' else 'SCHOLIUM_STRESS'
environment[prefix + '_UI'] = '1'
selection = os.environ.get('SCHOLIUM_STRESS_UI_SCENARIOS')
if selection is None:
    environment.pop('SCHOLIUM_STRESS_UI_SCENARIOS', None)
else:
    environment['SCHOLIUM_STRESS_UI_SCENARIOS'] = selection
if output:
    environment[prefix + ('_OUTPUT' if profile == 'tab-stress' else '_UI_OUTPUT')] = output
with open(target, 'wb') as stream:
    plistlib.dump(run, stream)
PY
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild \
    -xctestrun "${stress_run}" -destination "platform=macOS" \
    -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
    -derivedDataPath "${UI_TEST_DERIVED}" \
    "-only-testing:ScholiumUITests/ScholiumUITests/${stress_test}" \
    "${test_arguments[@]}" test-without-building
elif [[ "${profile}" == "smoke" ]]; then
  test_arguments=(
    "${critical_ui_tests[1]}"
    "${test_arguments[@]}"
  )
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild "${common_arguments[@]}" test "${test_arguments[@]}"
elif [[ "${profile}" == "complete" ]]; then
  manifest="${ROOT}/.build/qa-complete-test-manifest.json"
  acceptance_filters=("${critical_ui_tests[@]}" "${test_arguments[@]}")
  rm -f "${manifest}"
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild "${common_arguments[@]}" build-for-testing
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild \
    "${common_arguments[@]}" \
    -enumerate-tests \
    -test-enumeration-style flat \
    -test-enumeration-format json \
    -test-enumeration-output-path "${manifest}" \
    "${acceptance_filters[@]}" \
    test-without-building
  [[ -s "${manifest}" ]] || {
    print -u2 "Complete UI test enumeration produced no manifest."
    exit 1
  }
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild \
    "${common_arguments[@]}" \
    "${acceptance_filters[@]}" \
    test-without-building
else
  DEVELOPER_DIR="${DEVELOPER_DIR}" xcodebuild "${common_arguments[@]}" test "${test_arguments[@]}"
fi
