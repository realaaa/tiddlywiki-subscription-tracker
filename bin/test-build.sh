#!/usr/bin/env bash
# Plugin build smoke test. Verifies the plugin packages cleanly into a
# single shadow-tiddler JSON via the standard --savetiddler mechanism.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIKI="$REPO_ROOT/tests/wiki"
PLUGIN_PATH="$REPO_ROOT/plugins"
PLUGIN_TITLE='$:/plugins/realaaa/subscription-tracker'
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

TIDDLYWIKI_PLUGIN_PATH="$PLUGIN_PATH" \
    tiddlywiki "$WIKI" \
    --output "$OUT_DIR" \
    --savetiddler "$PLUGIN_TITLE" subscription-tracker.json >/dev/null

if [[ ! -s "$OUT_DIR/subscription-tracker.json" ]]; then
    echo "FAIL: plugin JSON not produced or empty"
    exit 1
fi

# Confirm the JSON is valid and has the expected title
python3 -c "
import json, sys
data = json.load(open('$OUT_DIR/subscription-tracker.json'))
title = data.get('title') or (data.get('tiddlers', {}) and list(data['tiddlers'].keys())[0]) or ''
if '$PLUGIN_TITLE' not in str(data):
    print('FAIL: plugin title not found in JSON')
    sys.exit(1)
print('PASS: plugin builds cleanly')
"
