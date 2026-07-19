#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repository_root="${script_dir:h:h}"
developer_dir="$(${script_dir}/resolve-xcode-developer-dir.sh)"
scratch_root="${repository_root}/.build/localization-sync-$$"

cleanup() {
  rm -rf -- "${scratch_root}"
}
trap cleanup EXIT

COPYFILE_DISABLE=1 DEVELOPER_DIR="${developer_dir}" swift build \
  --package-path "${repository_root}" \
  --scratch-path "${scratch_root}" \
  --product ScholiumApp

typeset -a stringsdata_arguments
while IFS= read -r -d '' stringsdata_file; do
  stringsdata_arguments+=(--stringsdata "${stringsdata_file}")
done < <(find "${scratch_root}" -type f -name '*.stringsdata' -print0)

(( ${#stringsdata_arguments[@]} > 0 )) || {
  print -u2 "The compiler emitted no localization source data."
  exit 1
}

DEVELOPER_DIR="${developer_dir}" xcrun xcstringstool sync \
  "${repository_root}/Scholium/Resources/Interface.xcstrings" \
  "${repository_root}/Scholium/Resources/Localizable.xcstrings" \
  "${stringsdata_arguments[@]}" \
  --skip-marking-strings-stale

missing_count="$(jq -s '
  [.[].strings[] | select(.localizations["zh-Hans"].stringUnit.state != "translated")]
  | length
' \
  "${repository_root}/Scholium/Resources/Interface.xcstrings" \
  "${repository_root}/Scholium/Resources/Localizable.xcstrings")"

print "String Catalogs synchronized from compiler output."
print "Simplified Chinese entries still requiring translation: ${missing_count}"
