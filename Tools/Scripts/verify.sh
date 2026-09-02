#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
SCRATCH="${ROOT}/.build/verification"
RELEASE_SCRATCH="${ROOT}/.build/verification-release"
TEST_TEMP="${ROOT}/.build/verification-tmp"
DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
export DEVELOPER_DIR
rm -rf "${SCRATCH}" "${RELEASE_SCRATCH}" "${TEST_TEMP}"
mkdir -p "${TEST_TEMP}"
export TMPDIR="${TEST_TEMP}"

python3 "${ROOT}/Tools/Scripts/validate-documentation-authority.py"

# The Core resource tree is the sole repository authority for release-shipped
# product Skills. Every shipped SKILL.md must have the local reference files
# it names before SwiftPM accepts the tree as a bundled Beta resource.
python3 - "${ROOT}/ScholiumCore/Resources/Skills" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
missing = []
skill_roots = sorted(path.parent for path in root.rglob("SKILL.md"))
for skill_root in skill_roots:
    source = (skill_root / "SKILL.md").read_text(encoding="utf-8")
    references = sorted(set(re.findall(r"references/[A-Za-z0-9._/-]+", source)))
    for reference in references:
        if not (skill_root / reference).is_file():
            missing.append(f"{skill_root}: {reference}")

if missing:
    print("Protected Skill reference check failed:", file=sys.stderr)
    print("\n".join(missing), file=sys.stderr)
    raise SystemExit(1)

print(f"Shipped Skill references: {len(skill_roots)} SKILL.md roots validated")
PY

# Scholium's current interface contract is English-only. Keep this guard
# scoped to production Swift sources so CJK research fixtures, user Markdown,
# and documentation remain valid test data rather than false UI failures.
if rg -n --glob '*.swift' '[\p{Han}]' \
  "${ROOT}/Scholium/App" \
  "${ROOT}/Scholium/Features" \
  "${ROOT}/Scholium/Models" \
  "${ROOT}/Scholium/Services" \
  "${ROOT}/Scholium/Views" \
  "${ROOT}/ScholiumCore"; then
  echo "English-only UI guard failed: production Swift sources contain CJK text." >&2
  exit 1
fi

# Agent collaboration has one fixed MCP surface. Legacy in-App lifecycle,
# portable result, discussion, and local bridge owners must not return.
LEGACY_AGENT_ROOTS=(
  "${ROOT}/Scholium"
  "${ROOT}/ScholiumCLI"
  "${ROOT}/ScholiumApplication"
  "${ROOT}/ScholiumContracts"
  "${ROOT}/ScholiumCore"
)
if rg -n --glob '*.swift' \
  '\b(ResearchAction[A-Za-z0-9_]*|PortableResearchRecord[A-Za-z0-9_]*|ResearchAgentSession[A-Za-z0-9_]*|ResearchDiscussion[A-Za-z0-9_]*|LocalAgentBridge[A-Za-z0-9_]*|ResearchRecordBrowser[A-Za-z0-9_]*|ResearchRecordsWindow[A-Za-z0-9_]*)\b' \
  "${LEGACY_AGENT_ROOTS[@]}"; then
  echo "Agent collaboration clean-cutover guard failed: a retired production owner returned." >&2
  exit 1
fi

for retired_path in \
  "${ROOT}/ScholiumResearchRecordsFeature" \
  "${ROOT}/Scholium/Features/ResearchActions" \
  "${ROOT}/Scholium/Views/ResearchActions" \
  "${ROOT}/Scholium/Views/ResearchRecord" \
  "${ROOT}/ScholiumCore/Resources/Skills/Scholium Method Skills"; do
  if [[ -d "${retired_path}" ]] \
    && [[ -n "$(find "${retired_path}" -type f -print -quit)" ]]; then
    echo "Agent collaboration clean-cutover guard failed: retired path remains: ${retired_path}" >&2
    exit 1
  fi
done

if rg -n --glob '*.swift' --glob '*.sh' \
  'scholium[[:space:]]+(agent|research|skills|workflow)|agent[[:space:]]+(connect|start|resume|complete)|research-records/v1' \
  "${LEGACY_AGENT_ROOTS[@]}" \
  "${ROOT}/Tools/Scripts/package-app.sh"; then
  echo "Agent collaboration CLI/storage guard failed: a retired route or path returned." >&2
  exit 1
