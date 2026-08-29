#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
FIXTURE_SOURCE="${ROOT}/Tools/Fixtures/research-action-quality-v1"

[[ -d "${FIXTURE_SOURCE}" ]] || {
  print -u2 "Missing Research Action quality fixture: ${FIXTURE_SOURCE}"
  exit 1
}

SCHOLIUM_TEST_VAULTS="${FIXTURE_SOURCE}" \
SCHOLIUM_QA_REQUIRE_CLEAN_RESEARCH_STATE=1 \
  zsh "${ROOT}/Tools/Scripts/build-qa-app.sh"

print "Performer case: ${FIXTURE_SOURCE}/performer-case.md"
print "Independent reviewer rubric: ${FIXTURE_SOURCE}/reviewer-rubric.md"
