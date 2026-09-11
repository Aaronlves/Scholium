#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
SCRIPT_NAME="${0:t}"
SWIFT_FORMAT_CONFIG="${ROOT}/Tools/Config/swift-format.json"
run_swift=true
run_editor=true
fix=false
typeset -a swift_targets

usage() {
  print -r -- "Usage: ${SCRIPT_NAME} [--fix] [--swift-only|--editor-only] [swift-file-or-directory ...]"
  print -r -- ""
  print -r -- "Checks Swift formatting rules and WebEditor TypeScript types."
  print -r -- "--fix          Format Swift targets in place before linting."
  print -r -- "--swift-only   Skip the WebEditor typecheck."
  print -r -- "--editor-only  Skip Swift lint."
  print -r -- "Paths          Limit Swift lint to the supplied files/directories."
  exit 64
}

while (( $# > 0 )); do
  case "$1" in
    --fix)
      fix=true
      shift
      ;;
    --swift-only)
      run_editor=false
      shift
      ;;
    --editor-only)
      run_swift=false
      shift
      ;;
    --help|-h)
      usage
      ;;
    --*)
      usage
      ;;
    *)
      swift_targets+=("$1")
      shift
      ;;
  esac
done

if ! $run_swift && $fix; then
  print -u2 "--fix requires Swift lint to be enabled."
  exit 64
fi
if (( ${#swift_targets[@]} > 0 )) && $run_editor; then
  print "Swift paths supplied; skipping the full WebEditor check."
  run_editor=false
fi
if (( ${#swift_targets[@]} > 0 )) && ! $run_swift; then
  print -u2 "Swift paths cannot be supplied with --editor-only."
  exit 64
fi

if $run_swift; then
  [[ -f "$SWIFT_FORMAT_CONFIG" ]] || {
    print -u2 "Swift-format configuration is missing: $SWIFT_FORMAT_CONFIG"
    exit 66
  }

  swift_format=""
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    swift_format="$(DEVELOPER_DIR="${DEVELOPER_DIR}" xcrun --find swift-format 2>/dev/null || true)"
  fi
  if [[ -z "$swift_format" ]] && command -v swift-format >/dev/null 2>&1; then
    swift_format="$(command -v swift-format)"
  fi
  if [[ -z "$swift_format" ]]; then
    swift_format="$(xcrun --find swift-format 2>/dev/null || true)"
  fi
  [[ -n "$swift_format" && -x "$swift_format" ]] || {
    print -u2 "swift-format is unavailable. Install/select an Apple toolchain that provides it."
    exit 66
  }

  if (( ${#swift_targets[@]} == 0 )); then
    swift_targets=(
      "${ROOT}/Package.swift"
      "${ROOT}/Scholium"
      "${ROOT}/ScholiumAgentHelper"
      "${ROOT}/ScholiumApplication"
      "${ROOT}/ScholiumCLI"
      "${ROOT}/ScholiumCLIUpdate"
      "${ROOT}/ScholiumContracts"
      "${ROOT}/ScholiumCore"
      "${ROOT}/Tests"
      "${ROOT}/UITests"
    )
  fi

  if $fix; then
    "$swift_format" format \
      --in-place \
      --recursive \
      --parallel \
      --no-color-diagnostics \
      --configuration "$SWIFT_FORMAT_CONFIG" \
      "${swift_targets[@]}"
  fi

  "$swift_format" lint \
    --strict \
    --recursive \
    --parallel \
    --no-color-diagnostics \
    --configuration "$SWIFT_FORMAT_CONFIG" \
    "${swift_targets[@]}"
  print "Swift lint: passed"
fi

if $run_editor; then
  "${ROOT}/Tools/Scripts/run-editor-toolchain.sh" --check-only
fi