fi

# The current server surface is closed and has exactly ten tool identities.
if [[ "$(rg -c 'case [A-Za-z]+ = "scholium_' "${ROOT}/ScholiumContracts/ScholiumMCPContracts.swift")" != "10" ]]; then
  echo "MCP surface guard failed: expected exactly ten Scholium tool identities." >&2
  exit 1
fi

# Note and Folder deletion has one clean system-Trash route. Prevent the
# retired Set Aside/internal-Trash lifecycle, commands, contracts, and routed
# specification name from becoming reachable again.
if rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  --glob '!Scholium/Resources/Editor/**' \
  --glob '!Tools/Scripts/verify.sh' \
  'Set Aside|Put Back|internal Trash|set-aside|put-back|trash-list|trash-restore|NoteLifecycle|FolderLifecycle|WorkspaceDocumentLifecycle|PermanentDeletionContracts|NotePermanentDeletionCoordinator|02-notes-and-lifecycle' \
  "${ROOT}/Scholium" \
  "${ROOT}/ScholiumApplication" \
  "${ROOT}/ScholiumContracts" \
  "${ROOT}/ScholiumCore" \
  "${ROOT}/ScholiumCLI" \
  "${ROOT}/Docs" \
  "${ROOT}/Tests" \
  "${ROOT}/UITests" \
  "${ROOT}/README.md"; then
  echo "System Trash clean-cutover guard failed: retired file-lifecycle residue remains." >&2
  exit 1
fi

# Delivery targets compile only against Contracts plus Application composition.
# Core is internal and cannot be imported by App, CLI, or their boundary tests.
DELIVERY_ROOTS=("${ROOT}/Scholium" "${ROOT}/ScholiumCLI")
if rg -n --glob '*.swift' \
  '\b(FileManager|URLSession|SQLite|FSEvent|AppKit|SwiftUI|Combine|UserDefaults|NSWorkspace|NSOpenPanel)\b' \
  "${ROOT}/ScholiumContracts"; then
  echo "Contracts purity guard failed: ScholiumContracts contains I/O, UI, or mutable delivery state." >&2
  exit 1
fi

if rg -n --glob '*.swift' '^import ScholiumCore$' \
  "${DELIVERY_ROOTS[@]}" \
  "${ROOT}/Tests/ScholiumAppTests" \
  "${ROOT}/Tests/ScholiumApplicationTests"; then
  echo "Compiler boundary guard failed: a delivery source imports ScholiumCore." >&2
  exit 1
fi

# Skill YAML parsing and package-ID routing are backend authorities. Delivery
# targets may request draft inspection through Application but must never call
# the parser or catalog YAML loader directly.
if rg -n --glob '*.swift' \
  '\bResearchSkillInspector\b|\bResearchSkillCatalog[[:space:]]*\.[[:space:]]*parse[[:space:]]*\(' \
  "${DELIVERY_ROOTS[@]}"; then
  echo "Skill authority guard failed: a delivery target parses Skill YAML directly." >&2
  exit 1
fi

# The document leaf receives narrow values and closures, never a complete
# window or Research feature root.
if rg -n '\b(ResearchController|WindowModel)\b' \
  "${ROOT}/Scholium/Views/Note/NoteContentView.swift"; then
  echo "Document ownership guard failed: NoteContentView received a window or Research feature root." >&2
  exit 1
fi

APPLICATION_IMPORTS=$(rg -l --glob '*.swift' '^import ScholiumApplication$' \
  "${DELIVERY_ROOTS[@]}" || true)
while IFS= read -r file; do
  [[ -z "${file}" ]] && continue
  case "${file}" in
    "${ROOT}/Scholium/App/ScholiumApp.swift"|\
    "${ROOT}/Scholium/App/ApplicationBootstrapController.swift"|\
    "${ROOT}/Scholium/App/Window/WindowWorkspaceController.swift"|\
    "${ROOT}/Scholium/Services/MCPAppBridgeRequestRouter.swift"|\
    "${ROOT}/Scholium/Services/ScholiumAppBridgeRequestRouter.swift"|\
    "${ROOT}/Scholium/Services/WindowSession.swift"|\
    "${ROOT}/Scholium/Views/AgentIntegrationSettingsView.swift"|\
    "${ROOT}/ScholiumCLI/CLIContext.swift"|\
    "${ROOT}/ScholiumCLI/MCPCommandHandler.swift") ;;
    *)
      echo "Compiler boundary guard failed: ScholiumApplication import outside a composition root: ${file}" >&2
      exit 1
      ;;
  esac
