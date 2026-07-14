#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
PREFIX="${SCHOLIUM_CLI_PREFIX:-${HOME}/.local}"
SCRATCH="${TMPDIR:-/tmp}/scholium-cli-release"

swift build --package-path "${ROOT}" -c release --product scholium --scratch-path "${SCRATCH}"
mkdir -p "${PREFIX}/bin"
install -m 755 "${SCRATCH}/release/scholium" "${PREFIX}/bin/scholium"

echo "Installed: ${PREFIX}/bin/scholium"
echo "Add ${PREFIX}/bin to PATH if it is not already present."
