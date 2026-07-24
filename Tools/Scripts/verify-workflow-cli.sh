#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")}"
export DEVELOPER_DIR
BUILD_SCRATCH="${ROOT}/.build/workflow-cli-verification"
FIXTURE="${ROOT}/Tests/Fixtures/ResearchWorkflow/bundled-analysis.json"
AUDIT_FIXTURE="${ROOT}/Tests/Fixtures/ResearchWorkflow/audit-input.json"
SCRATCH="${ROOT}/.build/workflow-cli-run-$$"
rm -rf "${SCRATCH}"
mkdir -p "${SCRATCH}"
trap 'rm -rf "${SCRATCH}"' EXIT
export SCHOLIUM_HOME="${SCRATCH}/home"

if (( $# >= 1 )); then
  BINARY="$1"
else
  swift build \
    --package-path "${ROOT}" \
    --scratch-path "${BUILD_SCRATCH}" \
    --product scholium
  BINARY="$(swift build \
    --package-path "${ROOT}" \
    --scratch-path "${BUILD_SCRATCH}" \
    --show-bin-path)/scholium"
fi

if [[ ! -x "${BINARY}" ]]; then
  print -u2 "Workflow CLI verifier cannot execute ${BINARY}."
  exit 1
fi

"${BINARY}" workflow validate --from "${FIXTURE}" --format json \
  > "${SCRATCH}/validation.json"
"${BINARY}" workflow assemble --from - --format json \
  < "${FIXTURE}" > "${SCRATCH}/assembly.json"
"${BINARY}" workflow assemble --from "${FIXTURE}" --format markdown \
  > "${SCRATCH}/assembly.md"
"${BINARY}" workflow audit-plan --from "${AUDIT_FIXTURE}" --format json \
  > "${SCRATCH}/audit-plan.json"

python3 - "${FIXTURE}" "${SCRATCH}" <<'PY'
from pathlib import Path
import json
import sys

fixture = Path(sys.argv[1])
scratch = Path(sys.argv[2])
base = json.loads(fixture.read_text())

artifact = json.loads(json.dumps(base))
for reference in artifact["original_read_set"]:
    reference["kind"] = "note"
for phase in artifact["phases"]:
    for reference in phase["read_set"]:
        reference["kind"] = "note"
(scratch / "triptych-artifact.json").write_text(json.dumps(artifact))

local = json.loads(json.dumps(base))
local["phases"][0]["required_skills"].append("local-method")
(scratch / "local-package.json").write_text(json.dumps(local))
PY

if "${BINARY}" workflow validate --from "${SCRATCH}/triptych-artifact.json" \
  --format json > /dev/null 2> "${SCRATCH}/triptych-artifact.err"; then
  print -u2 "A Triptych artifact workflow unexpectedly assembled without --triptych."
  exit 1
fi
grep -q "Triptych artifacts" "${SCRATCH}/triptych-artifact.err"

if "${BINARY}" workflow validate --from "${SCRATCH}/local-package.json" \
  --format json > /dev/null 2> "${SCRATCH}/local-package.err"; then
  print -u2 "A local-package workflow unexpectedly assembled without --triptych."
  exit 1
fi
grep -q "local packages: local-method" "${SCRATCH}/local-package.err"

python3 - "${SCRATCH}" <<'PY'
from pathlib import Path
import json
import sys

scratch = Path(sys.argv[1])
validation = json.loads((scratch / "validation.json").read_text())
assembly = json.loads((scratch / "assembly.json").read_text())
audit = json.loads((scratch / "audit-plan.json").read_text())
markdown = (scratch / "assembly.md").read_text()

assert validation["structurally_valid"] is True
assert validation["executable"] is True
packages = {package["id"]: package for package in validation["phases"][0]["packages"]}
assert "scholium-analyze" in packages
practice = packages["scholium-philosophical-practices"]
loaded = {resource["relative_path"] for resource in practice["loaded_resources"]}
assert "references/Historical-Interpreter.md" in loaded
assert "references/Reviewer.md" not in loaded
assert assembly["is_executable"] is True
assert "# Scholium Workflow Contract" in assembly["rendered_instructions"]
assert "# Scholium Workflow Contract" in markdown
assert len(audit["scheduled"]) == 1
assert not audit["reused"]

persisted = [path for path in (scratch / "home").rglob("*") if path.is_file()]
assert not any("workflow" in path.name.lower() for path in persisted)
PY

print "Workflow CLI: file input, stdin, JSON, Markdown, audit planning, and Triptych requirements verified"
