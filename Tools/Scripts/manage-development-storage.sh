#!/bin/zsh
set -u

ROOT="${0:A:h:h:h}"
USER_TEMP_ROOT="$(getconf DARWIN_USER_TEMP_DIR)"
USER_TEMP_ROOT="${USER_TEMP_ROOT%/}"
DERIVED_DATA_ROOT="${HOME}/Library/Developer/Xcode/DerivedData"
LOCAL_BUILD_ROOT="${ROOT}/.build"
LEGACY_EXTERNAL_BUILD_ROOT="${HOME}/Library/Developer/Scholium/Build"
if [[ -x "${ROOT}/Tools/Scripts/resolve-external-build-path.sh" ]] \
  && rg -q 'resolve-external-build-path' "${ROOT}/Tools/Scripts/verify.sh"; then
  CONFIGURED_BUILD_ROOT="${SCHOLIUM_BUILD_ROOT:-${LEGACY_EXTERNAL_BUILD_ROOT}}"
  CONFIGURED_BUILD_ROOT="${CONFIGURED_BUILD_ROOT:A}"
else
  CONFIGURED_BUILD_ROOT="${LOCAL_BUILD_ROOT}"
fi
PACKAGE_OUTPUT="${HOME}/Applications/Scholium Builds"

typeset -a CANDIDATES
typeset -A SEEN_CANDIDATES

usage() {
  cat <<'EOF'
Usage:
  manage-development-storage.sh interactive
  manage-development-storage.sh report
  manage-development-storage.sh open configured-build|local-build|temporary|derived-data|packages
  manage-development-storage.sh clean-stale [--delete]
  manage-development-storage.sh clean-all [--delete]

Cleaning without --delete is a dry run. clean-stale preserves both configured
and repository-local build roots. clean-all removes both; the next build will
regenerate them.
EOF
}

add_candidate() {
  local candidate="$1"
  [[ -e "${candidate}" || -L "${candidate}" ]] || return
  [[ -z "${SEEN_CANDIDATES[${candidate}]-}" ]] || return
  SEEN_CANDIDATES[${candidate}]=1
  CANDIDATES+=("${candidate}")
}

collect_stale_candidates() {
  CANDIDATES=()
  SEEN_CANDIDATES=()

  add_candidate "${HOME}/Applications/Scholium-Codex-QA-Do-Not-Use.app"
  if [[ "${CONFIGURED_BUILD_ROOT}" != "${LEGACY_EXTERNAL_BUILD_ROOT}" ]]; then
    add_candidate "${LEGACY_EXTERNAL_BUILD_ROOT}"
  fi

  local candidate
  while IFS= read -r -d '' candidate; do
    add_candidate "${candidate}"
  done < <(find /private/tmp -mindepth 1 -maxdepth 1 \
    \( -iname '*scholium*' -o -iname '*kbmanager*' -o -iname '*kb-manager*' \) \
    -print0 2>/dev/null)

  while IFS= read -r -d '' candidate; do
    add_candidate "${candidate}"
  done < <(find "${USER_TEMP_ROOT}" -mindepth 1 -maxdepth 1 \
    \( -iname '*scholium*' -o -iname '*kbmanager*' -o -iname '*kb-manager*' \) \
    -print0 2>/dev/null)

  if [[ -d "${DERIVED_DATA_ROOT}" ]]; then
    while IFS= read -r -d '' candidate; do
      add_candidate "${candidate}"
    done < <(find "${DERIVED_DATA_ROOT}" -mindepth 1 -maxdepth 1 \
      \( -name 'Scholium-*' -o -name 'ScholiumUITests-*' \) \
      -print0 2>/dev/null)
  fi

  while IFS= read -r -d '' candidate; do
    add_candidate "${candidate}"
  done < <(find "${HOME}/.Trash" -mindepth 1 -maxdepth 1 \
    -name 'Scholium-external-build-cache-*' -print0 2>/dev/null)
}

