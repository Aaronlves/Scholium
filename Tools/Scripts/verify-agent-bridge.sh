#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
XCODE="$(${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh)"
SCRATCH="${ROOT}/.build/ab"
BUILD="${SCHOLIUM_AGENT_BRIDGE_BUILD:-${SCRATCH}/build}"
APP="${SCRATCH}/Scholium-Agent-Bridge-Probe.app"
RUN_ID="$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-8)"
BUNDLE_ID="com.scholium.abp.r${RUN_ID}"
PROBE_ROOT="${HOME}/Library/Application Support/Scholium/Bridge-Probes/${RUN_ID}"
PROBE_HOME="${PROBE_ROOT}/home"
SUPPORT="${SCRATCH}/bridge-namespace"
CLI="${SCRATCH}/scholium"
APP_PID=""

cleanup() {
  local exit_code=$?
  if [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" 2>/dev/null; then
    kill "${APP_PID}" 2>/dev/null || true
    wait "${APP_PID}" 2>/dev/null || true
  fi
  rm -rf "${PROBE_ROOT}"
  if [[ "${SCRATCH}" == "${ROOT}/.build/ab" ]] \
    && (( exit_code == 0 )); then
    rm -rf "${SCRATCH}"
  fi
  if (( exit_code != 0 )); then
    print -u2 "Agent bridge probe evidence retained at ${SCRATCH}."
  fi
}
trap cleanup EXIT

rm -rf "${SCRATCH}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources" \
  "${PROBE_HOME}" "${SUPPORT}"

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
cp "${BUILD}/debug/scholium" "${CLI}"
chmod +x "${APP}/Contents/MacOS/Scholium" "${CLI}"
cp -R "${BUILD}/debug/Scholium_ScholiumApp.bundle" "${APP}/Contents/Resources/"
cp -R "${BUILD}/debug/Scholium_ScholiumCore.bundle" "${APP}/Contents/Resources/"
cp -R "${BUILD}/debug/Scholium_ScholiumCore.bundle" "${SCRATCH}/"
cp "${ROOT}/Tools/Packaging/Info.plist" "${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" \
  -c "Set :CFBundleName Scholium Agent Bridge Probe" \
  "${APP}/Contents/Info.plist"

xattr -cr "${APP}"
codesign --force --options runtime --sign - "${CLI}"
codesign --force --options runtime \
  --entitlements "${ROOT}/Tools/Packaging/Scholium.entitlements" \
  --sign - "${APP}"
codesign --verify --deep --strict "${APP}"
codesign --verify --strict "${CLI}"

APP_ENTITLEMENTS="${SCRATCH}/app-entitlements.plist"
CLI_ENTITLEMENTS="${SCRATCH}/cli-entitlements.plist"
codesign -d --entitlements :- "${APP}" > "${APP_ENTITLEMENTS}" 2>/dev/null
codesign -d --entitlements :- "${CLI}" > "${CLI_ENTITLEMENTS}" 2>/dev/null || true
if ! rg -q 'com\.apple\.security\.app-sandbox' "${APP_ENTITLEMENTS}"; then
  print -u2 "The local bridge probe App is not sandboxed."
  exit 65
fi
if rg -q 'com\.apple\.security\.app-sandbox' "${CLI_ENTITLEMENTS}"; then
  print -u2 "The standalone CLI unexpectedly contains App Sandbox entitlements."
  exit 65
fi
if rg -q 'com\.apple\.security\.application-groups' \
  "${APP_ENTITLEMENTS}" "${CLI_ENTITLEMENTS}"; then
  print -u2 "The source-first bridge probe unexpectedly depends on an App Group."
  exit 65
fi

RUN_LOCATOR="local-agent-bridge-probe"
PAIRING_CODE="ABCD-EFGH-JKLM-NPQR-STUV-WXYZ"

BEFORE="$(print -r -- "${PAIRING_CODE}" | \
  SCHOLIUM_AGENT_BRIDGE_CONTAINER="${SUPPORT}" \
  "${CLI}" agent pair --run "${RUN_LOCATOR}" \
  2>&1 || true)"
print -r -- "${BEFORE}" | rg -qi 'unavailable'

SCHOLIUM_HOME="${PROBE_HOME}" \
SCHOLIUM_AGENT_BRIDGE_CONTAINER="${SUPPORT}" \
  "${APP}/Contents/MacOS/Scholium" \
  > "${SCRATCH}/app.stdout" 2> "${SCRATCH}/app.stderr" &
APP_PID=$!

AFTER=""
for _ in {1..100}; do
  kill -0 "${APP_PID}" 2>/dev/null || {
    print -u2 "The local probe App exited before opening its bridge."
    sed -n '1,120p' "${SCRATCH}/app.stderr" >&2
    exit 1
  }
  AFTER="$(print -r -- "${PAIRING_CODE}" | \
    SCHOLIUM_AGENT_BRIDGE_CONTAINER="${SUPPORT}" \
    "${CLI}" agent pair --run "${RUN_LOCATOR}" \
    2>&1 || true)"
  if ! print -r -- "${AFTER}" | rg -qi 'unavailable'; then
    break
  fi
  sleep 0.1
done
[[ -n "${AFTER}" ]] && ! print -r -- "${AFTER}" | rg -qi 'unavailable' || {
  print -u2 "The local probe App did not open its loopback bridge."
  sed -n '1,120p' "${SCRATCH}/app.stderr" >&2
  exit 1
}
print -r -- "${AFTER}" | rg -qi 'bridge request was not authorized'
if print -r -- "${AFTER}" | rg -qi 'unavailable'; then
  print -u2 "The unpackaged CLI could not reach the local App bridge."
  exit 1
fi
if rg -Fq "${PAIRING_CODE}" \
  "${SCRATCH}/app.stdout" "${SCRATCH}/app.stderr"; then
  print -u2 "The local App logged the raw Pairing Code."
  exit 1
fi

kill "${APP_PID}"
wait "${APP_PID}" || true
APP_PID=""

print "Sandboxed App to standalone CLI loopback bridge probe passed."
print "App sandbox: enabled; standalone CLI sandbox: disabled."
print "Endpoint: 127.0.0.1 only; closed-App path: typed unavailable."
print "An invalid but well-formed Pairing Code reached the App, received the generic authorization denial, and was not logged."
