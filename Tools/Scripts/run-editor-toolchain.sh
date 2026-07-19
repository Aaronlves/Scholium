#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
source_dir="$repo_root/WebEditor"
run_tests=false
output=""

usage() {
  print -u2 "Usage: $0 --output <absolute-path> [--test]"
  exit 64
}

while (( $# > 0 )); do
  case "$1" in
    --output)
      (( $# >= 2 )) || usage
      output="$2"
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
[[ -d "${output:h}" ]] || {
  print -u2 "The editor bundle output directory does not exist: ${output:h}"
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
