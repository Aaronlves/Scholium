#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
OUTPUT="$ROOT/Scholium/Resources/Editor/editor.bundle.js"

"$ROOT/Tools/Scripts/run-editor-toolchain.sh" --output "$OUTPUT"

echo "Built Scholium/Resources/Editor/editor.bundle.js from the locked editor sources."
