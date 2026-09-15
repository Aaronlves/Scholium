#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
export DEVELOPER_DIR="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
SWIFT="$(xcrun --find swift)"
HOST_LIBRARIES="${SWIFT:h:h}/lib/swift/host"
MODULE_CACHE="${ROOT}/.build/contracts-purity/module-cache"
mkdir -p "${MODULE_CACHE}"
# Use the parser shipped with the selected compiler; no package dependency or
# independently versioned lexer is needed for this repository-only guard.
exec "${SWIFT}" -module-cache-path "${MODULE_CACHE}" \
  -I "${HOST_LIBRARIES}" -L "${HOST_LIBRARIES}" \
  -Xlinker -rpath -Xlinker "${HOST_LIBRARIES}" \
  "${ROOT}/Tools/Scripts/validate-contracts-purity.swift" \
  "${1:-${ROOT}/ScholiumContracts}"
