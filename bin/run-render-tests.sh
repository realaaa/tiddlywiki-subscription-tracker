#!/usr/bin/env bash
# Render-test runner. For each fixture in tests/render/, render via tiddlywiki
# and grep for the expected substring listed in tests/render/expectations.txt.
#
# expectations.txt format (one per line, tab-separated):
#   <fixture-tiddler-title><TAB><expected-substring>

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIKI="$REPO_ROOT/tests/wiki"
EXPECT="$REPO_ROOT/tests/render/expectations.txt"
PLUGIN_PATH="$REPO_ROOT/plugins"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if [[ ! -f "$EXPECT" ]]; then
    echo "ERROR: $EXPECT not found"
    exit 2
fi

# Stage all fixture .tid files into the test wiki's tiddlers folder for this run.
# We restore the empty state at the end via the trap.
STAGE_DIR="$WIKI/tiddlers"
STAGED=()
for f in "$REPO_ROOT"/tests/render/*.tid; do
    [[ -f "$f" ]] || continue
    cp "$f" "$STAGE_DIR/"
    STAGED+=("$STAGE_DIR/$(basename "$f")")
done
trap 'rm -rf "$TMPDIR"; for f in "${STAGED[@]:-}"; do rm -f "$f"; done' EXIT

passed=0
failed=0
while IFS=$'\t' read -r title expected; do
    [[ -z "${title:-}" || "$title" == "#"* ]] && continue
    out_file="$TMPDIR/${title//[\/$:]/_}.html"
    TIDDLYWIKI_PLUGIN_PATH="$PLUGIN_PATH" \
        tiddlywiki "$WIKI" \
        --output "$TMPDIR" \
        --rendertiddler "$title" "$(basename "$out_file")" "text/html" >/dev/null 2>&1
    if grep -q -- "$expected" "$out_file"; then
        echo "PASS: $title"
        passed=$((passed + 1))
    else
        echo "FAIL: $title"
        echo "  expected substring: $expected"
        echo "  actual output:"
        sed 's/^/    /' "$out_file" | head -20
        failed=$((failed + 1))
    fi
done < "$EXPECT"

echo
echo "Results: $passed passed, $failed failed"
[[ $failed -eq 0 ]]
