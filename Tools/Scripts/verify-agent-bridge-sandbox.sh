#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
XCODE="$(${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh)"
SCRATCH="${ROOT}/.build/agent-bridge-sandbox"
BUILD="${SCHOLIUM_AGENT_BRIDGE_BUILD:-${SCRATCH}/build}"
APP="${SCRATCH}/Scholium-Agent-Bridge-Probe.app"
RUN_ID="$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-8)"
BUNDLE_ID="com.scholium.abp.r${RUN_ID}"
CONTAINER="${HOME}/Library/Containers/${BUNDLE_ID}"
PROBE_HOME="${CONTAINER}/Data/h"
SUPPORT="${PROBE_HOME}/ApplicationSupport"
SOCKET="${SUPPORT}/b/s"
MARKER="${CONTAINER}/Data/.scholium-agent-bridge-probe"
APP_PID=""

cleanup() {
  if [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" 2>/dev/null; then
    kill "${APP_PID}" 2>/dev/null || true
    wait "${APP_PID}" 2>/dev/null || true
  fi
  if [[ "${SCRATCH}" == "${ROOT}/.build/agent-bridge-sandbox" ]]; then
    rm -rf "${SCRATCH}"
  fi
  if [[ "${CONTAINER}" == "${HOME}/Library/Containers/com.scholium.abp.r${RUN_ID}" ]] \
    && [[ -f "${MARKER}" ]] \
    && [[ "$(< "${MARKER}")" == "${RUN_ID}" ]]; then
    # Delete only this unique, marker-proved probe container. macOS may retain
    # its own empty container identity marker after the run.
    rm -rf "${CONTAINER}/Data"
    rm -rf "${CONTAINER}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ -e "${CONTAINER}" ]]; then
  print -u2 "The unique Agent bridge probe container unexpectedly exists."
  exit 65
fi
rm -rf "${SCRATCH}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Helpers" \
  "${APP}/Contents/Resources" "${PROBE_HOME}"
print -r -- "${RUN_ID}" > "${MARKER}"

if [[ ! -x "${BUILD}/debug/ScholiumApp" || ! -x "${BUILD}/debug/scholium" ]]; then
  DEVELOPER_DIR="${XCODE}" swift build \
    --package-path "${ROOT}" \
    --scratch-path "${BUILD}" \
    --configuration debug \
    --product ScholiumApp
  DEVELOPER_DIR="${XCODE}" swift build \
    --package-path "${ROOT}" \
    --scratch-path "${BUILD}" \
    --configuration debug \
    --product scholium
fi

cp "${BUILD}/debug/ScholiumApp" "${APP}/Contents/MacOS/Scholium"
cp "${BUILD}/debug/scholium" "${APP}/Contents/Helpers/scholium"
chmod +x "${APP}/Contents/MacOS/Scholium" "${APP}/Contents/Helpers/scholium"
cp -R "${BUILD}/debug/Scholium_ScholiumApp.bundle" "${APP}/Contents/Resources/"
cp -R "${BUILD}/debug/Scholium_ScholiumCore.bundle" "${APP}/Contents/Resources/"
cp "${ROOT}/Tools/Packaging/Info.plist" "${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" \
  -c "Set :CFBundleName Scholium Agent Bridge Probe" \
  "${APP}/Contents/Info.plist"

xattr -cr "${APP}"
codesign --force --options runtime \
  --entitlements "${ROOT}/Tools/Packaging/ScholiumCLI.entitlements" \
  --sign - "${APP}/Contents/Helpers/scholium"
codesign --force --options runtime \
  --entitlements "${ROOT}/Tools/Packaging/Scholium.entitlements" \
  --sign - "${APP}"
codesign --verify --deep --strict "${APP}"

APP_ENTITLEMENTS="${SCRATCH}/app-entitlements.plist"
CLI_ENTITLEMENTS="${SCRATCH}/cli-entitlements.plist"
codesign -d --entitlements :- "${APP}" > "${APP_ENTITLEMENTS}" 2>/dev/null
codesign -d --entitlements :- \
  "${APP}/Contents/Helpers/scholium" > "${CLI_ENTITLEMENTS}" 2>/dev/null || true
rg -q 'com\.apple\.security\.app-sandbox' "${APP_ENTITLEMENTS}"
if rg -q 'com\.apple\.security\.app-sandbox' "${CLI_ENTITLEMENTS}"; then
  print -u2 "The probe CLI unexpectedly inherited the App Sandbox."
  exit 65
fi
rg -q 'group\.com\.scholium\.app' "${APP_ENTITLEMENTS}"
rg -q 'group\.com\.scholium\.app' "${CLI_ENTITLEMENTS}"

RUN_LOCATOR="sandbox-agent-bridge-probe"
PAIRING_CODE="ABCD-EFGH-JKLM-NPQR-STUV-WXYZ"

BEFORE="$(print -r -- "${PAIRING_CODE}" | \
  SCHOLIUM_AGENT_BRIDGE_CONTAINER="${SUPPORT}" \
  "${APP}/Contents/Helpers/scholium" agent pair --run "${RUN_LOCATOR}" \
  2>&1 || true)"
print -r -- "${BEFORE}" | rg -qi 'unavailable'

SCHOLIUM_HOME="${PROBE_HOME}" \
SCHOLIUM_AGENT_BRIDGE_CONTAINER="${SUPPORT}" \
  "${APP}/Contents/MacOS/Scholium" \
  > "${SCRATCH}/app.stdout" 2> "${SCRATCH}/app.stderr" &
APP_PID=$!

for _ in {1..100}; do
  [[ -S "${SOCKET}" ]] && break
  kill -0 "${APP_PID}" 2>/dev/null || {
    print -u2 "The sandboxed probe App exited before opening its bridge."
    sed -n '1,120p' "${SCRATCH}/app.stderr" >&2
    exit 1
  }
  sleep 0.1
done
[[ -S "${SOCKET}" ]] || {
  print -u2 "The sandboxed probe App did not create its AF_UNIX socket."
  sed -n '1,120p' "${SCRATCH}/app.stderr" >&2
  exit 1
}
[[ "$(stat -f '%Lp' "${SUPPORT}/b")" == "700" ]]
[[ "$(stat -f '%Lp' "${SOCKET}")" == "600" ]]

AFTER="$(print -r -- "${PAIRING_CODE}" | \
  SCHOLIUM_AGENT_BRIDGE_CONTAINER="${SUPPORT}" \
  "${APP}/Contents/Helpers/scholium" agent pair --run "${RUN_LOCATOR}" \
  2>&1 || true)"
print -r -- "${AFTER}" | rg -qi 'bridge request was not authorized'
if print -r -- "${AFTER}" | rg -qi 'unavailable'; then
  print -u2 "The unpackaged CLI could not reach the sandboxed App bridge."
  exit 1
fi
if rg -Fq "${PAIRING_CODE}" \
  "${SCRATCH}/app.stdout" "${SCRATCH}/app.stderr"; then
  print -u2 "The sandboxed App logged the raw Pairing Code."
  exit 1
fi

kill "${APP_PID}"
wait "${APP_PID}" || true
APP_PID=""

print "Sandboxed AF_UNIX bridge probe passed."
print "App sandbox: enabled; bundled CLI sandbox: disabled."
print "Directory mode: 0700; socket mode: 0600; closed-App path: typed unavailable."
print "An invalid but well-formed Pairing Code reached the App, received the generic authorization denial, and was not logged."
print "Scope: DEBUG development-protocol evidence only. The ad-hoc Beta distribution"
print "compiles with SCHOLIUM_ADHOC_DISTRIBUTION and disables the direct Agent bridge;"
print "this probe does not validate that release channel."
