#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
EDITOR_SOURCE="$ROOT/WebEditor"

cd "$EDITOR_SOURCE"
npm ci
npm run typecheck
npm run build

echo "Built Scholium/Resources/Editor/editor.bundle.js from the locked editor sources."
