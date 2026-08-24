#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
committed="$repo_root/Scholium/Resources/Editor/editor.bundle.js"
committed_reader="$repo_root/Scholium/Resources/Editor/reader.bundle.js"
callout_styles="$repo_root/Scholium/Resources/Editor/callouts.css"
table_styles="$repo_root/Scholium/Resources/Editor/tables.css"
footnote_styles="$repo_root/Scholium/Resources/Editor/footnotes.css"
editor_styles="$repo_root/Scholium/Resources/Editor/editor.css"
read_styles="$repo_root/Scholium/Views/Note/SafeMarkdownReadWebView.swift"
design_system="$repo_root/Scholium/UI/Foundation/ScholiumDesignSystem.swift"
renderer="$repo_root/ScholiumContracts/SafeMarkdownRenderer.swift"
live_callouts="$repo_root/WebEditor/live-structured-block-projections.ts"
committed_math="$repo_root/Scholium/Resources/Editor/math.bundle.js"
committed_math_css="$repo_root/Scholium/Resources/Editor/katex.min.css"
committed_mermaid="$repo_root/Scholium/Resources/Editor/mermaid.bundle.js"
committed_mermaid_css="$repo_root/Scholium/Resources/Editor/mermaid.css"
committed_mermaid_notices="$repo_root/Tools/Packaging/Licenses/Mermaid-and-transitive-NOTICES.txt"
temporary_root="$repo_root/.build/editor-verification-$$"
temporary="$temporary_root/editor.bundle.js"
temporary_reader="$temporary_root/reader.bundle.js"
temporary_math="$temporary_root/math.bundle.js"
temporary_mermaid="$temporary_root/mermaid.bundle.js"
temporary_mermaid_notices="$temporary_root/Mermaid-and-transitive-NOTICES.txt"
trap 'rm -rf "$temporary_root"' EXIT INT TERM
rm -rf "$temporary_root"
mkdir -p "$temporary_root"

if [[ ! -s "$callout_styles" ]] || \
   ! rg -q '^\.scholium-callout' "$callout_styles" || \
   ! rg -q '^\.cm-live-callout-widget' "$editor_styles" || \
   ! rg -q 'callout\.classList\.add\("cm-live-callout-widget"\)' "$live_callouts"; then
  print -u2 "The app-owned Callout stylesheet is missing or incomplete: $callout_styles"
  exit 1
fi

if [[ ! -s "$table_styles" ]] || \
   ! rg -q '^\.scholium-table-scroll' "$table_styles" || \
   ! rg -q '^\.scholium-table th' "$table_styles" || \
   ! rg -q '^\.cm-live-table-widget' "$table_styles"; then
  print -u2 "The shared semantic table stylesheet is missing or incomplete: $table_styles"
  exit 1
fi

if [[ ! -s "$footnote_styles" ]] || \
   ! rg -q '^\.footnote-reference' "$footnote_styles" || \
   ! rg -q '^\.footnotes' "$footnote_styles" || \
   ! rg -q '^\.cm-live-footnote-reference-widget' "$footnote_styles" || \
   rg -q '^\.cm-live-footnotes-widget' "$footnote_styles"; then
  print -u2 "The shared semantic footnote stylesheet is missing or incomplete: $footnote_styles"
  exit 1
fi

if [[ ! -s "$committed_mermaid_css" ]] || \
   ! rg -q '^\.scholium-mermaid-output' "$committed_mermaid_css" || \
   ! rg -q '^\.cm-live-mermaid-slot' "$committed_mermaid_css"; then
  print -u2 "The shared Mermaid stylesheet is missing or incomplete: $committed_mermaid_css"
  exit 1
fi
if [[ ! -s "$committed_mermaid_notices" ]]; then
  print -u2 "The bundled Mermaid runtime notices are missing: $committed_mermaid_notices"
  exit 1
fi

for role in orient cite connect state illustrate quote flag neutral; do
  if ! rg -q "^\\.scholium-callout-$role" "$callout_styles"; then
    print -u2 "The protected shared $role Callout presentation is missing."
    exit 1
  fi
done

