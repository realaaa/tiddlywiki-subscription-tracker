#!/usr/bin/env bash
# Plugin build smoke test. Verifies the plugin packages cleanly into a
# drag-drop import bundle: a 1-element JSON array containing the plugin
# tiddler with its shadow tiddlers stringified into the `text` field.

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
    --rendertiddler '$:/core/templates/exporters/JsonFile' subscription-tracker.json application/json "" exportFilter "[[$PLUGIN_TITLE]]" >/dev/null

if [[ ! -s "$OUT_DIR/subscription-tracker.json" ]]; then
    echo "FAIL: plugin JSON not produced or empty"
    exit 1
fi

# Confirm the JSON is a 1-element array containing the plugin tiddler with
# its inner payload stringified into the `text` field (drag-drop import shape).
python3 -c "
import json, sys
data = json.load(open('$OUT_DIR/subscription-tracker.json'))
if not isinstance(data, list) or len(data) != 1:
    print('FAIL: dist JSON must be a 1-element array, got', type(data).__name__)
    sys.exit(1)
plugin = data[0]
if plugin.get('title') != '$PLUGIN_TITLE':
    print('FAIL: wrong plugin title:', plugin.get('title'))
    sys.exit(1)
inner = json.loads(plugin.get('text') or '{}')
if not inner.get('tiddlers'):
    print('FAIL: plugin text field has no inner tiddlers')
    sys.exit(1)
print('PASS: plugin builds cleanly (' + str(len(inner['tiddlers'])) + ' shadow tiddlers)')
"
