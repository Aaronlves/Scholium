#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repository_root="${script_dir:h:h}"
developer_dir="$(${script_dir}/resolve-xcode-developer-dir.sh)"
temporary_root="${repository_root}/.build/localization-validation-$$"

cleanup() {
  rm -rf -- "${temporary_root}"
}
trap cleanup EXIT

rm -rf -- "${temporary_root}"

source_file="${repository_root}/Scholium/Localization/ScholiumL10n.swift"
interface_catalog="${repository_root}/Scholium/Resources/Interface.xcstrings"
localizable_catalog="${repository_root}/Scholium/Resources/Localizable.xcstrings"
extracted_directory="${temporary_root}/extracted"
all_extracted_directory="${temporary_root}/all-extracted"
compiled_directory="${temporary_root}/compiled"
source_keys="${temporary_root}/source-keys.txt"
catalog_keys="${temporary_root}/catalog-keys.txt"
all_source_keys="${temporary_root}/all-source-keys.txt"
localizable_keys="${temporary_root}/localizable-keys.txt"

mkdir -p "${extracted_directory}" "${all_extracted_directory}" "${compiled_directory}"

DEVELOPER_DIR="${developer_dir}" xcrun xcstringstool extract \
  --modern-localizable-strings \
  --output-format xcstrings \
  --output-directory "${extracted_directory}" \
  "${source_file}"

jq -r '.strings | keys[]' \
  "${extracted_directory}/Interface.xcstrings" > "${source_keys}"
jq -r '.strings | keys[]' "${interface_catalog}" > "${catalog_keys}"

if ! diff -u "${source_keys}" "${catalog_keys}"; then
  print -u2 "Interface.xcstrings keys do not match ScholiumL10n.swift."
  exit 1
fi

find "${repository_root}/Scholium" -type f -name '*.swift' -print0 \
  | xargs -0 env DEVELOPER_DIR="${developer_dir}" xcrun xcstringstool extract \
      --SwiftUI \
      --modern-localizable-strings \
      --output-format xcstrings \
      --output-directory "${all_extracted_directory}"
jq -r '.strings | keys[]' \
  "${all_extracted_directory}/Localizable.xcstrings" \
  | sed -E 's/%([0-9]+\$)?(lld|ld|d|f|@|arg)/%arg/g' \
  | sort -u > "${all_source_keys}"
jq -r '.strings | keys[]' "${localizable_catalog}" \
  | sed -E 's/%([0-9]+\$)?(lld|ld|d|f|@|arg)/%arg/g' \
  | sort -u > "${localizable_keys}"
missing_static_keys="$(comm -23 "${all_source_keys}" "${localizable_keys}")"
if [[ -n "${missing_static_keys}" ]]; then
  print -u2 "Localizable.xcstrings is missing extracted interface strings:"
  print -u2 -- "${missing_static_keys}"
  exit 1
fi

missing_simplified_chinese="$({
  jq -r '
    .strings
    | to_entries[]
    | select(.value.localizations["zh-Hans"].stringUnit.state != "translated")
    | .key
  ' "${interface_catalog}" "${localizable_catalog}"
})"

if [[ -n "${missing_simplified_chinese}" ]]; then
  print -u2 "A string catalog has untranslated zh-Hans entries:"
  print -u2 -- "${missing_simplified_chinese}"
  exit 1
fi

placeholder_mismatches="$({
  jq -r '
    .strings
    | to_entries[]
    | .key as $key
    | ([.value.localizations.en.stringUnit.value | scan("%(?:[0-9]+\\$)?(?:arg|@|d|lld|ld|f)")] | sort) as $en
    | ([.value.localizations["zh-Hans"].stringUnit.value | scan("%(?:[0-9]+\\$)?(?:arg|@|d|lld|ld|f)")] | sort) as $zh
    | select($en != $zh)
    | $key
  ' "${interface_catalog}" "${localizable_catalog}"
})"
if [[ -n "${placeholder_mismatches}" ]]; then
  print -u2 "Localized format placeholders changed:"
  print -u2 -- "${placeholder_mismatches}"
  exit 1
fi

ascii_chinese_punctuation="$({
  jq -r '
    .strings
    | to_entries[]
    | select(
        .value.localizations["zh-Hans"].stringUnit.value
        | test("\\.\\.\\.|[,;!?()]|: ")
      )
    | .key
  ' "${interface_catalog}" "${localizable_catalog}"
})"
if [[ -n "${ascii_chinese_punctuation}" ]]; then
  print -u2 "Simplified Chinese interface prose uses ASCII punctuation:"
  print -u2 -- "${ascii_chinese_punctuation}"
  exit 1
fi

for catalog_file in "${interface_catalog}" "${localizable_catalog}"; do
  DEVELOPER_DIR="${developer_dir}" xcrun xcstringstool compile \
    --output-directory "${compiled_directory}" \
    "${catalog_file}"
done

compiled_catalog="${compiled_directory}/zh-Hans.lproj/Interface.strings"
[[ -f "${compiled_catalog}" ]] || {
  print -u2 "The compiled Simplified Chinese Interface table is missing."
  exit 1
}

[[ -f "${compiled_directory}/zh-Hans.lproj/Localizable.strings" ]] || {
  print -u2 "The compiled Simplified Chinese Localizable table is missing."
  exit 1
}

print "Interface localization validation passed (Interface + Localizable)."
