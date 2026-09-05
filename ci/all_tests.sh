#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

ROC_BIN="${ROC:-roc}"

if [[ "$ROC_BIN" == */* ]]; then
    ROC_BIN="$(cd "$(dirname "$ROC_BIN")" && pwd)/$(basename "$ROC_BIN")"
fi

if [ -n "${ROC_TIME_TMPDIR:-}" ]; then
    tmp_base="$ROC_TIME_TMPDIR"
else
    tmp_base="$root_dir/.roc-time-tmp"
fi
export ROC_TIME_TMPDIR="$tmp_base"
export ROC="$ROC_BIN"

tmp_dir="$tmp_base/roc-time-ci"
docs_dir="$tmp_dir/docs"
bundle_dir="$tmp_dir/bundle"

rm -rf "$tmp_dir"
mkdir -p "$docs_dir" "$bundle_dir"

echo "$("$ROC_BIN" version)"

echo ""
echo "Checking package..."
"$ROC_BIN" check package/main.roc

echo ""
echo "Running package tests..."
for module in package/*.roc; do
    if [ "$(basename "$module")" != "main.roc" ]; then
        "$ROC_BIN" test "$module"
    fi
done

echo ""
echo "Generating package docs..."
"$ROC_BIN" docs package/main.roc --output="$docs_dir"

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
        echo ""
        echo "Skipping package bundling on Windows."
        exit 0
        ;;
esac

echo ""
echo "Bundling package..."
BUNDLE_OUTPUT=$(scripts/bundle.sh --output-dir "$bundle_dir" 2>&1)
echo "$BUNDLE_OUTPUT"
BUNDLE_PATH=$(echo "$BUNDLE_OUTPUT" | grep "^Created:" | awk '{print $2}')

if [ -z "$BUNDLE_PATH" ]; then
    echo "Error: could not extract bundle path from roc bundle output"
    exit 1
fi

echo ""
echo "Testing examples against localhost bundle..."
python3 ci/test_bundle_examples.py --bundle-path "$BUNDLE_PATH"
