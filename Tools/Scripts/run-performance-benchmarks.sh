#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
MODE=scenario_only
APP=""
FIXTURE=""
OUTPUT=""
WARMUPS=0
SAMPLES=1
RELAUNCH_COOLDOWN_MS=0
METRIC_COOLDOWN_SECONDS=0
MEMORY_WATCH_PID=""
ONLY_METRIC=""
PREPARED_DRIVER=""
DRIVER_RUN_FILES=()
usage() {
  cat <<'EOF'
Usage:
  run-performance-benchmarks.sh --app APP --fixture RDF1 --output DIR [--scenario]
  run-performance-benchmarks.sh --app APP --fixture RDF1 --output DIR --scenario --metric NAME
  run-performance-benchmarks.sh --app APP --fixture RDF1 --output DIR --scenario --metric first_read_activation --warmups 5 --samples 30
  run-performance-benchmarks.sh --app APP --fixture RDF1 --output DIR --scenario --metric first_edit_activation --warmups 5 --samples 30
  run-performance-benchmarks.sh --app APP --fixture RDF1 --output DIR --gate --prepared-driver DIR

Scenario mode defaults to 0 warm-ups and 1 retained sample per metric and is
bounded to at most 3 + 10, except for fixed 5 + 30 first-use Review or Edit
diagnostics. Those exceptions remain scenario-only evidence.
Gate mode is fixed at 5 + 30, batches warm Search and Read inside one process,
cools between cold relaunches and metrics, and never compiles after the
prepared-driver boundary. It additionally requires a clean exact-tag checkout,
matching packaged and driver provenance, and
SCHOLIUM_RELEASE_OWNER_APPROVED_THRESHOLDS=1.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --fixture) FIXTURE="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --scenario) MODE=scenario_only; shift ;;
    --gate)
      MODE=product_gate
      WARMUPS=5
      SAMPLES=30
      RELAUNCH_COOLDOWN_MS=1500
      METRIC_COOLDOWN_SECONDS=15
      shift
      ;;
    --warmups) WARMUPS="$2"; shift 2 ;;
    --samples) SAMPLES="$2"; shift 2 ;;
    --metric) ONLY_METRIC="$2"; shift 2 ;;
    --prepared-driver) PREPARED_DRIVER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "Unknown argument: $1"; usage >&2; exit 64 ;;
  esac
done

[[ -n "${APP}" && -n "${FIXTURE}" && -n "${OUTPUT}" ]] || {
  usage >&2
  exit 64
}
[[ "${WARMUPS}" == <-> && "${SAMPLES}" == <-> && "${SAMPLES}" -gt 0 ]] || {
  print -u2 "Warm-ups must be nonnegative and samples must be positive integers."
  exit 64
}
IS_FIRST_USE_FULL_SCENARIO=0
if [[ "${MODE}" == scenario_only
      && ( "${ONLY_METRIC}" == first_read_activation
        || "${ONLY_METRIC}" == first_edit_activation )
      && "${WARMUPS}" == 5
      && "${SAMPLES}" == 30 ]]; then
  IS_FIRST_USE_FULL_SCENARIO=1
  RELAUNCH_COOLDOWN_MS=1500
fi
if [[ "${MODE}" == scenario_only
      && "${IS_FIRST_USE_FULL_SCENARIO}" != 1
      && ( "${WARMUPS}" -gt 3 || "${SAMPLES}" -gt 10 ) ]]; then
  print -u2 "A scenario run is limited to 3 warm-ups and 10 retained samples."
  exit 64
fi
if [[ "${MODE}" == product_gate && ( "${WARMUPS}" != 5 || "${SAMPLES}" != 30 ) ]]; then
  print -u2 "A product gate is fixed at 5 warm-ups and 30 retained samples."
  exit 64
fi
if [[ "${MODE}" == product_gate && -z "${PREPARED_DRIVER}" ]]; then
  print -u2 "A product gate requires --prepared-driver from prepare-performance-driver.sh."
  exit 64
fi
LATENCY_METRICS=(
  warm_library_launch
  indexed_search
  warm_read_activation
  first_read_activation
  editor_key_to_paint
  editor_mode_transition
  editor_cached_preview
  warm_edit_activation
  first_edit_activation
  editor_visible_projection
)
RUN_MEMORY=1
if [[ -n "${ONLY_METRIC}" ]]; then
  [[ "${MODE}" == scenario_only ]] || {
    print -u2 "A focused metric is available only in scenario mode."
    exit 64
  }
  case "${ONLY_METRIC}" in
    warm_library_launch|indexed_search|warm_read_activation|first_read_activation|editor_key_to_paint|editor_mode_transition|editor_cached_preview|warm_edit_activation|first_edit_activation|editor_visible_projection)
      LATENCY_METRICS=("${ONLY_METRIC}")
      RUN_MEMORY=0
      ;;
    editor_retained_memory)
      LATENCY_METRICS=()
      ;;
    *)
      print -u2 "Unknown performance metric: ${ONLY_METRIC}"
      exit 64
      ;;
  esac
