#!/bin/zsh
set -euo pipefail

package_root="${0:A:h}"
source_executable="${package_root}/scholium"
source_resources="${package_root}/Scholium_ScholiumCore.bundle"
install_prefix="${SCHOLIUM_CLI_PREFIX:-${HOME}/.local}"
destination_root="${install_prefix}/bin"

[[ -x "${source_executable}" ]] || {
  print -u2 "The Scholium CLI executable is missing from this package."
  exit 66
}
[[ -d "${source_resources}" ]] || {
  print -u2 "The Scholium CLI resource bundle is missing from this package."
  exit 66
}
[[ -n "${destination_root}" && "${destination_root}" != "/" ]] || {
  print -u2 "Refusing an invalid CLI installation destination."
  exit 64
}

staging_root="${destination_root}/.scholium-install-${$}"
cleanup() {
  rm -rf "${staging_root}"
}
trap cleanup EXIT

mkdir -p "${staging_root}"
install -m 755 "${source_executable}" "${staging_root}/scholium"
cp -R "${source_resources}" "${staging_root}/Scholium_ScholiumCore.bundle"

rm -f "${destination_root}/scholium"
rm -rf "${destination_root}/Scholium_ScholiumCore.bundle"
mv "${staging_root}/scholium" "${destination_root}/scholium"
mv "${staging_root}/Scholium_ScholiumCore.bundle" \
  "${destination_root}/Scholium_ScholiumCore.bundle"

"${destination_root}/scholium" version --format json
"${destination_root}/scholium" doctor --format json
print "Installed Scholium CLI at ${destination_root}/scholium"
