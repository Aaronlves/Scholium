#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
SCRATCH="${TMPDIR:-/tmp}/scholium-verification"
rm -rf "${SCRATCH}"

# The repository copy is the reviewable source of the protected Skill
# packages. SwiftPM embeds the generated mirror; release verification must
# fail if those two trees drift, including stale reference documentation.
"${ROOT}/Tools/Scripts/sync-product-skills.sh" --check

# Every protected Skill package must ship the local reference files that its
# SKILL.md names. The mirror check above catches drift between source and the
# SwiftPM bundle; this check catches a broken package before either copy is
# accepted as a valid Beta resource.
python3 - "${ROOT}/Skills" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
missing = []
packages = sorted(path.parent for path in root.rglob("SKILL.md"))
for package in packages:
    source = (package / "SKILL.md").read_text(encoding="utf-8")
    references = sorted(set(re.findall(r"references/[A-Za-z0-9._/-]+", source)))
    for reference in references:
        if not (package / reference).is_file():
            missing.append(f"{package}: {reference}")

if missing:
    print("Protected Skill reference check failed:", file=sys.stderr)
    print("\n".join(missing), file=sys.stderr)
    raise SystemExit(1)

print(f"Protected Skill references: {len(packages)} packages validated")
PY

# Scholium's current interface contract is English-only. Keep this guard
# scoped to production Swift sources so CJK research fixtures, user Markdown,
# and documentation remain valid test data rather than false UI failures.
if rg -n --glob '*.swift' '[\p{Han}]' \
  "${ROOT}/Scholium/App" \
  "${ROOT}/Scholium/Models" \
  "${ROOT}/Scholium/Services" \
  "${ROOT}/Scholium/Views" \
  "${ROOT}/ScholiumCore"; then
  echo "English-only UI guard failed: production Swift sources contain CJK text." >&2
  exit 1
fi

# The editor-only Research Strip is the one function doorway. Retired Scholia
# routing and standalone Dialogue/Critique presentations would recreate the
# duplicate surfaces that the typed function route replaced.
if rg -n --glob '*.swift' \
  '\b(showDialogue|ScholiaPanelView|ScholiaPresentationState|beginScholiaPresentation|pushScholiaDestination)\b|case[[:space:]]+scholia\b|\.[[:space:]]*scholia[[:space:]]*\(' \
  "${ROOT}/Scholium/App" \
  "${ROOT}/Scholium/Models" \
  "${ROOT}/Scholium/Services" \
  "${ROOT}/Scholium/Views"; then
  echo "Research Strip guard failed: production Swift sources contain a retired Scholia route." >&2
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

# The document leaf receives only the immutable Strip projection and action
# closure. Other adjacent inspector/history views in this source file may own
# their already-established ResearchController adapters, so inspect only the
# NoteContentView declaration rather than matching the entire file.
if sed -n \
  '/^struct NoteContentView: View/,/^private struct DocumentTabBar: View/p' \
  "${ROOT}/Scholium/Views/Note/NoteContentView.swift" \
  | rg -n '\b(ResearchController|WindowModel)\b'; then
  echo "Research Strip ownership guard failed: NoteContentView received a window or Research feature root." >&2
  exit 1
fi

APPLICATION_IMPORTS=$(rg -l --glob '*.swift' '^import ScholiumApplication$' \
  "${DELIVERY_ROOTS[@]}" || true)
while IFS= read -r file; do
  [[ -z "${file}" ]] && continue
  case "${file}" in
    "${ROOT}/Scholium/App/ScholiumApp.swift"|\
    "${ROOT}/Scholium/Services/WindowSession.swift"|\
    "${ROOT}/ScholiumCLI/CLIContext.swift") ;;
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
  --glob '!**/Views/Note/MarkdownEditorWebView.swift' \
  --glob '!**/Styling/ScholiumWebFonts.swift' \
  --glob '!**/Styling/ScholiumCalloutStyles.swift' \
  '\bFileManager\b|Data\(contentsOf:|String\(contentsOf:' \
  "${ROOT}/Scholium"; then
  echo "I/O wall guard failed: frontend filesystem I/O is outside its delivery allowlist." >&2
  exit 1
fi

if rg -n --glob '*.swift' '\b(VaultService|SearchEngine|VaultRepository|WorkspaceRegistry|VaultIdentityRegistry|PortableControlAccessRegistry|TriptychControlStore|ResearchSkillStore|HumanReviewStore|DialogueStore|CritiqueRegistry|TriptychCheckpointStore|TriptychMutationRecoveryStore|NoteIdentityRecoveryCoordinator|TriptychMoveCoordinator|NotePermanentDeletionCoordinator|UnclassifiedClassificationCoordinator)[[:space:]]*\(' \
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

zsh -n "${ROOT}/Tools/Scripts/run-performance-benchmarks.sh"
zsh -n "${ROOT}/Tools/Scripts/package-app.sh"
PYTHONPYCACHEPREFIX="${SCRATCH}-pycache" python3 -m py_compile \
  "${ROOT}/Tools/Scripts/generate-rdf1.py" \
  "${ROOT}/Tools/Scripts/capture-performance-environment.py" \
  "${ROOT}/Tools/Scripts/summarize-performance-results.py"
"${ROOT}/Tools/Scripts/verify-editor-bundle.sh"
"${ROOT}/Tools/Scripts/verify-rdf1-fixture.sh"
swift test --package-path "${ROOT}" --scratch-path "${SCRATCH}"

# Public Application signatures must be expressible entirely in Contracts and
# Foundation. A leaked Core nominal would defeat the package dependency wall.
swift package --package-path "${ROOT}" --scratch-path "${SCRATCH}" \
  dump-symbol-graph --minimum-access-level public
if rg -n 'ScholiumCore' \
  "${SCRATCH}/out/symbolgraph/ScholiumApplication.symbols.json"; then
  echo "Symbol graph guard failed: ScholiumApplication exposes a ScholiumCore type." >&2
  exit 1
fi

"${ROOT}/Tools/Scripts/verify-workflow-cli.sh" "${SCRATCH}/debug/scholium"
swift build --package-path "${ROOT}" -c release --scratch-path "${SCRATCH}-release"
