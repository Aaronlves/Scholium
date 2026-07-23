#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
FIRST="${ROOT}/.build/rdf1-verification-a"
SECOND="${ROOT}/.build/rdf1-verification-b"

cleanup() {
  rm -rf "${FIRST}" "${SECOND}"
}
trap cleanup EXIT

python3 "${ROOT}/Tools/Scripts/generate-rdf1.py" --output "${FIRST}"
python3 "${ROOT}/Tools/Scripts/generate-rdf1.py" --output "${FIRST}" --verify
python3 "${ROOT}/Tools/Scripts/generate-rdf1.py" --output "${SECOND}"
cmp "${FIRST}/manifest.json" "${SECOND}/manifest.json"

print "RDF-1 generation is deterministic and its manifest verifies."
