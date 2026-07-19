#!/bin/zsh
set -u

ROOT="${0:A:h}"
"${ROOT}/Tools/Scripts/manage-development-storage.sh" interactive
status=$?

if (( status != 0 )); then
  print
  print -u2 "Scholium development storage manager exited with status ${status}."
  read -k 1 "?Press any key to close."
  print
fi

exit "${status}"
