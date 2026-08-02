#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
XCODE="$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")"
DERIVED="${ROOT}/.build/qa-swiftpm"
QA_ROOT="${ROOT}/.build/qa-runtime"
APP="${QA_ROOT}/Scholium-QA.app"
FIXTURE_SOURCE="${SCHOLIUM_TEST_VAULTS:-${HOME}/Desktop/TestVaults}"
FIXTURE_COPY="${QA_ROOT}/fixtures"
QA_HOME="${QA_ROOT}/home"

[[ -d "${FIXTURE_SOURCE}" ]] || { print -u2 "Missing fixture vault root: ${FIXTURE_SOURCE}"; exit 1; }

terminate_qa_instances() {
  pkill -f "${APP}/Contents/MacOS/Scholium" 2>/dev/null || true
  pkill -f "${QA_ROOT}/registered/Scholium-Codex-QA-Do-Not-Use.app/Contents/MacOS/Scholium" 2>/dev/null || true

  # A QA process can be launched with a repository-relative command, which
  # does not match the absolute command-line patterns above. Resolve the
  # running image before terminating it so only this checkout's QA bundles
  # are included.
  local qa_pid executable
  local qa_pids=("${(@f)$(pgrep -x Scholium 2>/dev/null || true)}")
  for qa_pid in "${qa_pids[@]}"; do
    [[ -n "${qa_pid}" ]] || continue
    executable="$(
      /usr/sbin/lsof -a -p "${qa_pid}" -d txt -Fn 2>/dev/null \
        | sed -n 's/^n//p' \
        | head -n 1
    )"
    case "${executable}" in
      "${APP}/Contents/MacOS/Scholium"|\
      "/private${APP}/Contents/MacOS/Scholium"|\
      "${QA_ROOT}/registered/Scholium-Codex-QA-Do-Not-Use.app/Contents/MacOS/Scholium")
        kill "${qa_pid}" 2>/dev/null || true
        ;;
    esac
  done
}

# Rebuilding a running bundle can leave several stale QA processes alive.
# Terminate only known test-owned bundle paths before replacing the artifact.
terminate_qa_instances
rm -rf "${DERIVED}" "${APP}" "${FIXTURE_COPY}" "${QA_HOME}"
mkdir -p "${FIXTURE_COPY}" "${QA_HOME}"
for vault_root in 01-analyses 02-topics 03-works; do
  [[ -d "${FIXTURE_SOURCE}/${vault_root}" ]] || {
    print -u2 "Missing static fixture vault: ${FIXTURE_SOURCE}/${vault_root}"
    exit 1
  }
  cp -R "${FIXTURE_SOURCE}/${vault_root}" "${FIXTURE_COPY}/${vault_root}"
done
if [[ -d "${FIXTURE_SOURCE}/.scholium" ]]; then
  cp -R "${FIXTURE_SOURCE}/.scholium" "${FIXTURE_COPY}/.scholium"
fi
# QA consumes a static fixture snapshot. Authoring utilities such as
# generate_fixtures.py are deliberately neither copied nor executed.

DEVELOPER_DIR="${XCODE}" swift build \
  --package-path "${ROOT}" \
  --scratch-path "${DERIVED}" \
  --configuration debug \
  --product ScholiumApp
DEVELOPER_DIR="${XCODE}" swift build \
  --package-path "${ROOT}" \
  --scratch-path "${DERIVED}" \
  --configuration debug \
  --product scholium

mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Helpers" "${APP}/Contents/Resources"
cp "${DERIVED}/debug/ScholiumApp" "${APP}/Contents/MacOS/Scholium"
cp "${DERIVED}/debug/scholium" "${APP}/Contents/Helpers/scholium"
chmod +x "${APP}/Contents/Helpers/scholium"
cp -R "${DERIVED}/debug/Scholium_ScholiumApp.bundle" "${APP}/Contents/Resources/"
cp -R "${DERIVED}/debug/Scholium_ScholiumCore.bundle" "${APP}/Contents/Resources/"
# SwiftUI's literal-based controls resolve against the outer application
# bundle. Mirror the package target's compiled catalogs there while retaining
# the SwiftPM resource bundle for explicit Bundle.module lookups.
find "${DERIVED}/debug/Scholium_ScholiumApp.bundle" -type d -name '*.lproj' | while IFS= read -r localization; do
  cp -R "${localization}" "${APP}/Contents/Resources/"
done
cp "${ROOT}/Tools/Packaging/Info.plist" "${APP}/Contents/Info.plist"
cp "${ROOT}/Tools/Packaging/ScholiumIcon.icns" "${APP}/Contents/Resources/"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier com.scholium.qa" \
  -c "Set :CFBundleName Scholium QA" \
  "${APP}/Contents/Info.plist"
xattr -cr "${APP}"
codesign --force --deep --sign - "${APP}"
codesign --verify --deep --strict "${APP}"

print "QA app: ${APP}"
print "Disposable fixtures: ${FIXTURE_COPY}"
print "This is a SwiftPM Debug test bundle built with the selected Xcode toolchain, not a release package."