done <<< "${APPLICATION_IMPORTS}"

if rg -n --glob '*.swift' '\b(URLSession|SQLiteSearchIndex|FSEventStreamCreate)\b' \
  "${DELIVERY_ROOTS[@]}"; then
  echo "I/O wall guard failed: a delivery target owns network, SQLite, or watcher I/O." >&2
  exit 1
fi

if rg -n --glob '*.swift' \
  --glob '!**/Services/WindowSession.swift' \
  --glob '!**/Services/PerformanceProbe.swift' \
  --glob '!**/Localization/WebKitInterfaceLocalization.swift' \
  --glob '!**/Views/Note/MarkdownEditorWebView.swift' \
  --glob '!**/Views/Note/ScholiumDocumentWebResources.swift' \
  --glob '!**/Styling/ScholiumWebFonts.swift' \
  --glob '!**/Styling/ScholiumWebFontResources.swift' \
  --glob '!**/Styling/ScholiumCalloutStyles.swift' \
  --glob '!**/Styling/ScholiumTableStyles.swift' \
  --glob '!**/Styling/ScholiumFootnoteStyles.swift' \
  --glob '!**/Styling/ScholiumMathAssets.swift' \
  --glob '!**/Styling/ScholiumMermaidAssets.swift' \
  --glob '!**/Styling/ScholiumPreviewStyles.swift' \
  '\bFileManager\b|Data\(contentsOf:|String\(contentsOf:' \
  "${ROOT}/Scholium"; then
  echo "I/O wall guard failed: frontend filesystem I/O is outside its delivery allowlist." >&2
  exit 1
fi

if rg -n --glob '*.swift' '\b(VaultService|SearchEngine|VaultRepository|WorkspaceRegistry|TriptychControlStore|ResearchSkillStore|DialogueStore|CritiqueRegistry|TriptychMutationRecoveryStore|NoteIdentityRecoveryCoordinator|TriptychMoveCoordinator|NoteSystemTrashDeletionCoordinator)[[:space:]]*\(' \
  "${DELIVERY_ROOTS[@]}"; then
  echo "Application ownership guard failed: a delivery target constructs an Application-owned authority." >&2
  exit 1
fi

# SQLite indexes use a factory rather than an initializer, so guard that
# construction spelling separately.
if rg -n --glob '*.swift' '\bSQLiteSearchIndex[[:space:]]*\.[[:space:]]*openRecovering[[:space:]]*\(' \
  "${DELIVERY_ROOTS[@]}"; then
  echo "Application ownership guard failed: a delivery target opens a SQLite index." >&2
  exit 1
fi

if rg -n --glob '*.swift' '\bFSEventStreamCreate[[:space:]]*\(' \
  "${DELIVERY_ROOTS[@]}"; then
  echo "Application ownership guard failed: a delivery target constructs a vault watcher." >&2
  exit 1
fi

# Graph construction and publication belong behind ScholiumApplication. App
# and CLI consume immutable snapshots and must not rebuild a competing graph.
if rg -n --glob '*.swift' 'LinkGraphBuilder\.(build|resolve)' \
  "${DELIVERY_ROOTS[@]}"; then
  echo "Application ownership guard failed: a delivery target constructs or resolves a graph." >&2
  exit 1
fi

# CLI graph commands resolve selectors and format outputs only. Vault-qualified
# relationship membership and traversal semantics belong to Application.
if rg -n --glob '*.swift' \
  '\bGraphSnapshot\b|\btracePaths[[:space:]]*\(|\brelationshipTracePaths[[:space:]]*\(|subjectNote[[:space:]]*==[[:space:]]*nil' \
  "${ROOT}/ScholiumCLI"; then
  echo "Application ownership guard failed: the CLI owns Graph query semantics." >&2
  exit 1
fi

# Executable syntax and rendered help derive from one command specification
# registry; parallel rule/help dictionaries can drift silently.
if rg -n --glob '*.swift' \
  '\b(commandRules|commandHelp)[[:space:]]*[:=]' \
  "${ROOT}/ScholiumCLI"; then
  echo "CLI command registry guard failed: a parallel rule or help registry returned." >&2
  exit 1
