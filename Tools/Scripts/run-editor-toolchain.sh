#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
source_dir="$repo_root/WebEditor"
run_tests=false
output=""
math_output=""
mermaid_output=""
mermaid_notices_output=""
math_assets=""

usage() {
  print -u2 "Usage: $0 --output <absolute-path> --math-output <absolute-path> --mermaid-output <absolute-path> --mermaid-notices-output <absolute-path> --math-assets <absolute-directory> [--test]"
  exit 64
}

while (( $# > 0 )); do
  case "$1" in
    --output)
      (( $# >= 2 )) || usage
      output="$2"
      shift 2
      ;;
    --math-output)
      (( $# >= 2 )) || usage
      math_output="$2"
      shift 2
      ;;
    --mermaid-output)
      (( $# >= 2 )) || usage
      mermaid_output="$2"
      shift 2
      ;;
    --mermaid-notices-output)
      (( $# >= 2 )) || usage
      mermaid_notices_output="$2"
      shift 2
      ;;
    --math-assets)
      (( $# >= 2 )) || usage
      math_assets="$2"
      shift 2
      ;;
    --test)
      run_tests=true
      shift
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$output" && "$output" == /* ]] || usage
[[ -n "$math_output" && "$math_output" == /* ]] || usage
[[ -n "$mermaid_output" && "$mermaid_output" == /* ]] || usage
[[ -n "$mermaid_notices_output" && "$mermaid_notices_output" == /* ]] || usage
[[ -n "$math_assets" && "$math_assets" == /* ]] || usage
[[ -d "${output:h}" ]] || {
  print -u2 "The editor bundle output directory does not exist: ${output:h}"
  exit 66
}
[[ -d "${math_output:h}" ]] || {
  print -u2 "The mathematics bundle output directory does not exist: ${math_output:h}"
  exit 66
}
[[ -d "${mermaid_output:h}" ]] || {
  print -u2 "The Mermaid bundle output directory does not exist: ${mermaid_output:h}"
  exit 66
}
[[ -d "${mermaid_notices_output:h}" ]] || {
  print -u2 "The Mermaid notice output directory does not exist: ${mermaid_notices_output:h}"
  exit 66
}
[[ -d "$math_assets" ]] || {
  print -u2 "The mathematics asset output directory does not exist: $math_assets"
  exit 66
}

if [[ -e "$source_dir/node_modules" ]]; then
  print -u2 "Refusing to use in-worktree WebEditor/node_modules. Remove it and rerun the repository editor script; dependencies are installed in temporary storage."
  exit 65
fi

stage_root="${repo_root}/.build/editor-toolchain-$$"
stage="$stage_root/WebEditor"
trap 'rm -rf "$stage_root"' EXIT INT TERM

rm -rf "$stage_root"
mkdir -p "$stage"

rsync -a --delete \
  --exclude '.DS_Store' \
  --exclude 'node_modules' \
  "$source_dir/" "$stage/"

if $run_tests; then
  fixture_dir="$stage_root/Tests/ScholiumContractsTests/Fixtures"
  mkdir -p "$fixture_dir"
  cp "$repo_root/Tests/ScholiumContractsTests/Fixtures/semantic-parity-fixtures.json" "$fixture_dir/"
  cp "$repo_root/Tests/ScholiumContractsTests/Fixtures/base-syntax-parity-fixtures.json" "$fixture_dir/"
fi

cd "$stage"
npm ci --ignore-scripts
npm run typecheck
if $run_tests; then
  npm test
fi

./node_modules/.bin/esbuild editor.ts \
  --bundle \
  --format=iife \
  --platform=browser \
  --target=safari17 \
  --outfile="$output"

./node_modules/.bin/esbuild math-runtime.ts \
  --bundle \
  --format=iife \
  --platform=browser \
  --target=safari17 \
  --outfile="$math_output"

mermaid_metafile="$stage/.build/mermaid-metafile.json"
mkdir -p "${mermaid_metafile:h}"
./node_modules/.bin/esbuild mermaid-runtime.ts \
  --bundle \
  --minify \
  --format=iife \
  --platform=browser \
  --target=safari17 \
  --metafile="$mermaid_metafile" \
  --outfile="$mermaid_output"
node generate-mermaid-notices.mjs "$mermaid_metafile" "$mermaid_notices_output"

cp node_modules/katex/dist/katex.min.css "$math_assets/katex.min.css"
find "$math_assets" -maxdepth 1 -type f -name 'KaTeX_*.woff2' -delete
cp node_modules/katex/dist/fonts/KaTeX_*.woff2 "$math_assets/"
