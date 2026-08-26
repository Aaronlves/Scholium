#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-$("${ROOT}/Tools/Scripts/resolve-xcode-developer-dir.sh")}"
export DEVELOPER_DIR
# Source-checkout development artifacts stay with this repository. The
# packaged release installer has its separate, intentional user-local default.
PREFIX="${SCHOLIUM_CLI_PREFIX:-${ROOT}/.build/cli-prefix}"
SCRATCH="${ROOT}/.build/cli-release"
DESTINATION="${PREFIX}/bin/scholium"
TEMPORARY="${PREFIX}/bin/.scholium-install.$$"
RESOURCE_BUNDLE="${PREFIX}/bin/Scholium_ScholiumCore.bundle"
RESOURCE_TEMPORARY="${PREFIX}/bin/.Scholium_ScholiumCore.bundle.$$"

swift build --package-path "${ROOT}" -c release --product scholium --scratch-path "${SCRATCH}"
mkdir -p "${PREFIX}/bin"
trap 'rm -rf "${TEMPORARY}" "${RESOURCE_TEMPORARY}"' EXIT
cp -R "${SCRATCH}/release/Scholium_ScholiumCore.bundle" "${RESOURCE_TEMPORARY}"
rm -rf "${RESOURCE_BUNDLE}"
mv "${RESOURCE_TEMPORARY}" "${RESOURCE_BUNDLE}"
install -m 755 "${SCRATCH}/release/scholium" "${TEMPORARY}"
mv -f "${TEMPORARY}" "${DESTINATION}"
"${DESTINATION}" version --format json >/dev/null

echo "Installed: ${DESTINATION}"
echo "Add ${PREFIX}/bin to PATH if it is not already present."