fi
if rg -n --glob '*.swift' --glob '!CLICommandCatalog.swift' \
  '"Usage: scholium' "${ROOT}/ScholiumCLI"; then
  echo "CLI command registry guard failed: a handler restates registered usage." >&2
  exit 1
fi

# Zotero request handling is composed by ScholiumApplication; the CLI owns
# only argument parsing, MCP framing, and output formatting.
if rg -n --glob '*.swift' '\b(ZoteroMCPServer|ZoteroMCPTransportLocator)[[:space:]]*[.(]' \
  "${ROOT}/ScholiumCLI"; then
  echo "Application ownership guard failed: the CLI constructs a Zotero authority." >&2
  exit 1
fi

# The complete per-window model belongs only at the SwiftUI composition root.
# Feature roots receive their controller plus narrow immutable/action contexts;
# descendants must not reacquire the window through the environment.
if rg -n --glob '*.swift' --glob '!ContentView.swift' '\bWindowModel\b' \
  "${ROOT}/Scholium/Views"; then
  echo "Window ownership guard failed: a descendant view references WindowModel." >&2
  exit 1
fi

# App views consume Core/Application documents and YAML values directly. A
# second mutable Note or frontmatter value model would recreate a competing
# source authority.
if rg -n --glob '*.swift' '\b(struct[[:space:]]+Note|enum[[:space:]]+FrontmatterValue)\b' \
  "${ROOT}/Scholium"; then
  echo "Source projection guard failed: the App declares a mutable Note or YAML authority." >&2
  exit 1
fi

for shell_script in \
  "${ROOT}/Tools/Scripts/build-qa-app.sh" \
  "${ROOT}/Tools/Scripts/install-cli.sh" \
  "${ROOT}/Tools/Scripts/inspect-window-size.sh" \
  "${ROOT}/Tools/Scripts/manage-development-storage.sh" \
  "${ROOT}/Tools/Scripts/package-app.sh" \
  "${ROOT}/Tools/Scripts/run-debug-app.sh" \
  "${ROOT}/Tools/Scripts/run-editor-toolchain.sh" \
  "${ROOT}/Tools/Scripts/run-performance-benchmarks.sh" \
  "${ROOT}/Tools/Scripts/run-ui-tests.sh" \
  "${ROOT}/Tools/Scripts/sync-interface-localization.sh" \
  "${ROOT}/Tools/Scripts/validate-interface-localization.sh" \
  "${ROOT}/Tools/Scripts/verify-qa-upgrade-safety.sh"; do
  zsh -n "${shell_script}"
done
zsh -n "${ROOT}/Manage Scholium Development Storage.command"
PYTHONPYCACHEPREFIX="${SCRATCH}-pycache" python3 -m py_compile \
  "${ROOT}/Tools/Scripts/generate-rdf1.py" \
  "${ROOT}/Tools/Scripts/capture-performance-environment.py" \
  "${ROOT}/Tools/Scripts/summarize-performance-results.py" \
  "${ROOT}/Tools/Scripts/sample-app-process-memory.py" \
  "${ROOT}/Tools/Scripts/validate-entitlements.py" \
  "${ROOT}/Tools/Scripts/qa-upgrade-manifest.py"
python3 "${ROOT}/Tools/Scripts/validate-entitlements.py" --self-test
python3 "${ROOT}/Tools/Scripts/qa-upgrade-manifest.py" self-test
python3 "${ROOT}/Tools/Scripts/sample-app-process-memory.py" --self-test
python3 "${ROOT}/Tools/Scripts/summarize-performance-results.py" --self-test
"${ROOT}/Tools/Scripts/verify-editor-bundle.sh"
"${ROOT}/Tools/Scripts/verify-rdf1-fixture.sh"
# Xcode beta's Swift Testing helper can crash while multiple test products
# tear down their event graphs (and AppKit/WebKit resources) in one invocation.
# Run the complete product set serially; no suite or test is excluded.
report_swift_test_success() {
  local label="$1"
  local log="$2"
  local summary
  summary="$(rg -o 'Test run with .* passed after [0-9.]+ seconds\.' "${log}" | tail -n 1 || true)"
  if [[ -n "${summary}" ]]; then
    print "${label}: ${summary}"
  else
    print "${label}: passed"
  fi

  if rg -q 'SEARCH_V6_PERFORMANCE_REPORT' "${log}"; then
    rg 'SEARCH_V6_PERFORMANCE_REPORT|"(cold_rebuild_ms|warm_query_p95_ms|incremental_publication_p95_ms|database_bytes|process_peak_rss_bytes)"' \
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
  local log="${SCRATCH}/${log_name}.log"
  local command_status

  mkdir -p "${SCRATCH}"
  set +e
  swift test \
    --package-path "${ROOT}" \
    --scratch-path "${SCRATCH}" \
    "$@" > "${log}" 2>&1
  command_status=$?
  set -e
  if (( command_status == 0 )); then
    report_swift_test_success "${label}" "${log}"
    return 0
  fi
  report_swift_test_failure "${label}" "${log}"
  return "${command_status}"
}