fi
SUMMARY_METRICS=("${LATENCY_METRICS[@]}")
if (( RUN_MEMORY )); then
  SUMMARY_METRICS+=(editor_retained_memory)
fi

APP="${APP:P}"
FIXTURE="${FIXTURE:P}"
OUTPUT="${OUTPUT:A}"
if [[ -n "${PREPARED_DRIVER}" ]]; then
  PREPARED_DRIVER="${PREPARED_DRIVER:A}"
  case "${PREPARED_DRIVER}" in
    "${ROOT}/.build"/*) ;;
    *)
      print -u2 "Prepared performance drivers must remain under ${ROOT}/.build."
      exit 65
      ;;
  esac
fi
[[ -d "${APP}" && -x "${APP}/Contents/MacOS/Scholium" ]] || {
  print -u2 "Invalid Scholium app bundle: ${APP}"
  exit 66
}
[[ -f "${FIXTURE}/manifest.json" ]] || {
  print -u2 "Missing RDF-1 manifest: ${FIXTURE}/manifest.json"
  exit 66
}
case "${OUTPUT}" in
  "${ROOT}"|"${ROOT}"/*|"${FIXTURE}"|"${FIXTURE}"/*)
    print -u2 "Performance evidence must be outside the source checkout and RDF-1."
    exit 65
    ;;
esac
if [[ -e "${OUTPUT}" && -n "$(find "${OUTPUT}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  print -u2 "Refusing to overwrite a nonempty output directory: ${OUTPUT}"
  exit 65
fi

export DEVELOPER_DIR
[[ -x "${DEVELOPER_DIR}/usr/bin/xcodebuild" ]] || {
  print -u2 "Xcode toolchain is unavailable at ${DEVELOPER_DIR}."
  exit 69
}
"${ROOT}/Tools/Scripts/require-unlocked-ui-host.sh"
python3 "${ROOT}/Tools/Scripts/generate-rdf1.py" --output "${FIXTURE}" --verify
codesign --verify --deep --strict "${APP}"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "${APP}/Contents/Info.plist")"
if pgrep -f '/Contents/MacOS/Scholium( |$)' >/dev/null 2>&1; then
  print -u2 "Refusing to run while another Scholium process is active."
  exit 65
fi
ARTIFACT_KIND=debug_qa
if [[ "${BUNDLE_ID}" == com.scholium.app ]]; then
  ARTIFACT_KIND=packaged_release
fi

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

PRODUCTION_STATE=""
PRODUCTION_STATE_SIGNATURE=""
if [[ "${ARTIFACT_KIND}" == packaged_release ]]; then
  PRODUCTION_STATE="${HOME}/Library/Application Support/Scholium/State-v1"
  PRODUCTION_STATE_SIGNATURE="$(state_signature "${PRODUCTION_STATE}")"
fi

if [[ "${MODE}" == product_gate ]]; then
  [[ "${SCHOLIUM_RELEASE_OWNER_APPROVED_THRESHOLDS:-0}" == 1 ]] || {
    print -u2 "Release-owner threshold approval is missing."
    exit 77
  }
  [[ "${ARTIFACT_KIND}" == packaged_release ]] || {
    print -u2 "A product gate requires the packaged Release app."
    exit 65
  }
  [[ -z "$(git -C "${ROOT}" status --porcelain)" ]] || {
    print -u2 "A product gate requires a clean worktree."
    exit 65
  }
  EXACT_TAG="$(git -C "${ROOT}" describe --tags --exact-match 2>/dev/null || true)"
  [[ -n "${EXACT_TAG}" ]] || {
    print -u2 "A product gate requires an exact tagged commit."
    exit 65
  }
  PROVENANCE="${APP}/Contents/Resources/ScholiumBuildProvenance.plist"
  [[ -f "${PROVENANCE}" ]] || {
    print -u2 "The packaged app has no build provenance record."
    exit 65
  }
  [[ "$(plutil -extract schema raw "${PROVENANCE}")" == scholium-build-provenance-v1 ]]
  [[ "$(plutil -extract source_clean raw "${PROVENANCE}")" == true ]]
  [[ "$(plutil -extract git_commit raw "${PROVENANCE}")" == "$(git -C "${ROOT}" rev-parse HEAD)" ]]
  [[ "$(plutil -extract git_exact_tag raw "${PROVENANCE}")" == "${EXACT_TAG}" ]]
fi

DRIVER_PRODUCTS=""
BASE_XCTESTRUN=""
if [[ -n "${PREPARED_DRIVER}" ]]; then
  DRIVER_MANIFEST="${PREPARED_DRIVER}/ScholiumPerformanceDriver.plist"
  [[ -f "${DRIVER_MANIFEST}" ]] || {
    print -u2 "Prepared driver manifest is missing: ${DRIVER_MANIFEST}"
    exit 66
  }
  CURRENT_XCODE_BUILD="$("${DEVELOPER_DIR}/usr/bin/xcodebuild" -version | awk '/Build version/{print $3}')"
  [[ "$(plutil -extract schema raw "${DRIVER_MANIFEST}")" == scholium-performance-driver-v1 ]]
  [[ "$(plutil -extract evidence_class raw "${DRIVER_MANIFEST}")" == "${MODE}" ]]
  [[ "$(plutil -extract git_commit raw "${DRIVER_MANIFEST}")" == "$(git -C "${ROOT}" rev-parse HEAD)" ]]
  [[ "$(plutil -extract architecture raw "${DRIVER_MANIFEST}")" == "$(uname -m)" ]]
  [[ "$(plutil -extract xcode_build raw "${DRIVER_MANIFEST}")" == "${CURRENT_XCODE_BUILD}" ]]
  CURRENT_PATCH_SHA256="$(git -C "${ROOT}" diff --binary HEAD | shasum -a 256 | awk '{print $1}')"
  [[ "$(plutil -extract worktree_patch_sha256 raw "${DRIVER_MANIFEST}")" == "${CURRENT_PATCH_SHA256}" ]]
  if [[ "${MODE}" == product_gate ]]; then
    [[ "$(plutil -extract source_clean raw "${DRIVER_MANIFEST}")" == true ]]
    [[ "$(plutil -extract git_exact_tag raw "${DRIVER_MANIFEST}")" == "$(git -C "${ROOT}" describe --tags --exact-match)" ]]
  fi
  DRIVER_PRODUCTS="${PREPARED_DRIVER}/derived-data/Build/Products"
  BASE_XCTESTRUN="$(find "${DRIVER_PRODUCTS}" -maxdepth 1 -name '*.xctestrun' -print -quit)"
  [[ -f "${BASE_XCTESTRUN}" ]] || {
    print -u2 "Prepared driver has no .xctestrun file."
    exit 66
  }
fi

RUN_ID="rdf1_$(date -u +%Y%m%dT%H%M%SZ)_$$"
SCRATCH="${ROOT}/.build/performance-${RUN_ID}"
if [[ "${ARTIFACT_KIND}" == packaged_release ]]; then
  APP_SCRATCH="${HOME}/Library/Application Support/Scholium/Performance Runs/${RUN_ID}"
else
  APP_SCRATCH="${SCRATCH}/app-state"
fi
FIXTURE_COPY="${APP_SCRATCH}/rdf1"
RAW="${SCRATCH}/raw"
DERIVED="${SCRATCH}/derived-data"

cleanup() {
  local exit_code=$?
  local pid
  if [[ -n "${MEMORY_WATCH_PID}" ]]; then
    kill "${MEMORY_WATCH_PID}" 2>/dev/null || true
    wait "${MEMORY_WATCH_PID}" 2>/dev/null || true
  fi
  for run_file in "${DRIVER_RUN_FILES[@]}"; do
    rm -f -- "${run_file}"
  done
  for pid in $(pgrep -f "^${APP}/Contents/MacOS/Scholium( |$)" 2>/dev/null || true); do
    kill "${pid}" 2>/dev/null || true
  done
  if [[ -n "${PRODUCTION_STATE}" ]] \
      && [[ "$(state_signature "${PRODUCTION_STATE}")" != "${PRODUCTION_STATE_SIGNATURE}" ]]; then
    print -u2 "The performance driver mutated production machine state."
    exit_code=1
  fi
  if [[ "${APP_SCRATCH}" != "${SCRATCH}/app-state" ]]; then
    rm -rf "${APP_SCRATCH}"
  fi
  if (( exit_code == 0 )); then
    rm -rf "${SCRATCH}"
  else
    print -u2 "Incomplete performance artifacts retained at ${SCRATCH}"
  fi
  trap - EXIT
  exit "${exit_code}"
}
trap cleanup EXIT

mkdir -p "${SCRATCH}" "${RAW}" "${OUTPUT}"
ditto --norsrc --noextattr --noqtn --noacl "${FIXTURE}" "${FIXTURE_COPY}"
python3 "${ROOT}/Tools/Scripts/generate-rdf1.py" \
  --output "${FIXTURE_COPY}" \
  --verify \
  --allow-outside-tmp

if [[ -z "${PREPARED_DRIVER}" ]]; then
  "${DEVELOPER_DIR}/usr/bin/xcodebuild" \
    -project "${ROOT}/ScholiumUITests.xcodeproj" \
    -scheme ScholiumUITests \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "${DERIVED}" \
    build-for-testing \
    >"${SCRATCH}/build-ui-driver.log"
  DRIVER_PRODUCTS="${DERIVED}/Build/Products"
  BASE_XCTESTRUN="$(find "${DRIVER_PRODUCTS}" -maxdepth 1 -name '*.xctestrun' -print -quit)"
fi
[[ -f "${BASE_XCTESTRUN}" ]] || {
  print -u2 "Xcode did not produce an .xctestrun file."
  exit 70
}

python3 "${ROOT}/Tools/Scripts/capture-performance-environment.py" \
  --output "${RAW}/environment.json" \
  --app "${APP}" \
  --bundle-id "${BUNDLE_ID}" \
  --artifact-kind "${ARTIFACT_KIND}" \
  --fixture-manifest "${FIXTURE_COPY}/manifest.json"

set_test_environment() {
  local plist="$1"
  local key="$2"
  local value="$3"
  /usr/libexec/PlistBuddy \
    -c "Add :ScholiumUITests:EnvironmentVariables:${key} string ${value}" \
    "${plist}"
}

for metric in "${LATENCY_METRICS[@]}"; do
  results="${RAW}/${metric}.jsonl"
  home="${APP_SCRATCH}/home-${metric}"
  run_file="${DRIVER_PRODUCTS}/ScholiumPerformance-${RUN_ID}-${metric}.xctestrun"
  DRIVER_RUN_FILES+=("${run_file}")
  mkdir -p "${home}"
  cp "${BASE_XCTESTRUN}" "${run_file}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH "${APP}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_METRIC "${metric}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_FIXTURE_ROOT "${FIXTURE_COPY}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_HOME_ROOT "${home}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_RESULTS_PATH "${results}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_RUN_ID "${RUN_ID}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_WARMUPS "${WARMUPS}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_SAMPLES "${SAMPLES}"
  set_test_environment "${run_file}" SCHOLIUM_PERFORMANCE_DRIVER_RELAUNCH_COOLDOWN_MS "${RELAUNCH_COOLDOWN_MS}"
  "${DEVELOPER_DIR}/usr/bin/xcodebuild" \
    -xctestrun "${run_file}" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -parallel-testing-enabled NO \
    -maximum-parallel-testing-workers 1 \
    -resultBundlePath "${SCRATCH}/${metric}.xcresult" \
    test-without-building \
    -only-testing:ScholiumUITests/ScholiumPerformanceUITests/testRDF1PerformanceSamples \
    >"${SCRATCH}/${metric}.log"
  if [[ "${MODE}" == product_gate ]]; then
    sleep "${METRIC_COOLDOWN_SECONDS}"
  fi
done

# Retained Editor memory is sampled through the exact app originator's launchd
# service map rather than PPID or process-name matching. The UI journey owns
# the real mode transitions; the external sampler owns attribution and RSS.
if (( RUN_MEMORY )); then
memory_handoff="${RAW}/editor-retained-memory-handoff"
memory_results="${memory_handoff}/editor_retained_memory.jsonl"
memory_progress="${memory_handoff}/editor_retained_memory_progress.jsonl"
memory_acknowledgment="${memory_handoff}/editor_retained_memory.ack"
memory_home="${APP_SCRATCH}/home-editor-retained-memory"
memory_run_file="${DRIVER_PRODUCTS}/ScholiumPerformance-${RUN_ID}-editor-retained-memory.xctestrun"
DRIVER_RUN_FILES+=("${memory_run_file}")
mkdir -p "${memory_home}" "${memory_handoff}"
cp "${BASE_XCTESTRUN}" "${memory_run_file}"
set_test_environment "${memory_run_file}" SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH "${APP}"
set_test_environment "${memory_run_file}" SCHOLIUM_PERFORMANCE_DRIVER_FIXTURE_ROOT "${FIXTURE_COPY}"
set_test_environment "${memory_run_file}" SCHOLIUM_PERFORMANCE_DRIVER_HOME_ROOT "${memory_home}"
set_test_environment "${memory_run_file}" SCHOLIUM_PERFORMANCE_DRIVER_RUN_ID "${RUN_ID}"
set_test_environment "${memory_run_file}" SCHOLIUM_PERFORMANCE_MEMORY_PROGRESS_PATH \
  "${memory_progress}"
set_test_environment "${memory_run_file}" SCHOLIUM_PERFORMANCE_MEMORY_ACKNOWLEDGMENT_PATH \
  "${memory_acknowledgment}"
set_test_environment "${memory_run_file}" SCHOLIUM_PERFORMANCE_MEMORY_TRANSITIONS 50
python3 "${ROOT}/Tools/Scripts/sample-app-process-memory.py" \
  --app "${APP}" \
  --watch-progress "${memory_progress}" \
  --acknowledgment "${memory_acknowledgment}" \
  --output "${memory_results}" \
  --samples 51 \
  --timeout-seconds 900 \
  >"${SCRATCH}/editor-retained-memory-sampler.log" 2>&1 &
MEMORY_WATCH_PID=$!
set +e
"${DEVELOPER_DIR}/usr/bin/xcodebuild" \
  -xctestrun "${memory_run_file}" \
  -destination "platform=macOS,arch=$(uname -m)" \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -resultBundlePath "${SCRATCH}/editor-retained-memory.xcresult" \
  test-without-building \
  -only-testing:ScholiumUITests/ScholiumPerformanceUITests/testRDF1EditorRetainedMemory \
  >"${SCRATCH}/editor-retained-memory.log"
memory_test_status=$?
set -e
if (( memory_test_status != 0 )); then
  kill "${MEMORY_WATCH_PID}" 2>/dev/null || true
  wait "${MEMORY_WATCH_PID}" 2>/dev/null || true
  MEMORY_WATCH_PID=""
  exit "${memory_test_status}"
fi
wait "${MEMORY_WATCH_PID}"
MEMORY_WATCH_PID=""
cp "${memory_results}" "${RAW}/editor_retained_memory.jsonl"
fi

if [[ "${MODE}" == product_gate ]]; then
cjk_results="${RAW}/editor_large_cjk_correctness.jsonl"
cjk_home="${APP_SCRATCH}/home-editor-large-cjk-correctness"
cjk_run_file="${DRIVER_PRODUCTS}/ScholiumPerformance-${RUN_ID}-editor-large-cjk-correctness.xctestrun"
DRIVER_RUN_FILES+=("${cjk_run_file}")
mkdir -p "${cjk_home}"
cp "${BASE_XCTESTRUN}" "${cjk_run_file}"
set_test_environment "${cjk_run_file}" SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH "${APP}"
set_test_environment "${cjk_run_file}" SCHOLIUM_PERFORMANCE_DRIVER_FIXTURE_ROOT "${FIXTURE_COPY}"
set_test_environment "${cjk_run_file}" SCHOLIUM_PERFORMANCE_DRIVER_HOME_ROOT "${cjk_home}"
set_test_environment "${cjk_run_file}" SCHOLIUM_PERFORMANCE_DRIVER_RUN_ID "${RUN_ID}"
set_test_environment "${cjk_run_file}" SCHOLIUM_PERFORMANCE_CJK_RESULTS_PATH "${cjk_results}"
"${DEVELOPER_DIR}/usr/bin/xcodebuild" \
  -xctestrun "${cjk_run_file}" \
  -destination "platform=macOS,arch=$(uname -m)" \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -resultBundlePath "${SCRATCH}/editor-large-cjk-correctness.xcresult" \
  test-without-building \
  -only-testing:ScholiumUITests/ScholiumPerformanceUITests/testRDF1HundredThousandCJKCorrectness \
  >"${SCRATCH}/editor-large-cjk-correctness.log"
fi

python3 "${ROOT}/Tools/Scripts/generate-rdf1.py" \
  --output "${FIXTURE_COPY}" \
  --verify \
  --allow-outside-tmp
cp "${RAW}/"*.jsonl "${OUTPUT}/"
cp "${RAW}/environment.json" "${OUTPUT}/environment.json"
python3 "${ROOT}/Tools/Scripts/summarize-performance-results.py" \
  --input-dir "${RAW}" \
  --output "${OUTPUT}/report.json" \
  --environment "${OUTPUT}/environment.json" \
  --run-id "${RUN_ID}" \
  --warmups "${WARMUPS}" \
  --samples "${SAMPLES}" \
  --evidence-class "${MODE}" \
  --metrics "${SUMMARY_METRICS[@]}"

print "Evidence class: ${MODE}"
print "Report: ${OUTPUT}/report.json"
