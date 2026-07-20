#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
OUTPUT="$ROOT/Scholium/Resources/Editor/editor.bundle.js"
MATH_OUTPUT="$ROOT/Scholium/Resources/Editor/math.bundle.js"
ASSET_OUTPUT="$ROOT/Scholium/Resources/Editor"

"$ROOT/Tools/Scripts/run-editor-toolchain.sh" \
  --output "$OUTPUT" \
  --math-output "$MATH_OUTPUT" \
  --math-assets "$ASSET_OUTPUT"

echo "Built the locked CodeMirror and shared KaTeX editor resources."
