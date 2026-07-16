#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
SOURCE="${ROOT}/Skills"
DESTINATION="${ROOT}/ScholiumCore/Resources/Skills"

usage() {
  print -u2 "Usage: $0 --sync | --check"
  exit 64
}

[[ $# -eq 1 ]] || usage
[[ -d "${SOURCE}" ]] || { print -u2 "Missing canonical product Skill tree: ${SOURCE}"; exit 66; }

case "$1" in
  --sync)
    mkdir -p "${DESTINATION}"
    rsync -a --delete --exclude '.DS_Store' "${SOURCE}/" "${DESTINATION}/"
    print "Synchronized canonical product Skills into ScholiumCore resources."
    ;;
  --check)
    if diff -qr -x '.DS_Store' "${SOURCE}" "${DESTINATION}"; then
      print "Product Skill resource snapshot matches the canonical Skills tree."
    else
      print -u2 "Product Skill resource snapshot is stale. Run $0 --sync."
      exit 1
    fi
    ;;
  *) usage ;;
esac