candidate_is_safe() {
  local candidate="$1"
  local base="${candidate:t}"
  local lower="${(L)base}"

  case "${candidate}" in
    "${LOCAL_BUILD_ROOT}"|\
    "${LEGACY_EXTERNAL_BUILD_ROOT}"|\
    "${HOME}/Applications/Scholium-Codex-QA-Do-Not-Use.app")
      return 0
      ;;
    "${DERIVED_DATA_ROOT}/Scholium-"*|"${DERIVED_DATA_ROOT}/ScholiumUITests-"*)
      return 0
      ;;
    "${HOME}/.Trash/Scholium-external-build-cache-"*)
      return 0
      ;;
    /private/tmp/*|"${USER_TEMP_ROOT}/"*)
      [[ "${lower}" == *scholium* || "${lower}" == *kbmanager* || "${lower}" == *kb-manager* ]]
      return
      ;;
  esac

  return 1
}

item_size_kb() {
  local candidate="$1"
  du -sk "${candidate}" 2>/dev/null | awk '{print $1 + 0}'
}

candidates_size_kb() {
  local total=0
  local candidate size
  for candidate in "${CANDIDATES[@]}"; do
    size="$(item_size_kb "${candidate}")"
    total=$(( total + ${size:-0} ))
  done
  print -r -- "${total}"
}

human_size() {
  local kilobytes="${1:-0}"
  awk -v kb="${kilobytes}" 'BEGIN {
    if (kb >= 1048576) printf "%.2f GB", kb / 1048576;
    else if (kb >= 1024) printf "%.1f MB", kb / 1024;
    else printf "%d KB", kb;
  }'
}

size_or_zero() {
  local candidate="$1"
  if [[ -e "${candidate}" || -L "${candidate}" ]]; then
    item_size_kb "${candidate}"
  else
    print 0
  fi
}

report_text() {
  collect_stale_candidates
  local configured_kb local_kb package_kb stale_kb
  configured_kb="$(size_or_zero "${CONFIGURED_BUILD_ROOT}")"
  local_kb="$(size_or_zero "${LOCAL_BUILD_ROOT}")"
  package_kb="$(size_or_zero "${PACKAGE_OUTPUT}")"
  stale_kb="$(candidates_size_kb)"

  cat <<EOF
Configured build root: $(human_size "${configured_kb}")
Repository-local .build: $(human_size "${local_kb}")
Stale development artifacts: $(human_size "${stale_kb}") (${#CANDIDATES[@]} items)
Packaged builds: $(human_size "${package_kb}")

Configured build root: ${CONFIGURED_BUILD_ROOT}
Local build root: ${LOCAL_BUILD_ROOT}
Temporary files: /private/tmp and ${USER_TEMP_ROOT}
Xcode DerivedData: ${DERIVED_DATA_ROOT}
Packaged builds: ${PACKAGE_OUTPUT}
EOF
}

print_candidates() {
  local candidate size
  if (( ${#CANDIDATES[@]} == 0 )); then
    print "No matching development artifacts were found."
    return
  fi

  for candidate in "${CANDIDATES[@]}"; do
    size="$(item_size_kb "${candidate}")"
    printf '%10s  %s\n' "$(human_size "${size:-0}")" "${candidate}"
  done
  print "Total: $(human_size "$(candidates_size_kb)") in ${#CANDIDATES[@]} items"
}

build_processes_are_running() {
  pgrep -f '(^|/)(swift-build|swift-test|swift-frontend|swiftc|xcodebuild)( |$)|/Contents/MacOS/Scholium( |$)' >/dev/null 2>&1
}

perform_cleanup() {
  local include_build="$1"
  collect_stale_candidates
  if [[ "${include_build}" == true ]]; then
    add_candidate "${CONFIGURED_BUILD_ROOT}"
    add_candidate "${LOCAL_BUILD_ROOT}"
  fi

  if build_processes_are_running; then
    print -u2 "A Swift, Xcode, or Scholium process is running. Stop it before cleaning development storage."
    return 75
  fi

  local before_kb candidate failures=0
  before_kb="$(candidates_size_kb)"
  for candidate in "${CANDIDATES[@]}"; do
    if ! candidate_is_safe "${candidate}"; then
      print -u2 "Refusing an unrecognized cleanup path: ${candidate}"
      failures=$(( failures + 1 ))
      continue
    fi
    if ! /bin/rm -rf -- "${candidate}"; then
      print -u2 "Could not remove: ${candidate}"
      failures=$(( failures + 1 ))
    fi
  done

  (( failures == 0 )) || return 1
  print "Removed $(human_size "${before_kb}") of rebuildable Scholium development artifacts."
}

open_existing_or_parent() {
  local destination="$1"
  local parent="$2"
  if [[ -d "${destination}" ]]; then
    open "${destination}"
  else
    open "${parent}"
  fi
}

open_location() {
  local destination="$1"
  case "${destination}" in
    configured-build)
      mkdir -p "${CONFIGURED_BUILD_ROOT}"
      open "${CONFIGURED_BUILD_ROOT}"
      ;;
    local-build)
      mkdir -p "${LOCAL_BUILD_ROOT}"
      open "${LOCAL_BUILD_ROOT}"
      ;;
    temporary)
      open /private/tmp
      open "${USER_TEMP_ROOT}"
      ;;
    derived-data)
      mkdir -p "${DERIVED_DATA_ROOT}"
      open "${DERIVED_DATA_ROOT}"
      ;;
    packages)
      open_existing_or_parent "${PACKAGE_OUTPUT}" "${HOME}/Applications"
      ;;
    *)
      print -u2 "Unknown storage location: ${destination}"
      return 64
      ;;
  esac
}

show_dialog() {
  local title="$1"
  local message="$2"
  osascript - "${title}" "${message}" <<'APPLESCRIPT' >/dev/null
on run argv
  display dialog (item 2 of argv) with title (item 1 of argv) buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

confirm_cleanup() {
  local message="$1"
  local response
  response="$(osascript - "${message}" <<'APPLESCRIPT'
on run argv
  set resultDialog to display dialog (item 1 of argv) with title "Scholium Development Storage" buttons {"Cancel", "Delete"} default button "Cancel" cancel button "Cancel" with icon caution
  return button returned of resultDialog
end run
APPLESCRIPT
)" || return 1
  [[ "${response}" == Delete ]]
}

choose_interactive_action() {
  osascript <<'APPLESCRIPT'
set actions to {"Show storage report", "Open configured build root", "Open local .build", "Open temporary files", "Open Xcode DerivedData", "Open packaged builds", "Delete stale artifacts", "Delete all rebuildable artifacts"}
set picked to choose from list actions with title "Scholium Development Storage" with prompt "Choose an action. Application state and Triptych files are always protected." default items {"Show storage report"}
if picked is false then return "Quit"
return item 1 of picked
APPLESCRIPT
}

interactive() {
  local action preview result
  while true; do
    action="$(choose_interactive_action)" || return 1
    case "${action}" in
      Quit) return 0 ;;
      'Show storage report') show_dialog "Scholium Development Storage" "$(report_text)" ;;
      'Open configured build root') open_location configured-build ;;
      'Open local .build') open_location local-build ;;
      'Open temporary files') open_location temporary ;;
      'Open Xcode DerivedData') open_location derived-data ;;
      'Open packaged builds') open_location packages ;;
      'Delete stale artifacts')
        collect_stale_candidates
        preview="Delete $(human_size "$(candidates_size_kb)") in ${#CANDIDATES[@]} stale items?\n\nBoth build roots, application state, packaged builds, and Triptych files will remain."
        if confirm_cleanup "${preview}"; then
          result="$(perform_cleanup false 2>&1)" || {
            show_dialog "Cleanup Failed" "${result:-A protected or active file could not be removed.}"
            continue
          }
          show_dialog "Cleanup Complete" "${result}"
        fi
        ;;
      'Delete all rebuildable artifacts')
        collect_stale_candidates
        add_candidate "${CONFIGURED_BUILD_ROOT}"
        add_candidate "${LOCAL_BUILD_ROOT}"
        preview="Delete $(human_size "$(candidates_size_kb)") in ${#CANDIDATES[@]} rebuildable items?\n\nThis includes configured and local build roots. The next build will be slower. Application state, packaged builds, and Triptych files will remain."
        if confirm_cleanup "${preview}"; then
          result="$(perform_cleanup true 2>&1)" || {
            show_dialog "Cleanup Failed" "${result:-A protected or active file could not be removed.}"
            continue
          }
          show_dialog "Cleanup Complete" "${result}"
        fi
        ;;
    esac
  done
}

command="${1:-interactive}"
case "${command}" in
  interactive)
    interactive
    ;;
  report)
    report_text
    ;;
  open)
    (( $# == 2 )) || { usage; exit 64; }
    open_location "$2"
    ;;
  clean-stale|clean-all)
    include_build=false
    [[ "${command}" == clean-all ]] && include_build=true
    collect_stale_candidates
    if [[ "${include_build}" == true ]]; then
      add_candidate "${CONFIGURED_BUILD_ROOT}"
      add_candidate "${LOCAL_BUILD_ROOT}"
    fi
    print_candidates
    if [[ "${2:-}" != --delete ]]; then
      print
      print "Dry run only. Add --delete to remove these rebuildable files."
      exit 0
    fi
    perform_cleanup "${include_build}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 64
    ;;
esac
