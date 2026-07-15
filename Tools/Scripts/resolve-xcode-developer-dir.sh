#!/bin/zsh
set -euo pipefail

is_xcode_developer_dir() {
  [[ -n "$1" && -x "$1/usr/bin/xcodebuild" ]]
}

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  if is_xcode_developer_dir "${DEVELOPER_DIR}"; then
    print -r -- "${DEVELOPER_DIR}"
    exit 0
  fi
  print -u2 "DEVELOPER_DIR is not a complete Xcode developer directory: ${DEVELOPER_DIR}"
  exit 69
fi

selected="$(xcode-select -p 2>/dev/null || true)"
if is_xcode_developer_dir "${selected}"; then
  print -r -- "${selected}"
  exit 0
fi

for candidate in \
  /Applications/Xcode-beta.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer
do
  if is_xcode_developer_dir "${candidate}"; then
    print -r -- "${candidate}"
    exit 0
  fi
done

print -u2 "No complete Xcode developer directory is available. Set DEVELOPER_DIR explicitly."
exit 69
