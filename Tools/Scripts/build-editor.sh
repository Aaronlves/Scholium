#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
OUTPUT="$ROOT/Scholium/Resources/Editor/editor.bundle.js"
READER_OUTPUT="$ROOT/Scholium/Resources/Editor/reader.bundle.js"
MATH_OUTPUT="$ROOT/Scholium/Resources/Editor/math.bundle.js"
PELE_OUTPUT="$ROOT/Scholium/Resources/Editor/pele.bundle.js"
PELE_NOTICES_OUTPUT="$ROOT/Tools/Packaging/Licenses/Pele-NOTICES.txt"
STREAMING_OUTPUT="$ROOT/Scholium/Resources/Editor/chat-streaming-markdown.bundle.js"
STREAMING_NOTICES_OUTPUT="$ROOT/Tools/Packaging/Licenses/Remend-NOTICE.txt"
ASSET_OUTPUT="$ROOT/Scholium/Resources/Editor"

"$ROOT/Tools/Scripts/run-editor-toolchain.sh" \
  --output "$OUTPUT" \
  --reader-output "$READER_OUTPUT" \
  --math-output "$MATH_OUTPUT" \
  --pele-output "$PELE_OUTPUT" \
  --pele-notices-output "$PELE_NOTICES_OUTPUT" \
  --streaming-output "$STREAMING_OUTPUT" \
  --streaming-notices-output "$STREAMING_NOTICES_OUTPUT" \
  --math-assets "$ASSET_OUTPUT"

echo "Built the locked CodeMirror, Read, streaming Markdown, KaTeX, and Pele resources."
