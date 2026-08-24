#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
OUTPUT="$ROOT/Scholium/Resources/Editor/editor.bundle.js"
READER_OUTPUT="$ROOT/Scholium/Resources/Editor/reader.bundle.js"
MATH_OUTPUT="$ROOT/Scholium/Resources/Editor/math.bundle.js"
MERMAID_OUTPUT="$ROOT/Scholium/Resources/Editor/mermaid.bundle.js"
MERMAID_NOTICES_OUTPUT="$ROOT/Tools/Packaging/Licenses/Mermaid-and-transitive-NOTICES.txt"
ASSET_OUTPUT="$ROOT/Scholium/Resources/Editor"

"$ROOT/Tools/Scripts/run-editor-toolchain.sh" \
  --output "$OUTPUT" \
  --reader-output "$READER_OUTPUT" \
  --math-output "$MATH_OUTPUT" \
  --mermaid-output "$MERMAID_OUTPUT" \
  --mermaid-notices-output "$MERMAID_NOTICES_OUTPUT" \
  --math-assets "$ASSET_OUTPUT"

echo "Built the locked CodeMirror, Read, KaTeX, and Mermaid document resources."