run_swift_test_product() {
  local test_product="$1"
  local attempt log command_status
  local -a parallelism_arguments selection_arguments
  parallelism_arguments=()
  selection_arguments=(--filter "${test_product}")
  if [[ "${test_product}" == "ScholiumCoreTests" ]]; then
    # Runtime microbenchmarks need a quiet process boundary. Running them
    # beside graph, index, and filesystem stress suites measures scheduler
    # contention instead of the declared workload. They run immediately after
    # the complete nonperformance Core set, with the same build and thresholds.
    selection_arguments+=(--skip 'PerformanceRegressionMicrobenchmarkTests')
  fi
  if [[ "${test_product}" == "ScholiumAppTests" ]]; then
    # This target owns AppKit windows and WebKit processes. Make Swift
    # Testing's in-process execution order explicit at that shared boundary.
    parallelism_arguments=(--no-parallel)
  fi
  if [[ "${test_product}" == "ScholiumApplicationTests" ]]; then
    # The canonical RDF-1 refresh measurement needs its own quiet process
    # boundary so graph/Search timings are not scheduler-contention artifacts.
    selection_arguments+=(--skip 'ArchitectureStabilityMeasurementTests')
  fi
  mkdir -p "${SCRATCH}"
  for attempt in 1 2 3; do
    log="${SCRATCH}/${test_product}-attempt-${attempt}.log"
    set +e
    swift test \
      --package-path "${ROOT}" \
      --scratch-path "${SCRATCH}" \
      "${parallelism_arguments[@]}" \
      "${selection_arguments[@]}" > "${log}" 2>&1
    command_status=$?
    set -e
    if (( command_status == 0 )); then
      report_swift_test_success "${test_product}" "${log}"
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

for test_product in \
  ScholiumCoreTests \
  ScholiumContractsTests \
  ScholiumApplicationTests \
  ScholiumAppTests; do
  run_swift_test_product "${test_product}"
  if [[ "${test_product}" == "ScholiumCoreTests" ]]; then
    run_swift_test_once \
      "ScholiumCoreTests performance" \
      "ScholiumCoreTests-performance" \
      --no-parallel \
      --filter 'ScholiumCoreTests.PerformanceRegressionMicrobenchmarkTests'
  elif [[ "${test_product}" == "ScholiumApplicationTests" ]]; then
    run_swift_test_once \
      "ScholiumApplicationTests architecture measurement" \
      "ScholiumApplicationTests-architecture" \
      --no-parallel \
      --filter 'ScholiumApplicationTests.ArchitectureStabilityMeasurementTests'
  fi
done

# Public Application signatures must be expressible entirely in Contracts and
# Foundation. A leaked Core nominal would defeat the package dependency wall.
swift package --package-path "${ROOT}" --scratch-path "${SCRATCH}" \
  dump-symbol-graph --minimum-access-level public
if rg -n 'ScholiumCore' \
  "${SCRATCH}/out/symbolgraph/ScholiumApplication.symbols.json"; then
  echo "Symbol graph guard failed: ScholiumApplication exposes a ScholiumCore type." >&2
  exit 1
fi

mkdir -p "${RELEASE_SCRATCH}"
release_log="${RELEASE_SCRATCH}/release-build.log"
set +e
swift build --package-path "${ROOT}" -c release \
  --scratch-path "${RELEASE_SCRATCH}" > "${release_log}" 2>&1
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
