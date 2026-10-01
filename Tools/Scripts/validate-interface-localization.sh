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

interface_catalog="${repository_root}/Scholium/Resources/Interface.xcstrings"
localizable_catalog="${repository_root}/Scholium/Resources/Localizable.xcstrings"
webkit_catalog="${repository_root}/Scholium/Resources/WebKitInterface.xcstrings"
all_extracted_directory="${temporary_root}/all-extracted"
compiled_directory="${temporary_root}/compiled"
source_keys="${temporary_root}/source-keys.txt"
catalog_keys="${temporary_root}/catalog-keys.txt"
all_source_keys="${temporary_root}/all-source-keys.txt"
localizable_keys="${temporary_root}/localizable-keys.txt"

mkdir -p "${all_extracted_directory}" "${compiled_directory}"

find "${repository_root}/Scholium" -type f -name '*.swift' -print0 \
  | xargs -0 env DEVELOPER_DIR="${developer_dir}" xcrun xcstringstool extract \
      --SwiftUI \
      --modern-localizable-strings \
      --output-format xcstrings \
      --output-directory "${all_extracted_directory}"

jq -r '.strings | keys[]' \
  "${all_extracted_directory}/Interface.xcstrings" > "${source_keys}"
jq -r '.strings | keys[]' "${interface_catalog}" > "${catalog_keys}"

if ! diff -u "${source_keys}" "${catalog_keys}"; then
  print -u2 "Interface.xcstrings keys do not match the App's localized resources."
  exit 1
fi

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

python3 "${script_dir}/validate-localization-catalogs.py" --self-test \
  "${interface_catalog}" "${localizable_catalog}" "${webkit_catalog}"

for catalog_file in "${interface_catalog}" "${localizable_catalog}" "${webkit_catalog}"; do
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

[[ -f "${compiled_directory}/zh-Hans.lproj/WebKitInterface.strings" ]] || {
  print -u2 "The compiled Simplified Chinese WebKitInterface table is missing."
  exit 1
}

node "${repository_root}/WebEditor/validate-localization.mjs"

print "Interface localization validation passed (Interface + Localizable + WebKitInterface)."