if ! rg -q '^\.scholium-callout-fold-mark' "$callout_styles" || \
   ! rg -q 'scholium-callout-fold-mark' "$renderer" || \
   ! rg -q 'scholium-callout-signature' "$renderer"; then
  print -u2 "The protected Callout fold or compatibility markup contract is incomplete."
  exit 1
fi

if rg -q '^\.cm-live-callout-(orient|cite|connect|state|illustrate|quote|flag|neutral)' "$callout_styles" || \
   ! rg -q '^\.scholium-callout-role,$' "$callout_styles" || \
   ! rg -q '^\.scholium-callout-title \{' "$callout_styles" || \
   ! rg -q '^\.scholium-callout-cite \.scholium-callout-content > p' "$callout_styles" || \
   ! rg -q '^\.scholium-callout-quote \.scholium-callout-quotation' "$callout_styles"; then
  print -u2 "The shared typographic Callout contract is incomplete or duplicated."
  exit 1
fi

if ! rg -q -- '--scholium-document-prose-font-size:.*body\.fontSizePoints' "$design_system" || \
   ! rg -q 'font-size: var\(--scholium-document-prose-font-size\)' "$editor_styles" || \
   ! rg -q 'font-size: var\(--scholium-document-prose-font-size\)' "$read_styles" || \
   ! rg -U -q '^[[:space:]]*\.scholium-document h1,\n[[:space:]]*\.scholium-live-mode \.cm-live-h1 \{[^}]*font-size:' "$design_system" || \
   rg -U -q '^\.cm-live-h[1-6].*\{[^}]*font-(size|weight):' "$editor_styles" || \
   ! rg -q '\.scholium-callout-body' "$callout_styles" || \
   ! rg -q 'font-size: 100%' "$callout_styles"; then
  print -u2 "The shared document typography roles are missing or incomplete."
  exit 1
fi

"$repo_root/Tools/Scripts/run-editor-toolchain.sh" \
  --output "$temporary" \
  --reader-output "$temporary_reader" \
  --math-output "$temporary_math" \
  --mermaid-output "$temporary_mermaid" \
  --mermaid-notices-output "$temporary_mermaid_notices" \
  --math-assets "$temporary_root" \
  --test

if ! cmp -s "$temporary" "$committed"; then
  print -u2 "The committed CodeMirror bundle is stale. Run Tools/Scripts/build-editor.sh and commit the result."
  exit 1
fi

if ! cmp -s "$temporary_reader" "$committed_reader"; then
  print -u2 "The committed Read bundle is stale. Run Tools/Scripts/build-editor.sh and commit the result."
  exit 1
fi

if ! cmp -s "$temporary_mermaid" "$committed_mermaid"; then
  print -u2 "The committed shared Mermaid bundle is stale. Run Tools/Scripts/build-editor.sh and commit the result."
  exit 1
fi

if ! cmp -s "$temporary_mermaid_notices" "$committed_mermaid_notices"; then
  print -u2 "The committed Mermaid runtime notices are stale. Run Tools/Scripts/build-editor.sh and commit the result."
  exit 1
fi

if ! cmp -s "$temporary_math" "$committed_math"; then
  print -u2 "The committed shared mathematics bundle is stale. Run Tools/Scripts/build-editor.sh and commit the result."
  exit 1
fi

if ! cmp -s "$temporary_root/katex.min.css" "$committed_math_css"; then
  print -u2 "The committed KaTeX stylesheet is stale. Run Tools/Scripts/build-editor.sh and commit the result."
  exit 1
fi

committed_fonts=("$repo_root"/Scholium/Resources/Editor/KaTeX_*.woff2(N))
temporary_fonts=("$temporary_root"/KaTeX_*.woff2(N))
if (( ${#committed_fonts} != ${#temporary_fonts} )); then
  print -u2 "The committed KaTeX font set is incomplete. Run Tools/Scripts/build-editor.sh and commit the result."
  exit 1
fi
for font in "${temporary_fonts[@]}"; do
  committed_font="$repo_root/Scholium/Resources/Editor/${font:t}"
  if ! cmp -s "$font" "$committed_font"; then
    print -u2 "The committed KaTeX font is stale: ${font:t}"
    exit 1
  fi
done

print "CodeMirror, Read, and shared document resources are reproducible and current."
