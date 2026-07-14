#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
SCRATCH="${TMPDIR:-/tmp}/scholium-verification"
rm -rf "${SCRATCH}"

"${ROOT}/Tools/Scripts/verify-editor-bundle.sh"
swift test --package-path "${ROOT}" --scratch-path "${SCRATCH}"
swift build --package-path "${ROOT}" -c release --scratch-path "${SCRATCH}-release"
