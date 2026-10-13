#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEMP_ROOT="${SCHOLIUM_VERIFY_RUN_ROOT:-${ROOT}/.build/rdf1-verification-$$}"
FIRST="${TEMP_ROOT}/rdf1-a"
SECOND="${TEMP_ROOT}/rdf1-b"

cleanup() {
  rm -rf "${FIRST}" "${SECOND}"
}
trap cleanup EXIT

python3 "${ROOT}/Tools/Scripts/generate-rdf1.py" --output "${FIRST}"
python3 "${ROOT}/Tools/Scripts/generate-rdf1.py" --output "${FIRST}" --verify
mkdir -p "${FIRST}/.scholium/researcher-owned"
cp "${ROOT}/LICENSE" \
  "${FIRST}/.scholium/researcher-owned/custom-control.md"
python3 "${ROOT}/Tools/Scripts/generate-rdf1.py" --output "${FIRST}" --verify
python3 "${ROOT}/Tools/Scripts/generate-rdf1.py" --output "${SECOND}"
cmp "${FIRST}/manifest.json" "${SECOND}/manifest.json"

print "RDF-1 generation is deterministic; portable control Markdown does not alter its Note inventory."
