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

mkdir -p "${destination_root}"
[[ -d "${destination_root}" && ! -L "${destination_root}" ]] || {
  print -u2 "The CLI installation destination is not a real directory."
  exit 73
}

installation_lock="${destination_root}/.scholium-cli-install.lock"
if [[ ! -e "${installation_lock}" && ! -L "${installation_lock}" ]]; then
  (umask 077; setopt noclobber; : > "${installation_lock}") 2>/dev/null || true
fi
lock_mode="$(/usr/bin/stat -f %Lp "${installation_lock}" 2>/dev/null || true)"
[[ -f "${installation_lock}" && ! -L "${installation_lock}" \
    && -O "${installation_lock}" && -n "${lock_mode}" ]] \
  && (( (8#${lock_mode} & 8#077) == 0 )) || {
    print -u2 "The shared CLI installation lock is unavailable or unsafe."
    exit 73
  }
zmodload zsh/system || {
  print -u2 "The shell cannot load the shared CLI installation lock support."
  exit 69
}
zsystem flock -t 0 -f installation_lock_descriptor "${installation_lock}" || {
  print -u2 "Another Scholium CLI installation or update is already running."
  exit 75
}

staging_root="${destination_root}/.scholium-install-${$}"
cleanup() {
  rm -rf "${staging_root}"
}
trap cleanup EXIT

destination_executable="${destination_root}/scholium"
destination_resources="${destination_root}/Scholium_ScholiumCore.bundle"
executable_present=0
resources_present=0
[[ -e "${destination_executable}" || -L "${destination_executable}" ]] \
  && executable_present=1
[[ -e "${destination_resources}" || -L "${destination_resources}" ]] \
  && resources_present=1

if (( executable_present && resources_present )); then
  print -u2 "Scholium CLI is already installed. Use 'scholium update' for verified replacement."
  exit 73
fi

if (( executable_present )); then
  [[ -f "${destination_executable}" && ! -L "${destination_executable}" \
      && -x "${destination_executable}" ]] \
    && /usr/bin/cmp -s "${source_executable}" "${destination_executable}" || {
      print -u2 "The partial CLI executable differs from this package; no files were changed."
      exit 73
    }
fi

if (( resources_present )); then
  [[ -d "${destination_resources}" && ! -L "${destination_resources}" ]] \
    && /usr/bin/diff -qr "${source_resources}" "${destination_resources}" \
      >/dev/null || {
      print -u2 "The partial CLI resource bundle differs from this package; no files were changed."
      exit 73
    }
fi

mkdir -p "${staging_root}"
published_resources=0
if (( ! resources_present )); then
  cp -R "${source_resources}" "${staging_root}/Scholium_ScholiumCore.bundle"
  /bin/mv -n "${staging_root}/Scholium_ScholiumCore.bundle" \
    "${destination_resources}" || true
  if [[ -e "${staging_root}/Scholium_ScholiumCore.bundle" ]]; then
    print -u2 "The CLI resource destination appeared during installation; no executable was published."
    exit 75
  fi
  published_resources=1
fi
if (( ! executable_present )); then
  install -m 755 "${source_executable}" "${staging_root}/scholium"
  # The executable is published last so a first install cannot advertise a
  # runnable CLI without its adjacent resource bundle.
  /bin/mv -n "${staging_root}/scholium" "${destination_executable}" || true
  if [[ -e "${staging_root}/scholium" ]]; then
    if (( published_resources )) \
        && [[ -d "${destination_resources}" && ! -L "${destination_resources}" ]] \
        && /usr/bin/diff -qr "${source_resources}" "${destination_resources}" \
          >/dev/null; then
      /bin/mv -n "${destination_resources}" \
        "${staging_root}/rollback-resources" || true
    fi
    print -u2 "The CLI executable destination appeared during installation; this package published no executable."
    exit 75
  fi
fi

"${destination_root}/scholium" version --format json
"${destination_root}/scholium" doctor --format json
print "Installed Scholium CLI at ${destination_root}/scholium"
