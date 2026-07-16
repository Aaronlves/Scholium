#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
committed="$repo_root/Scholium/Resources/Editor/editor.bundle.js"
callout_styles="$repo_root/Scholium/Resources/Editor/callouts.css"
editor_styles="$repo_root/Scholium/Resources/Editor/editor.css"
read_styles="$repo_root/Scholium/Views/Note/SafeMarkdownReadWebView.swift"
renderer="$repo_root/ScholiumContracts/SafeMarkdownRenderer.swift"
temporary="$(mktemp -t scholium-editor.XXXXXX.js)"
trap 'rm -f "$temporary"' EXIT

if [[ ! -s "$callout_styles" ]] || ! rg -q '^\.scholium-callout' "$callout_styles" || ! rg -q '^\.cm-live-callout' "$callout_styles"; then
  print -u2 "The app-owned Callout stylesheet is missing or incomplete: $callout_styles"
  exit 1
fi

for role in orient cite connect state illustrate quote flag neutral; do
  if ! rg -q "^\\.scholium-callout-$role" "$callout_styles" || \
     ! rg -q "^\\.cm-live-callout-$role" "$callout_styles"; then
    print -u2 "The protected $role Callout is missing from Read or Live Preview."
    exit 1
  fi
done

if ! rg -q '^\.scholium-callout-fold-mark' "$callout_styles" || \
   ! rg -q 'scholium-callout-fold-mark' "$renderer" || \
   ! rg -q 'scholium-callout-signature' "$renderer"; then
  print -u2 "The protected Callout fold or decorative markup contract is incomplete."
  exit 1
fi

if ! rg -q '^\.scholium-callout-cite > header::after' "$callout_styles" || \
   ! rg -q '^\.cm-live-callout-cite\.cm-live-callout-header::after' "$callout_styles"; then
  print -u2 "The protected Source Callout divider is missing from Read or Live Preview."
  exit 1
fi

if ! rg -q 'font-size: 12pt' "$editor_styles" || \
   ! rg -q 'font-size: 12pt' "$read_styles" || \
   ! rg -q '\.cm-live-h1 \{ font-size: 150%' "$editor_styles" || \
   ! rg -q 'h1 \{ font-size: 150%' "$read_styles" || \
   ! rg -q '\.scholium-callout-body' "$callout_styles" || \
   ! rg -q 'font-size: 100%' "$callout_styles"; then
  print -u2 "The normalized document typography baseline is missing or incomplete."
  exit 1
fi

"$repo_root/Tools/Scripts/run-editor-toolchain.sh" --output "$temporary" --test

if ! cmp -s "$temporary" "$committed"; then
  print -u2 "The committed CodeMirror bundle is stale. Run Tools/Scripts/build-editor.sh and commit the result."
  exit 1
fi

print "CodeMirror bundle is reproducible and current."
