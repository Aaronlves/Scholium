#!/bin/zsh
set -euo pipefail

# macOS cannot enable XCTest AutomationMode while the console is locked.
# Keep every UI-driven harness on one fail-fast host-state contract so a
# machine condition cannot be mistaken for an application regression.
locked_state="$(ioreg -n Root -d 1 -a 2>/dev/null \
  | plutil -extract 'IOConsoleUsers.0.CGSSessionScreenIsLocked' raw -o - - 2>/dev/null \
  || true)"

if [[ "${locked_state}" == "true" ]]; then
  print -u2 "Scholium UI automation requires an unlocked macOS console. Unlock the Mac, then rerun this command."
  exit 78
fi
