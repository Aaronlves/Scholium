#!/bin/zsh
# Keep the global EXIT trap on failures inside functions as well as top-level commands.
setopt POSIX_TRAPS
set -euo pipefail
zmodload zsh/datetime

# Default full remains clean. Daily retains only toolchain-partitioned Swift
# build/dependency state; every invocation executes current-source tests.
PROFILE=full
if (( $# > 0 )); then
  if (( $# != 1 )); then
    print -u2 "Usage: ${0:t} [--ci|--docs]"
    exit 64
  fi
  case "$1" in
    --ci) PROFILE=daily ;;
    --docs) PROFILE=docs ;;
    *) print -u2 "Usage: ${0:t} [--ci|--docs]"; exit 64 ;;
  esac
fi

ROOT="${0:A:h:h:h}"
RUN_ROOT="${ROOT}/.build/ci-verification/runs/${PROFILE}-$(date -u +%Y%m%dT%H%M%S)-$$"
LOG_ROOT="${RUN_ROOT}/logs"
TEST_TEMP="${RUN_ROOT}/tmp"
mkdir -p "${LOG_ROOT}" "${TEST_TEMP}"
export SCHOLIUM_VERIFY_RUN_ROOT="${RUN_ROOT}"
export PYTHONPYCACHEPREFIX="${RUN_ROOT}/pycache"
export TMPDIR="${TEST_TEMP}"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
export DEVELOPER_DIR
swift() { xcrun swift "$@"; }

typeset -F started_at=${EPOCHREALTIME} phase_started=0
phase_label=""
phase_begin() {
  phase_label="$1"
  phase_started=${EPOCHREALTIME}
  print "Starting ${phase_label}"
}
phase_end() {
  local result="${1:-0}"
  local elapsed=$(( EPOCHREALTIME - phase_started ))
  printf '%s\t%.3f\t%s\n' "${phase_label}" "${elapsed}" "${result}" >> "${RUN_ROOT}/timings.tsv"
  printf '%s: %.3f seconds (status %s)\n' "${phase_label}" "${elapsed}" "${result}"
  phase_label=""
}
finish_verification() {
  local result=$?
  trap - EXIT
  # A signalled Swift driver may leave helper children alive as well.
  if (( result == 130 || result == 143 )); then verification_interrupted=1; fi
  if [[ "${verification_interrupted:-0}" == 1 && -n "${GITHUB_OUTPUT:-}" ]]; then
    print "interrupted=true" >> "${GITHUB_OUTPUT}"
  fi
  [[ -z "${phase_label}" ]] || phase_end "${result}"
  {
    print "## Repository verification"
    print ""
    print "Profile: ${PROFILE}; exit status: ${result}."
    print ""
    print "| Phase | Seconds | Status |"
    print "| --- | ---: | ---: |"
    while IFS=$'\t' read -r label seconds code; do
      print "| ${label} | ${seconds} | ${code} |"
    done < "${RUN_ROOT}/timings.tsv"
    print ""
    printf 'Total: %.3f seconds.\n' "$(( EPOCHREALTIME - started_at ))"
    if [[ -f "${RUN_ROOT}/test-results.txt" ]]; then
      print ""
      cat "${RUN_ROOT}/test-results.txt"
      print ""
    fi
    if [[ "${verification_interrupted:-0}" == 1 ]]; then
      print "Interrupted verification: disposable state retained until children stop; cache saving blocked."
    fi
    print "Measurement evidence skipped: ${SCHOLIUM_SKIP_MEASUREMENT_EVIDENCE:-0}. Display evidence skipped: ${SCHOLIUM_SKIP_DISPLAY_EVIDENCE:-0}."
    print "Daily scope defers MarkdownEditorWebViewIntegrationTests, MarkdownEditorReuseTests and Release; docs scope runs documentation and structural guards."
  } > "${RUN_ROOT}/summary.md"
  print "Verification evidence: ${RUN_ROOT}"
  [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || cat "${RUN_ROOT}/summary.md" >> "${GITHUB_STEP_SUMMARY}"
  if [[ "${verification_interrupted:-0}" == 1 ]]; then
    # A signal to the shell alone need not stop its children. Keep their state
    # until the cancellation owner has stopped the whole process tree.
    print "Interrupted verification: retaining disposable state until child processes stop."
  else
    rm -rf -- "${TEST_TEMP}" "${RUN_ROOT}/pycache"
    if [[ "${PROFILE}" == full ]]; then
      rm -rf -- "${RUN_ROOT}/build" "${RUN_ROOT}/release-build" "${RUN_ROOT}/dependencies" "${RUN_ROOT}/release-dependencies"
    fi
  fi
  return "${result}"
}
touch "${RUN_ROOT}/timings.tsv"
trap finish_verification EXIT
verification_interrupted=0
trap 'verification_interrupted=1; exit 130' INT
trap 'verification_interrupted=1; exit 143' TERM

phase_begin "Documentation and structural guards"
if "${ROOT}/Tools/Scripts/verify-structure.sh" > "${LOG_ROOT}/structure.log" 2>&1; then
  cat "${LOG_ROOT}/structure.log"
else
  command_status=$?
  tail -n 80 "${LOG_ROOT}/structure.log" >&2
  exit "${command_status}"
fi
phase_end
phase_begin "RDF-1 fixture"
if "${ROOT}/Tools/Scripts/verify-rdf1-fixture.sh" > "${LOG_ROOT}/rdf1.log" 2>&1; then
  cat "${LOG_ROOT}/rdf1.log"
else
  command_status=$?
  tail -n 80 "${LOG_ROOT}/rdf1.log" >&2
  exit "${command_status}"
fi
phase_end
if [[ "${PROFILE}" == docs ]]; then
  print "Documentation-only repository verification passed."
  exit 0
fi

if [[ "${PROFILE}" == daily ]]; then
  partition="$(python3 "${ROOT}/Tools/Scripts/verification-cache-key.py")"
  SCRATCH="${ROOT}/.build/ci-verification/daily/${partition}/build"
  DEPENDENCIES="${ROOT}/.build/ci-verification/daily/${partition}/dependencies"
else
  SCRATCH="${RUN_ROOT}/build"
  DEPENDENCIES="${RUN_ROOT}/dependencies"
fi
RELEASE_SCRATCH="${RUN_ROOT}/release-build"
print "Swift build state: ${SCRATCH}"
phase_begin "Editor bundle and Web tests"
if "${ROOT}/Tools/Scripts/verify-editor-bundle.sh" > "${LOG_ROOT}/editor.log" 2>&1; then
  cat "${LOG_ROOT}/editor.log"
else
  command_status=$?
  tail -n 80 "${LOG_ROOT}/editor.log" >&2
  exit "${command_status}"
fi
phase_end

# Xcode beta's Swift Testing helper can crash while multiple test products
# tear down their event graphs (and AppKit/WebKit resources) in one invocation.
# Run the complete product set serially; no suite or test is excluded.
swift_test_success_summary() {
  local log="$1"
  local last_run_event
  if rg -q 'No matching test cases were run|recorded an issue|Test run with .* failed|Suite .* failed|fatal error|unexpected signal code' "${log}"; then
    return 1
  fi
  # A helper may exit zero after only part of a run. An earlier completed run
  # cannot establish success if another run started and never finished.
  last_run_event="$(rg -o 'Test run (started\.|with .*)' "${log}" | tail -n 1 || true)"
  print -r -- "${last_run_event}" | rg -x \
    'Test run with [1-9][0-9]* tests?( in [1-9][0-9]* suites?)? passed after [0-9]+(\.[0-9]+)? seconds\.'
}

report_swift_test_success() {
  local label="$1"
  local log="$2"
  local summary="$3"
  print "${label}: ${summary}"
  local skipped="$(rg -c 'Test .* skipped\.' "${log}" || true)"
  print "${label}: ${skipped:-0} declared test skips."
  if [[ -n "${RUN_ROOT:-}" ]]; then
    print "${label}: ${summary} Declared test skips: ${skipped:-0}." >> "${RUN_ROOT}/test-results.txt"
  fi

  if rg -q 'SEARCH_V9_PERFORMANCE_REPORT' "${log}"; then
    rg 'SEARCH_V9_PERFORMANCE_REPORT|"(cold_rebuild_ms|warm_query_p95_ms|incremental_publication_p95_ms|database_bytes|process_peak_rss_bytes)"' \
      "${log}" || true
  fi
}

report_swift_test_failure() {
  local label="$1"
  local log="$2"
  print -u2 "${label} failed. Relevant diagnostics:"
  rg -n 'recorded an issue|Test run with .* failed|Suite .* failed|error:|fatal error|unexpected signal code' \
    "${log}" | tail -n 120 >&2 || true
  print -u2 "Last 80 log lines:"
  tail -n 80 "${log}" >&2
  print -u2 "Complete log: ${log}"
}

run_swift_test_once() {
  local label="$1"
  local log_name="$2"
  shift 2
  local log="${LOG_ROOT}/${log_name}.log"
  local command_status summary

  mkdir -p "${SCRATCH}"
  set +e
  swift test \
    --package-path "${ROOT}" \
    --scratch-path "${SCRATCH}" --cache-path "${DEPENDENCIES}" --manifest-cache local --force-resolved-versions \
    "$@" > "${log}" 2>&1
  command_status=$?
  set -e
  if (( command_status == 0 )); then
    if ! summary="$(swift_test_success_summary "${log}")"; then
      print -u2 "${label} returned success without a complete, positive Swift Testing success summary."
      report_swift_test_failure "${label}" "${log}"
      return 65
    fi
    report_swift_test_success "${label}" "${log}" "${summary}"
    return 0
  fi
  report_swift_test_failure "${label}" "${log}"
  return "${command_status}"
}

# The measurement suites assert absolute durations, so they report the machine
# as much as the code. A shared runner with a fraction of a development Mac's
# cores fails them while saying nothing about Scholium. Rather than loosen
# thresholds that state what Search has to feel like, a caller that cannot
# measure says so, and the omission is printed rather than hidden.
run_measurement_test() {
  local label="$1"
  if [[ "${SCHOLIUM_SKIP_MEASUREMENT_EVIDENCE:-0}" == "1" ]]; then
    echo "Skipping ${label}: SCHOLIUM_SKIP_MEASUREMENT_EVIDENCE=1." >&2
    echo "  Timing thresholds are unmet on this machine by construction, not by regression." >&2
    echo "  This evidence has to come from a development Mac before a release." >&2
    return 0
  fi
  run_swift_test_once "$@"
}

run_swift_test_product() {
  local test_product="$1"
  local attempt log command_status summary
  local -a parallelism_arguments selection_arguments
  parallelism_arguments=()
  selection_arguments=(--filter "${test_product}")
  if [[ "${test_product}" == "ScholiumCoreTests" || "${test_product}" == "ScholiumApplicationTests" || "${test_product}" == "ScholiumAppTests" ]]; then
    # Core's URLSession fixtures and Application's large bridge payloads need
    # CPU time within unchanged deadlines; App shares AppKit/WebKit resources.
    # Serialize top-level tests while preserving each test's concurrent tasks.
    parallelism_arguments=(--no-parallel)
  fi
  if [[ "${test_product}" == "ScholiumAppTests" ]]; then
    if [[ "${PROFILE}" == daily ]]; then
      # These are complete live WebKit ownership suites, including their
      # extension files. Every assertion still runs in the default full gate.
      selection_arguments+=(--skip '^ScholiumAppTests\.(MarkdownEditorWebViewIntegrationTests|MarkdownEditorReuseTests)/')
      print "Daily CI defers MarkdownEditorWebViewIntegrationTests and MarkdownEditorReuseTests to full release verification."
    fi
  fi
  if [[ "${test_product}" == "ScholiumApplicationTests" ]]; then
    # Timed bridge lifecycles and the RDF-1 refresh measurement own quiet
    # processes below, independent of other suites' refresh/I/O contention.
    selection_arguments+=(--skip 'ArchitectureStabilityMeasurementTests|ScholiumAppBridgeTests')
  fi
  mkdir -p "${SCRATCH}"
  for attempt in 1 2 3; do
    log="${LOG_ROOT}/${test_product}-attempt-${attempt}.log"
    set +e
    swift test \
      --package-path "${ROOT}" \
      --scratch-path "${SCRATCH}" --cache-path "${DEPENDENCIES}" --manifest-cache local --force-resolved-versions \
      "${parallelism_arguments[@]}" \
      "${selection_arguments[@]}" > "${log}" 2>&1
    command_status=$?
    set -e
    if (( command_status == 0 )); then
      if ! summary="$(swift_test_success_summary "${log}")"; then
        print -u2 "${test_product} returned success without a complete, positive Swift Testing success summary."
        report_swift_test_failure "${test_product}" "${log}"
        return 65
      fi
      report_swift_test_success "${test_product}" "${log}" "${summary}"
      return 0
    fi
    if (( attempt < 3 )) \
      && rg -q 'swiftpm-testing-helper.*unexpected signal code 11' "${log}" \
      && ! rg -q 'recorded an issue|Test run with .* failed|Suite .* failed' "${log}"; then
      echo "Retrying ${test_product} after the known Xcode beta Swift Testing teardown fault (attempt ${attempt}/3)." >&2
      continue
    fi
    report_swift_test_failure "${test_product}" "${log}"
    return "${command_status}"
  done
}


prepare_swift_tests() {
  local reused=0 command_status
  [[ "${PROFILE}" != daily || ! -d "${SCRATCH}" ]] || reused=1
  local log="${LOG_ROOT}/debug-test-build.log"
  set +e
  swift build --build-tests --package-path "${ROOT}" \
    --scratch-path "${SCRATCH}" --cache-path "${DEPENDENCIES}" \
    --manifest-cache local --force-resolved-versions > "${log}" 2>&1
  command_status=$?
  set -e
  if (( command_status != 0 && reused == 1 )); then
    print -u2 "Reused Swift state failed to build; retaining its log and trying one clean build."
    # These are this toolchain partition's disposable build/dependency products.
    rm -rf -- "${SCRATCH}" "${DEPENDENCIES}"
    log="${LOG_ROOT}/debug-test-build-clean-fallback.log"
    set +e
    swift build --build-tests --package-path "${ROOT}" \
      --scratch-path "${SCRATCH}" --cache-path "${DEPENDENCIES}" \
      --manifest-cache local --force-resolved-versions > "${log}" 2>&1
    command_status=$?
    set -e
  fi
  if (( command_status != 0 )); then
    print -u2 "Debug test build failed. Last 80 log lines:"
    tail -n 80 "${log}" >&2
    print -u2 "Complete log: ${log}"
    return "${command_status}"
  fi
  [[ -z "${GITHUB_OUTPUT:-}" ]] || print "build-ready=true" >> "${GITHUB_OUTPUT}"
  print "Debug test build: $(rg 'Build complete!' "${log}" | tail -n 1 || true)"
}

phase_begin "Current-source Debug test build"
prepare_swift_tests
phase_end

for test_product in \
  ScholiumCoreTests \
  ScholiumPerformanceTests \
  ScholiumContractsTests \
  ScholiumApplicationTests \
  ScholiumAppTests; do
  phase_begin "${test_product}"
  if [[ "${test_product}" == "ScholiumPerformanceTests" ]]; then
    run_measurement_test \
      "ScholiumPerformanceTests performance" \
      "ScholiumPerformanceTests-performance" \
      --no-parallel \
      --filter 'ScholiumPerformanceTests'
  else
    run_swift_test_product "${test_product}"
  fi
  phase_end
  if [[ "${test_product}" == "ScholiumApplicationTests" ]]; then
    phase_begin "Application bridge lifecycle"
    run_swift_test_once \
      "ScholiumApplicationTests bridge lifecycle" \
      "ScholiumApplicationTests-bridge" \
      --no-parallel \
      --filter 'ScholiumApplicationTests.ScholiumAppBridgeTests'
    phase_end
    phase_begin "Application architecture measurement"
    run_measurement_test \
      "ScholiumApplicationTests architecture measurement" \
      "ScholiumApplicationTests-architecture" \
      --no-parallel \
      --filter 'ScholiumApplicationTests.ArchitectureStabilityMeasurementTests'
    phase_end
  fi
done

phase_begin "Compiled localization catalogs"
python3 "${ROOT}/Tools/Scripts/validate-localization-catalogs.py" \
  --stringsdata-root "${SCRATCH}" --swift-source-root "${ROOT}/Scholium" \
  "${ROOT}/Scholium/Resources/Interface.xcstrings" \
  "${ROOT}/Scholium/Resources/Localizable.xcstrings" \
  "${ROOT}/Scholium/Resources/WebKitInterface.xcstrings"

phase_end
phase_begin "Public Application symbol boundary"
# Public Application signatures must be expressible entirely in Contracts and
# Foundation. A leaked Core nominal would defeat the package dependency wall.
swift package --package-path "${ROOT}" --scratch-path "${SCRATCH}" --cache-path "${DEPENDENCIES}" --manifest-cache local --force-resolved-versions \
  dump-symbol-graph --minimum-access-level public
if rg -n 'ScholiumCore' \
  "${SCRATCH}/out/symbolgraph/ScholiumApplication.symbols.json"; then
  echo "Symbol graph guard failed: ScholiumApplication exposes a ScholiumCore type." >&2
  exit 1
fi

phase_end
if [[ "${PROFILE}" == daily ]]; then
  phase_begin "Debug Agent helper"
  helper_log="${LOG_ROOT}/debug-helper-build.log"
  if ! swift build --package-path "${ROOT}" --scratch-path "${SCRATCH}" --cache-path "${DEPENDENCIES}" --manifest-cache local --force-resolved-versions \
    --product ScholiumAgentHelper > "${helper_log}" 2>&1; then
    print -u2 "Debug helper build failed. Last 80 log lines:"
    tail -n 80 "${helper_log}" >&2
    exit 1
  fi
  python3 "${ROOT}/Tools/Scripts/verify-agent-helper.py" "${SCRATCH}/debug/ScholiumAgentHelper"
  phase_end
  print "Daily CI passed; the optimized Release build and Release helper remain required in the default full gate."
  exit 0
fi

phase_begin "Clean Release build"
mkdir -p "${RELEASE_SCRATCH}"
release_log="${LOG_ROOT}/release-build.log"
set +e
swift build --package-path "${ROOT}" -c release \
  --scratch-path "${RELEASE_SCRATCH}" --cache-path "${RUN_ROOT}/release-dependencies" --manifest-cache local --force-resolved-versions > "${release_log}" 2>&1
release_status=$?
set -e
if (( release_status != 0 )); then
  print -u2 "Release build failed. Last 120 log lines:"
  tail -n 120 "${release_log}" >&2
  print -u2 "Complete log: ${release_log}"
  exit "${release_status}"
fi
release_summary="$(rg 'Build complete!' "${release_log}" | tail -n 1 || true)"
print "Release build: ${release_summary:-passed}"


python3 "${ROOT}/Tools/Scripts/verify-agent-helper.py" "${RELEASE_SCRATCH}/release/ScholiumAgentHelper"

phase_end
print "Full repository verification passed."
