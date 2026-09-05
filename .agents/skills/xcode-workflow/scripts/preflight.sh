#!/bin/zsh
set -euo pipefail

candidate="${1:-${DEVELOPER_DIR:-}}"
selection_source="argument"

if [[ -z "${candidate}" ]]; then
  candidate="$(xcode-select -p 2>/dev/null || true)"
  selection_source="xcode-select"
elif (( $# == 0 )); then
  selection_source="DEVELOPER_DIR"
fi

if [[ -d "${candidate}/Contents/Developer" ]]; then
  candidate="${candidate}/Contents/Developer"
fi

if [[ -z "${candidate}" || ! -d "${candidate}" ]]; then
  print -u2 "The requested Xcode developer directory is unavailable: ${candidate:-<empty>}"
  print -u2 "Installed Xcode candidates:"
  find /Applications "${HOME}/Applications" "${HOME}/Downloads" \
    -maxdepth 3 -type d -name 'Xcode*.app' -print 2>/dev/null | sort -u >&2 || true
  exit 66
fi

developer_dir="$(cd "${candidate}" && pwd -P)"
shell_selected="$(xcode-select -p 2>/dev/null || true)"
xcode_version="$(DEVELOPER_DIR="${developer_dir}" xcodebuild -version | paste -sd ';' -)"
swift_version="$(DEVELOPER_DIR="${developer_dir}" xcrun swift --version 2>&1 | paste -sd ';' -)"
sdk_version="$(DEVELOPER_DIR="${developer_dir}" xcrun --sdk macosx --show-sdk-version)"
xcodebuild_path="$(DEVELOPER_DIR="${developer_dir}" xcrun --find xcodebuild)"
mcpbridge_path="$(DEVELOPER_DIR="${developer_dir}" xcrun --find mcpbridge)"
host_version="$(sw_vers -productVersion) ($(sw_vers -buildVersion))"

mcp_configured="unknown"
if command -v codex >/dev/null 2>&1; then
  if codex mcp list 2>/dev/null | awk '$1 == "xcode" { found = 1 } END { exit !found }'; then
    mcp_configured="yes"
  else
    mcp_configured="no"
  fi
fi

print "selection_source=${selection_source}"
print "developer_dir=${developer_dir}"
print "xcode=${xcode_version}"
print "swift=${swift_version}"
print "macos_sdk=${sdk_version}"
print "host_macos=${host_version}"
print "xcodebuild=${xcodebuild_path}"
print "mcpbridge=${mcpbridge_path}"
print "shell_selected=${shell_selected}"
print "xcode_mcp_configured=${mcp_configured}"
