#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
BINARY="${1:-${ROOT}/.build/debug/scholium}"
SCRATCH="${2:-${TMPDIR:-/tmp}/scholium-function-cli-verification}"

if [[ ! -x "${BINARY}" ]]; then
  print -u2 "Function CLI verifier cannot execute ${BINARY}."
  exit 1
fi

SCHOLIUM_FUNCTION_CLI_BINARY="${BINARY}" \
DEVELOPER_DIR="${DEVELOPER_DIR:-$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")}" \
swift test \
  --package-path "${ROOT}" \
  --scratch-path "${SCRATCH}" \
  --filter FunctionCLIExecutableLifecycleTests

print "Function CLI: executable availability, Dialogue, Revise, edit, Fidelity, completion, cancellation, and failure lifecycle verified"
