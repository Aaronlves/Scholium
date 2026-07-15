#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
SOURCE="${ROOT}/.agents/skills"
PLUGIN_ROOT="${SCHOLIUM_TOOLKIT_DIR:-${HOME}/plugins/scholium-toolkit}"
DESTINATION="${PLUGIN_ROOT}/skills"

usage() {
  print -u2 "Usage: $0 --sync | --check"
  exit 64
}

[[ $# -eq 1 ]] || usage
[[ -d "${SOURCE}" ]] || { print -u2 "Missing canonical skill tree: ${SOURCE}"; exit 66; }
[[ -f "${PLUGIN_ROOT}/.codex-plugin/plugin.json" ]] || {
  print -u2 "Missing scholium-toolkit plugin manifest: ${PLUGIN_ROOT}/.codex-plugin/plugin.json"
  exit 66
}

case "$1" in
  --sync)
    mkdir -p "${DESTINATION}"
    rsync -a --delete --exclude '.DS_Store' "${SOURCE}/" "${DESTINATION}/"
    print "Synchronized ${SOURCE} -> ${DESTINATION}"
    ;;
  --check)
    if diff -qr -x '.DS_Store' "${SOURCE}" "${DESTINATION}"; then
      print "scholium-toolkit skill snapshot matches the repository source."
    else
      print -u2 "scholium-toolkit skill snapshot is stale. Run $0 --sync."
      exit 1
    fi
    ;;
  *) usage ;;
esac
