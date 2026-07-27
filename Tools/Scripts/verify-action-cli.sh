#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")}"
export DEVELOPER_DIR
SCRATCH="${2:-${ROOT}/.build/action-cli-verification}"

if (( $# >= 1 )); then
  BINARY="$1"
else
  swift build \
    --package-path "${ROOT}" \
    --scratch-path "${SCRATCH}" \
    --product scholium
  BINARY="$(swift build \
    --package-path "${ROOT}" \
    --scratch-path "${SCRATCH}" \
    --show-bin-path)/scholium"
fi

if [[ ! -x "${BINARY}" ]]; then
  print -u2 "Action CLI verifier cannot execute ${BINARY}."
  exit 1
fi

SCHOLIUM_ACTION_CLI_BINARY="${BINARY}" \
swift test \
  --package-path "${ROOT}" \
  --scratch-path "${SCRATCH}" \
  --filter ActionCLIExecutableLifecycleTests

print "Research CLI: Action and Recommended Bibliography executable lifecycles verified"
