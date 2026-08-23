#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")}"
export DEVELOPER_DIR
SCRATCH="${2:-${ROOT}/.build/action-cli-verification}"
mkdir -p "${SCRATCH}"

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

VERIFIER_DIRECTORY="$(mktemp -d "${SCRATCH}/signed-action-cli.XXXXXX")"
trap 'rm -rf "${VERIFIER_DIRECTORY}"' EXIT
VERIFIER_BINARY="${VERIFIER_DIRECTORY}/scholium"
BOOKMARK_HELPER="${VERIFIER_DIRECTORY}/bookmark-binder"
CORE_RESOURCES="${BINARY:h}/Scholium_ScholiumCore.bundle"
if [[ ! -d "${CORE_RESOURCES}" ]]; then
  print -u2 "Action CLI verifier cannot find ${CORE_RESOURCES}."
  exit 1
fi
cp "${BINARY}" "${VERIFIER_BINARY}"
ditto "${CORE_RESOURCES}" "${VERIFIER_DIRECTORY}/Scholium_ScholiumCore.bundle"
xcrun swiftc \
  "${ROOT}/Tools/Fixtures/ScholiumActionCLIBookmarkBinder.swift" \
  -o "${BOOKMARK_HELPER}"
VERIFIER_IDENTITY="com.scholium.action-cli-verifier"
codesign --force --sign - --identifier "${VERIFIER_IDENTITY}" "${BOOKMARK_HELPER}"
codesign --force --sign - --identifier "${VERIFIER_IDENTITY}" "${VERIFIER_BINARY}"

SCHOLIUM_ACTION_CLI_BINARY="${VERIFIER_BINARY}" \
SCHOLIUM_ACTION_CLI_BOOKMARK_HELPER="${BOOKMARK_HELPER}" \
swift test \
  --package-path "${ROOT}" \
  --scratch-path "${SCRATCH}" \
  --filter ActionCLIExecutableLifecycleTests

print "Research CLI: Research Action executable lifecycles verified"
