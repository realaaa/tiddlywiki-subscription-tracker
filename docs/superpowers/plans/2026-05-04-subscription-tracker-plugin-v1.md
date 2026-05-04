# Subscription Tracker Plugin v1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v1 of `$:/plugins/realaaa/subscription-tracker` — a vanilla, dependency-free TiddlyWiki 5.4 plugin that turns `subscriptions`-tagged tiddlers into a Notion-style table with multi-currency math, trial tracking, render-time auto-rolled renewal dates, and a structured editor.

**Architecture:** ~7 shadow tiddlers under `plugins/realaaa/subscription-tracker/` — pure WikiText + CSS + JSON, zero JavaScript, zero external plugin dependencies. The plugin owns *views and helpers*; subscription tiddlers themselves are user-owned. Tested via render-fixture HTML grep + manual test plan + plugin build smoke.

**Tech Stack:** TiddlyWiki 5.4.0+ (Node mode), WikiText (`\function`, `\procedure`, filter math), CSS, JSON data tiddlers, bash test runners.

**Spec:** [`docs/superpowers/specs/2026-05-04-subscription-tracker-plugin-design.md`](../specs/2026-05-04-subscription-tracker-plugin-design.md)

---

## Repository layout target

```
tiddlywiki-subscription-tracker/
├── bin/
│   ├── run-render-tests.sh      ← bash render-test runner (Phase 0)
│   └── test-build.sh            ← plugin build smoke test (Phase 9)
├── plugins/
│   └── realaaa/
│       └── subscription-tracker/
│           ├── plugin.info
│           ├── readme.tid
│           ├── styles.tid
│           ├── macros.tid
│           ├── config/
│           │   ├── settings.tid
│           │   └── rates.json
│           ├── templates/
│           │   └── edit.tid
│           └── views/
│               └── main.tid
├── tests/
│   ├── wiki/                     ← bare TW node-mode wiki for testing
│   │   ├── tiddlywiki.info
│   │   └── tiddlers/             (kept empty — fixtures loaded at render time)
│   ├── render/                   ← per-function render-test fixtures
│   │   └── expectations.txt      (sidecar: lines of `fixture-name<TAB>expected-substring`)
│   ├── fixtures/                 ← manual-test fixture tiddlers
│   └── test-plan.md
└── docs/
    └── superpowers/
        ├── specs/2026-05-04-subscription-tracker-plugin-design.md
        └── plans/2026-05-04-subscription-tracker-plugin-v1.md  ← this file
```

## Testing approach

Three layers, listed by automation level:

1. **Render fixtures (semi-automated).** Each `\function` and `\procedure` gets a small fixture tiddler that calls it with known inputs and produces a known string in its body. The runner `bin/run-render-tests.sh` invokes `tiddlywiki tests/wiki --render '[[<fixture>]]' '<fixture>.html' 'text/html'` for each fixture and `grep`s the output for the expected substring. Fail = exit non-zero. This is our "TDD" loop: write fixture → run runner (red) → implement function → run runner (green) → commit.

2. **Manual test plan (`tests/test-plan.md`).** Walks through end-to-end UX scenarios using the manual fixtures. Run after build before release.

3. **Build smoke (`bin/test-build.sh`).** Confirms the plugin packages cleanly via `tiddlywiki --build plugin`.

---

## Phase 0 — Test infrastructure

### Task 0.1: Create the bare test wiki

**Files:**
- Create: `tests/wiki/tiddlywiki.info`
- Create: `tests/wiki/.gitkeep` for `tests/wiki/tiddlers/` (empty tiddlers folder so node-tw is happy)

- [ ] **Step 1: Create the wiki info file**

`tests/wiki/tiddlywiki.info`:
```json
{
    "description": "Test wiki for subscription-tracker plugin development",
    "plugins": [
        "tiddlywiki/filesystem",
        "tiddlywiki/tiddlyweb"
    ],
    "themes": [
        "tiddlywiki/vanilla",
        "tiddlywiki/snowwhite"
    ],
    "includeWikis": [],
    "build": {
        "plugin": [
            "--rendertiddler",
            "$:/core/save/all-external-js",
            "build/index.html",
            "text/plain"
        ]
    }
}
```

The plugin path is added later via the `TIDDLYWIKI_PLUGIN_PATH` env var, not hardcoded here — this keeps the test wiki portable.

- [ ] **Step 2: Create the empty tiddlers folder marker**

```bash
mkdir -p tests/wiki/tiddlers
touch tests/wiki/tiddlers/.gitkeep
```

- [ ] **Step 3: Verify the test wiki boots**

```bash
TIDDLYWIKI_PLUGIN_PATH=plugins tiddlywiki tests/wiki --version
```
Expected: prints a TW version string ≥ `5.4.0`. If it errors with "TiddlyWiki not found," install it: `npm install -g tiddlywiki`.

- [ ] **Step 4: Commit**

```bash
git add tests/wiki/
git commit -m "test: add bare TW node wiki for plugin development"
```

### Task 0.2: Render-test runner script

**Files:**
- Create: `bin/run-render-tests.sh`
- Create: `tests/render/expectations.txt` (empty for now)

- [ ] **Step 1: Write the runner**

`bin/run-render-tests.sh`:
```bash
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
        --rendertiddler "$title" "$(basename "$out_file")" "text/html" \
        --output "$TMPDIR" >/dev/null 2>&1
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
```

- [ ] **Step 2: Make it executable + create the empty expectations file**

```bash
chmod +x bin/run-render-tests.sh
mkdir -p tests/render
touch tests/render/expectations.txt
```

- [ ] **Step 3: Run with empty expectations to verify it doesn't crash**

```bash
bin/run-render-tests.sh
```
Expected output: `Results: 0 passed, 0 failed` and exit 0.

- [ ] **Step 4: Commit**

```bash
git add bin/run-render-tests.sh tests/render/expectations.txt
git commit -m "test: add render-test runner"
```

### Task 0.3: Quick plugin-load smoke test

**Files:**
- Create: `bin/test-build.sh`

- [ ] **Step 1: Write the smoke runner**

`bin/test-build.sh`:
```bash
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
    --savetiddler "$PLUGIN_TITLE" subscription-tracker.json \
    --output "$OUT_DIR" >/dev/null

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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/test-build.sh
```

- [ ] **Step 3: Commit (don't run yet — plugin doesn't exist)**

```bash
git add bin/test-build.sh
git commit -m "test: add plugin build smoke runner"
```

---

## Phase 1 — Plugin shell

### Task 1.1: Plugin manifest

**Files:**
- Create: `plugins/realaaa/subscription-tracker/plugin.info`

- [ ] **Step 1: Write `plugin.info`**

```json
{
    "title": "$:/plugins/realaaa/subscription-tracker",
    "name": "Subscription Tracker",
    "description": "Notion-style subscriptions table with multi-currency totals, trial tracking, and auto-rolled renewal dates",
    "author": "realaaa",
    "version": "0.1.0",
    "core-version": ">=5.4.0",
    "plugin-type": "plugin",
    "list": "readme",
    "source": "https://github.com/realaaa/tiddlywiki-subscription-tracker",
    "license": "MIT"
}
```

- [ ] **Step 2: Verify the plugin is discovered**

```bash
TIDDLYWIKI_PLUGIN_PATH=plugins tiddlywiki tests/wiki --listen --port 0 &
PID=$!
sleep 2
kill $PID 2>/dev/null || true
```
The startup log should mention `$:/plugins/realaaa/subscription-tracker` being loaded. If you see `Error: Plugin not found`, check the folder structure exactly matches `plugins/realaaa/subscription-tracker/plugin.info`.

- [ ] **Step 3: Commit**

```bash
git add plugins/realaaa/subscription-tracker/plugin.info
git commit -m "feat: add plugin manifest"
```

### Task 1.2: Readme tiddler

**Files:**
- Create: `plugins/realaaa/subscription-tracker/readme.tid`

- [ ] **Step 1: Write `readme.tid`**

```
title: $:/plugins/realaaa/subscription-tracker/readme

! Subscription Tracker

A vanilla TiddlyWiki 5.4+ plugin that turns ''subscriptions''-tagged tiddlers into a Notion-style table with:

* multi-currency monthly + yearly totals (single configurable display currency)
* trial tracking with countdown
* render-time auto-rolled renewal dates (no field churn)
* structured editor for adding/editing subscriptions
* status / sort / tag filtering

! Quick start

# Tag any tiddler with `subscriptions` plus 1+ category tag.
# Open the [[Subscriptions]] view tiddler.
# Click ''+ New subscription'' to add one.

! Configuration

* Display currency, tag-name, and renewal-soon threshold: see [[$:/plugins/realaaa/subscription-tracker/config/settings]]
* Currency rates: see [[$:/plugins/realaaa/subscription-tracker/config/rates]]

! License

MIT.
```

- [ ] **Step 2: Verify it renders**

```bash
TIDDLYWIKI_PLUGIN_PATH=plugins tiddlywiki tests/wiki \
    --rendertiddler '$:/plugins/realaaa/subscription-tracker/readme' \
    readme.html text/html --output /tmp/sub-tracker-test
grep -q "Subscription Tracker" /tmp/sub-tracker-test/readme.html && echo PASS || echo FAIL
```
Expected: `PASS`

- [ ] **Step 3: Commit**

```bash
git add plugins/realaaa/subscription-tracker/readme.tid
git commit -m "docs: add plugin readme"
```

### Task 1.3: User-facing `Subscriptions` shadow tiddler

The main view lives at the namespaced title `$:/plugins/realaaa/subscription-tracker/views/main`, which is awkward for users to find. Ship a plain-named user-facing wrapper that transcludes the view.

**Files:**
- Create: `plugins/realaaa/subscription-tracker/Subscriptions.tid`

- [ ] **Step 1: Write the wrapper**

```
title: Subscriptions

{{$:/plugins/realaaa/subscription-tracker/views/main}}
```

This ships as a shadow tiddler. Users can override it (it becomes a regular tiddler the moment they edit it) without losing it on plugin uninstall — but reinstall restores the default. Standard TW pattern.

- [ ] **Step 2: Verify the readme link resolves**

The readme references `[[Subscriptions]]` — that link is now valid. (Render-test deferred until Task 7.1 builds the main view; right now the wrapper transcludes nothing.)

- [ ] **Step 3: Commit**

```bash
git add plugins/realaaa/subscription-tracker/Subscriptions.tid
git commit -m "feat: add user-facing Subscriptions wrapper tiddler"
```

---

## Phase 2 — Config tiddlers

### Task 2.1: Settings tiddler

**Files:**
- Create: `plugins/realaaa/subscription-tracker/config/settings.tid`

- [ ] **Step 1: Write `settings.tid`**

```
title: $:/plugins/realaaa/subscription-tracker/config/settings
display-currency: AUD
tag-name: subscriptions
renewal-soon-days: 14
show-canceled-default: no

This tiddler holds plugin-level configuration. Edit fields directly to customise behaviour.

|!Field |!Default |!Purpose |
|`display-currency` |`AUD` |Currency used for monthly/yearly columns + totals |
|`tag-name` |`subscriptions` |Tag identifying subscription tiddlers |
|`renewal-soon-days` |`14` |Days threshold for the red-highlight on renewal date |
|`show-canceled-default` |`no` |Whether the status filter starts at "include Canceled" |
```

- [ ] **Step 2: Verify the field is readable**

Add a render fixture `tests/render/settings-display-currency.tid`:
```
title: settings-display-currency

{{$:/plugins/realaaa/subscription-tracker/config/settings!!display-currency}}
```

Add expectation to `tests/render/expectations.txt`:
```
settings-display-currency	AUD
```

- [ ] **Step 3: Run render tests**

```bash
bin/run-render-tests.sh
```
Expected: `PASS: settings-display-currency`

- [ ] **Step 4: Commit**

```bash
git add plugins/realaaa/subscription-tracker/config/settings.tid \
        tests/render/settings-display-currency.tid \
        tests/render/expectations.txt
git commit -m "feat: add plugin settings tiddler"
```

### Task 2.2: Rates data tiddler

**Files:**
- Create: `plugins/realaaa/subscription-tracker/config/rates.tid`

Note: shipping as `.tid` with `type: application/json` rather than as a `.json` file — easier for users to find in tiddler search and edit via the UI.

- [ ] **Step 1: Write `rates.tid`**

```
title: $:/plugins/realaaa/subscription-tracker/config/rates
type: application/json

{
    "AUD": 1.0,
    "USD": 1.52,
    "EUR": 1.65,
    "GBP": 1.92
}
```

- [ ] **Step 2: Verify the JSON parses and a key is readable**

Add render fixture `tests/render/rates-aud.tid`:
```
title: rates-aud

{{$:/plugins/realaaa/subscription-tracker/config/rates##AUD}}
```

Add expectation to `tests/render/expectations.txt`:
```
rates-aud	1
```

- [ ] **Step 3: Run render tests**

```bash
bin/run-render-tests.sh
```
Expected: both fixtures pass.

- [ ] **Step 4: Commit**

```bash
git add plugins/realaaa/subscription-tracker/config/rates.tid \
        tests/render/rates-aud.tid \
        tests/render/expectations.txt
git commit -m "feat: add currency rates data tiddler"
```

---

## Phase 3 — Macros: math functions

All math functions go into a single `macros.tid` file, added incrementally. Each task adds one `\function`, one render fixture, one expectation, one commit.

### Task 3.1: `sub.rate(ccy)` — currency rate lookup

**Files:**
- Create: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: `tests/render/macro-rate-aud.tid`, `tests/render/macro-rate-usd.tid`, `tests/render/macro-rate-missing.tid`

- [ ] **Step 1: Write the failing fixtures**

`tests/render/macro-rate-aud.tid`:
```
title: macro-rate-aud

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.rate "AUD">>
```

`tests/render/macro-rate-usd.tid`:
```
title: macro-rate-usd

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.rate "USD">>
```

`tests/render/macro-rate-missing.tid`:
```
title: macro-rate-missing

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

[<<sub.rate "XYZ">>]
```

Append to `tests/render/expectations.txt`:
```
macro-rate-aud	1
macro-rate-usd	1.52
macro-rate-missing	[]
```

The third fixture asserts the macro returns *empty* for an unknown currency (the brackets surround the empty output).

- [ ] **Step 2: Run tests — confirm red**

```bash
bin/run-render-tests.sh
```
Expected: 3 FAILs (macros tiddler doesn't exist).

- [ ] **Step 3: Create `macros.tid` with `sub.rate`**

```
title: $:/plugins/realaaa/subscription-tracker/macros

\function sub.rate(ccy)
[[$:/plugins/realaaa/subscription-tracker/config/rates]getindex<ccy>]
\end
```

- [ ] **Step 4: Run tests — confirm green**

```bash
bin/run-render-tests.sh
```
Expected: `macro-rate-aud`, `macro-rate-usd`, `macro-rate-missing` all PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/macro-rate-*.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.rate() currency lookup"
```

### Task 3.2: `sub.monthly-native()` — amount normalised to monthly in native currency

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: 4 render fixtures (one per billing-frequency)

- [ ] **Step 1: Write fixtures (red)**

`tests/render/macro-monthly-native-monthly.tid`:
```
title: macro-monthly-native-monthly
amount: 13.99
billing-frequency: Monthly

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.monthly-native>>
```

`tests/render/macro-monthly-native-yearly.tid`:
```
title: macro-monthly-native-yearly
amount: 120
billing-frequency: Yearly

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.monthly-native>>
```

`tests/render/macro-monthly-native-quarterly.tid`:
```
title: macro-monthly-native-quarterly
amount: 30
billing-frequency: Quarterly

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.monthly-native>>
```

`tests/render/macro-monthly-native-weekly.tid`:
```
title: macro-monthly-native-weekly
amount: 10
billing-frequency: Weekly

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.monthly-native>>
```

Append to `tests/render/expectations.txt`:
```
macro-monthly-native-monthly	13.99
macro-monthly-native-yearly	10
macro-monthly-native-quarterly	10
macro-monthly-native-weekly	43.3
```

(Weekly: 10 × 4.33 = 43.3.)

- [ ] **Step 2: Run tests — red**

```bash
bin/run-render-tests.sh
```
Expected: 4 FAILs.

- [ ] **Step 3: Add `sub.monthly-native` to `macros.tid`**

Append after `sub.rate`:

```
\function sub.monthly-native()
[get[billing-frequency]match[Monthly]] :then[get[amount]]
[get[billing-frequency]match[Yearly]] :then[get[amount]divide[12]]
[get[billing-frequency]match[Quarterly]] :then[get[amount]divide[3]]
[get[billing-frequency]match[Weekly]] :then[get[amount]multiply[4.33]]
\end
```

- [ ] **Step 4: Run tests — green**

```bash
bin/run-render-tests.sh
```
Expected: all 4 monthly-native fixtures PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/macro-monthly-native-*.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.monthly-native() billing-frequency normalisation"
```

### Task 3.3: `sub.monthly-display()` — converted to display currency

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: 3 render fixtures

- [ ] **Step 1: Write fixtures (red)**

`tests/render/macro-monthly-display-aud.tid`:
```
title: macro-monthly-display-aud
amount: 10
billing-frequency: Monthly
currency: AUD

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.monthly-display>>
```

`tests/render/macro-monthly-display-usd.tid`:
```
title: macro-monthly-display-usd
amount: 10
billing-frequency: Monthly
currency: USD

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.monthly-display>>
```

`tests/render/macro-monthly-display-missing-rate.tid`:
```
title: macro-monthly-display-missing-rate
amount: 10
billing-frequency: Monthly
currency: XYZ

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

[<<sub.monthly-display>>]
```

Append to `tests/render/expectations.txt`:
```
macro-monthly-display-aud	10
macro-monthly-display-usd	15.2
macro-monthly-display-missing-rate	[]
```

(USD: 10 × 1.52 = 15.2. Missing rate → empty.)

- [ ] **Step 2: Run tests — red**

```bash
bin/run-render-tests.sh
```
Expected: 3 FAILs.

- [ ] **Step 3: Add `sub.monthly-display` to `macros.tid`**

Append:

```
\function sub.monthly-display()
[<sub.monthly-native>multiply<sub.rate {{!!currency}}>]
\end
```

- [ ] **Step 4: Run tests — green**

```bash
bin/run-render-tests.sh
```

Note: when `sub.rate` returns empty, `multiply` against empty yields empty (that's TW filter math behaviour — multiplying with no operand drops the run). Confirm the missing-rate fixture's bracketed output is `[]`, not `[NaN]`.

- [ ] **Step 5: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/macro-monthly-display-*.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.monthly-display() with rate conversion"
```

### Task 3.4: `sub.yearly-display()` — yearly cost in display currency

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: 2 render fixtures

- [ ] **Step 1: Write fixtures (red)**

`tests/render/macro-yearly-display-aud.tid`:
```
title: macro-yearly-display-aud
amount: 10
billing-frequency: Monthly
currency: AUD

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.yearly-display>>
```

`tests/render/macro-yearly-display-yearly.tid`:
```
title: macro-yearly-display-yearly
amount: 100
billing-frequency: Yearly
currency: AUD

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.yearly-display>>
```

Append:
```
macro-yearly-display-aud	120
macro-yearly-display-yearly	100
```

- [ ] **Step 2: Red**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 3: Implement**

Append to `macros.tid`:

```
\function sub.yearly-display()
[<sub.monthly-display>multiply[12]]
\end
```

- [ ] **Step 4: Green**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/macro-yearly-display-*.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.yearly-display()"
```

### Task 3.5: `sub.next-renewal()` — auto-roll renewal date

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: 4 render fixtures

This is the most algorithmically interesting function. Behaviour:
- If `status=Canceled`: return stored `renewal-date` as-is (don't roll).
- If `renewal-date` is empty: return empty.
- If `renewal-date` is in the future: return as-is.
- If `renewal-date` is in the past and `status≠Canceled`: compute the next future occurrence by adding `billing-frequency`-sized periods.

The "bounded math" approach: compute days-since-stored, divide by period-days, ceiling, multiply back, add to stored date.

Filter math approach (since WikiText doesn't loop): use `daysuntil[]` to get days from today (negative = past), then if negative, add ceiling(|days|/period-days) × period to stored.

The cleanest implementation uses TW's `addsuffix` trick on date components, but that's fragile. Cleaner: compute target as `today + days-until-next-period-boundary`. Concretely, for Monthly: `[get[renewal-date]:then<addmonth-until-future>]` where `addmonth-until-future` rolls forward.

Realistic implementation given filter limitations: derive the period in days, compute how many periods to add, return a date. We use TW's date arithmetic on a numeric `daysuntil` basis since 5.4 supports `daysuntil[]` returning an integer.

Pragmatic design: since exact date math (preserving day-of-month across months with different lengths) is hard in pure WikiText, we implement an **approximate** roll: convert period to days (Monthly=30.44, Quarterly=91.31, Yearly=365.25, Weekly=7) and roll the date forward by N×days to first land in the future. This is good enough for "next renewal date" display purposes — accuracy within a couple days for the common case, drifts a bit for multi-year-old renewals (which are user data hygiene issues regardless).

We need a way to add days to a date in TW filter math. TW has `[<date>days[N]]` for adding/subtracting days. So:
- `period-days` = lookup table by `billing-frequency`
- `days-since` = `-1 × daysuntil(renewal-date)` (positive number)
- `n-periods-to-add` = `ceiling(days-since / period-days)`
- `result` = `renewal-date + n-periods-to-add × period-days` days

WikiText for "add N days to a date": `[<date>format:date[YYYY0MM0DD]]` ⨯ math doesn't work well. Use the date-add operator: `[<date>days<n>]` (5.4 syntax — confirm).

Actually, the cleaner TW idiom is to convert dates to JavaScript timestamps (`format:date[[UTC]YYYY0MM0DD0hh0mm0ss]`) and do math on those, then convert back. But that's verbose.

**Simplification:** Since the spec calls this approximate-by-days math, accept that edge cases (Feb 29 anniversaries) are out of scope. Use the days-based add.

- [ ] **Step 1: Write fixtures (red)**

`tests/render/macro-next-renewal-future.tid`:
```
title: macro-next-renewal-future
status: Active
billing-frequency: Monthly
renewal-date: 20990101000000

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.next-renewal>>
```

`tests/render/macro-next-renewal-canceled.tid`:
```
title: macro-next-renewal-canceled
status: Canceled
billing-frequency: Monthly
renewal-date: 20100101000000

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.next-renewal>>
```

`tests/render/macro-next-renewal-empty.tid`:
```
title: macro-next-renewal-empty
status: Active
billing-frequency: Monthly

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

[<<sub.next-renewal>>]
```

`tests/render/macro-next-renewal-rolled.tid`:
```
title: macro-next-renewal-rolled
status: Active
billing-frequency: Monthly
renewal-date: 20100101000000

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.next-renewal>> :: <$text text={{{ [<sub.next-renewal>compare:date:gt<now>] }}}/>
```

The fourth fixture asserts the rolled date is *greater than now* — using `compare:date:gt<now>` returns the input when true, empty when false. Plus the `<<sub.next-renewal>>` echoes the rolled value.

Append to `tests/render/expectations.txt`:
```
macro-next-renewal-future	20990101
macro-next-renewal-canceled	20100101
macro-next-renewal-empty	[]
macro-next-renewal-rolled	::
```

The fourth fixture's expectation is `::` — we just want both halves to be non-empty (the `::` separator is always present, but if the comparison fails the right side is empty; we'll add a stronger assertion if needed by greppling for a later year).

A cleaner strong assertion: change the fourth expectation after we see actual output.

- [ ] **Step 2: Red**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 3: Implement**

Append to `macros.tid`:

```
\function sub.period-days()
[get[billing-frequency]match[Monthly]] :then[[30.44]]
[get[billing-frequency]match[Yearly]] :then[[365.25]]
[get[billing-frequency]match[Quarterly]] :then[[91.31]]
[get[billing-frequency]match[Weekly]] :then[[7]]
\end

\function sub.next-renewal()
[get[status]match[Canceled]] :then[get[renewal-date]]
[get[renewal-date]is[blank]] :then[[]]
[get[renewal-date]compare:date:gteq<now>] :then[get[renewal-date]]
[get[renewal-date]daysuntil[]multiply[-1]divide<sub.period-days>ceiling[]multiply<sub.period-days>] :map[<__>]
   :map[{{!!renewal-date}}days<__>]
\end
```

The last branch:
1. `daysuntil[]` of stored date returns a negative integer (days in past).
2. `multiply[-1]` flips to positive (how many days ago).
3. `divide<sub.period-days>ceiling[]` = how many full periods we need to add.
4. `multiply<sub.period-days>` = total days to add.
5. `:map[<__>]` chains forward; the variable `<__>` holds the days-to-add.
6. `[{{!!renewal-date}}days<__>]` adds that many days to the original date.

This may need iteration on the exact filter syntax — TW's `:map` substitution semantics can be subtle. If the syntax above doesn't work as written, the fallback is two functions:

```
\function sub.days-to-add()
[get[renewal-date]daysuntil[]multiply[-1]divide<sub.period-days>ceiling[]multiply<sub.period-days>]
\end

\function sub.next-renewal()
[get[status]match[Canceled]] :then[get[renewal-date]]
[get[renewal-date]is[blank]] :then[[]]
[get[renewal-date]compare:date:gteq<now>] :then[get[renewal-date]]
[get[renewal-date]days<sub.days-to-add>]
\end
```

Use the two-function form if `:map[<__>]` chaining behaves unexpectedly.

- [ ] **Step 4: Green**

```bash
bin/run-render-tests.sh
```
Expected: all 4 next-renewal fixtures PASS.

- [ ] **Step 5: Refine the rolled assertion**

After confirming the rolled fixture renders, update its expectation in `tests/render/expectations.txt` to grep for a year ≥ 2026 (i.e. the rolled date is in the future — adjust based on actual output):

```
macro-next-renewal-rolled	202
```

(The `202` substring matches any 2020s+ year — use a tighter substring once you see the actual output.)

- [ ] **Step 6: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/macro-next-renewal-*.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.next-renewal() with auto-roll for past dates"
```

### Task 3.6: `sub.days-until-renewal()` — built on `sub.next-renewal`

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: 2 render fixtures

- [ ] **Step 1: Fixtures (red)**

`tests/render/macro-days-until-future.tid`:
```
title: macro-days-until-future
status: Active
billing-frequency: Monthly
renewal-date: 20990101000000

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.days-until-renewal>>
```

`tests/render/macro-days-until-empty.tid`:
```
title: macro-days-until-empty
status: Active
billing-frequency: Monthly

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

[<<sub.days-until-renewal>>]
```

Append:
```
macro-days-until-future	2
macro-days-until-empty	[]
```

(For 2099, `daysuntil` returns a large positive — we just check it starts with `2` because anything ≥20000 days starts with `2`.)

- [ ] **Step 2: Red**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 3: Implement**

Append to `macros.tid`:

```
\function sub.days-until-renewal()
[<sub.next-renewal>!is[blank]daysuntil[]]
\end
```

- [ ] **Step 4: Green**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/macro-days-until-*.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.days-until-renewal()"
```

### Task 3.7: `sub.is-renewal-soon()` — threshold check against settings

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: 2 render fixtures

- [ ] **Step 1: Fixtures (red)**

`tests/render/macro-soon-yes.tid`:
```
title: macro-soon-yes
status: Active
billing-frequency: Monthly
renewal-date: <%= [[2026-05-10 00:00:00]format:date[[UTC]YYYY0MM0DD0hh0mm0ss]] %>

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

[<<sub.is-renewal-soon>>]
```

That `<%= ... %>` doesn't exist in TW — we need a static date. Use a date 5 days from a known reference. Since fixtures need static content, use a date just inside the threshold relative to the run date:

`tests/render/macro-soon-yes.tid`:
```
title: macro-soon-yes
status: Active
billing-frequency: Monthly
renewal-date: 20260518000000

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

[<<sub.is-renewal-soon>>:yes]
```

`tests/render/macro-soon-no.tid`:
```
title: macro-soon-no
status: Active
billing-frequency: Monthly
renewal-date: 21000101000000

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

[<<sub.is-renewal-soon>>:no]
```

Note: the fixture dates above assume run-date 2026-05-04. If you're running this plan more than a few weeks later, update the "yes" fixture's `renewal-date` to be ~10 days ahead of *your* current date (must be inside the 14-day default threshold).

Append:
```
macro-soon-yes	[202
macro-soon-no	[:no
```

The "yes" fixture: when soon, the function returns the date itself (truthy in filter context); the "no" fixture: empty (filter is empty → just `[:no]`).

- [ ] **Step 2: Red**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 3: Implement**

Append to `macros.tid`:

```
\function sub.is-renewal-soon()
[<sub.days-until-renewal>!is[blank]compare:integer:lteq{$:/plugins/realaaa/subscription-tracker/config/settings!!renewal-soon-days}]
\end
```

Returns the days-until value when soon, empty when not soon.

- [ ] **Step 4: Green**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/macro-soon-*.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.is-renewal-soon()"
```

### Task 3.8: `sub.trial-days-left()` — countdown for Trial subs

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: 3 render fixtures

- [ ] **Step 1: Fixtures (red)**

`tests/render/macro-trial-days-trial.tid`:
```
title: macro-trial-days-trial
status: Trial
trial-ends: 21000101000000

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

[<<sub.trial-days-left>>]
```

`tests/render/macro-trial-days-active.tid`:
```
title: macro-trial-days-active
status: Active
trial-ends: 21000101000000

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

[<<sub.trial-days-left>>]
```

`tests/render/macro-trial-days-no-end.tid`:
```
title: macro-trial-days-no-end
status: Trial

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

[<<sub.trial-days-left>>]
```

Append:
```
macro-trial-days-trial	[2
macro-trial-days-active	[]
macro-trial-days-no-end	[]
```

(Trial: positive days remaining. Non-trial status: empty. Trial without trial-ends: empty — strict error path is rendered by the *procedure* layer, not the function layer.)

- [ ] **Step 2: Red**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 3: Implement**

Append to `macros.tid`:

```
\function sub.trial-days-left()
[get[status]match[Trial]get[trial-ends]!is[blank]daysuntil[]]
\end
```

- [ ] **Step 4: Green**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/macro-trial-days-*.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.trial-days-left()"
```

---

## Phase 4 — Macros: UI procedures

### Task 4.1: `sub.status-pill(status)`

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: 2 render fixtures

- [ ] **Step 1: Fixtures (red)**

`tests/render/proc-status-pill-active.tid`:
```
title: proc-status-pill-active

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.status-pill "Active">>
```

`tests/render/proc-status-pill-canceled.tid`:
```
title: proc-status-pill-canceled

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.status-pill "Canceled">>
```

Append:
```
proc-status-pill-active	sub-status-active
proc-status-pill-canceled	sub-status-canceled
```

We grep for the CSS class — that's all the procedure has to produce. The styling comes later from `styles.tid`.

- [ ] **Step 2: Red**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 3: Implement**

Append to `macros.tid`:

```
\procedure sub.status-pill(status)
<span class={{{ [[sub-pill sub-status-]addsuffix<status>lowercase[]] }}}><$text text=<<status>>/></span>
\end
```

- [ ] **Step 4: Green**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/proc-status-pill-*.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.status-pill procedure"
```

### Task 4.2: `sub.tag-pill(tag)`

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: 1 render fixture

- [ ] **Step 1: Fixture**

`tests/render/proc-tag-pill.tid`:
```
title: proc-tag-pill

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.tag-pill "Entertainment">>
```

Append:
```
proc-tag-pill	sub-tag
```

- [ ] **Step 2: Red**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 3: Implement**

Append to `macros.tid`:

```
\procedure sub.tag-pill(tag)
<span class="sub-pill sub-tag"><$text text=<<tag>>/></span>
\end
```

- [ ] **Step 4: Green**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/proc-tag-pill.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.tag-pill procedure"
```

### Task 4.3: `sub.amount-cell(amount, currency)` — strict on missing rate

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/macros.tid`
- Create: 2 render fixtures

- [ ] **Step 1: Fixtures**

`tests/render/proc-amount-cell-ok.tid`:
```
title: proc-amount-cell-ok

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.amount-cell "9.99" "USD">>
```

`tests/render/proc-amount-cell-bad.tid`:
```
title: proc-amount-cell-bad

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<<sub.amount-cell "9.99" "XYZ">>
```

Append:
```
proc-amount-cell-ok	USD 9.99
proc-amount-cell-bad	sub-error
```

- [ ] **Step 2: Red**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 3: Implement**

Append to `macros.tid`:

```
\procedure sub.amount-cell(amount, currency)
<$list filter="[<sub.rate <currency>>!is[blank]]" variable="_"
       emptyMessage="<span class='sub-error' title='Unknown currency'>⚠ <$text text=<<currency>>/> ?</span>">
<$text text=<<currency>>/> <$text text=<<amount>>/>
</$list>
\end
```

- [ ] **Step 4: Green**

```bash
bin/run-render-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add plugins/realaaa/subscription-tracker/macros.tid \
        tests/render/proc-amount-cell-*.tid \
        tests/render/expectations.txt
git commit -m "feat(macros): add sub.amount-cell with strict missing-rate error"
```

---

## Phase 5 — Styles

### Task 5.1: Plugin stylesheet

**Files:**
- Create: `plugins/realaaa/subscription-tracker/styles.tid`

This is a CSS-only task — no functional test, just a smoke check that the stylesheet loads.

- [ ] **Step 1: Write `styles.tid`**

```
title: $:/plugins/realaaa/subscription-tracker/styles
tags: $:/tags/Stylesheet

/* === Subscription Tracker stylesheet === */

/* Table */
.sub-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.95em;
    margin-top: 1em;
}
.sub-table th,
.sub-table td {
    padding: 8px 12px;
    border-bottom: 1px solid <<colour table-border>>;
    text-align: left;
    vertical-align: middle;
}
.sub-table th {
    background: <<colour table-header-background>>;
    font-weight: 600;
}
.sub-table td.num {
    text-align: right;
    font-variant-numeric: tabular-nums;
}
.sub-table tr:hover {
    background: <<colour table-footer-background>>;
}

/* Pills (status + tags) */
.sub-pill {
    display: inline-block;
    padding: 2px 10px;
    border-radius: 10px;
    font-size: 0.85em;
    margin-right: 4px;
    color: #fff;
}
.sub-status-active   { background: #c2410c; }
.sub-status-canceled { background: #15803d; }
.sub-status-trial    { background: #7e22ce; }
.sub-status-paused   { background: #525252; }
.sub-tag             { background: #b45309; }

/* Renewal-date highlight */
.sub-renewal-soon { color: #dc2626; font-weight: 600; }
.sub-renewal-ok   { color: inherit; }

/* Strict-error glyph */
.sub-error {
    color: #dc2626;
    font-weight: 600;
}

/* Filter bar */
.sub-filter-bar {
    display: flex;
    gap: 12px;
    align-items: center;
    margin: 1em 0;
    flex-wrap: wrap;
}
.sub-filter-bar select {
    padding: 4px 8px;
}

/* Totals bar */
.sub-totals {
    font-size: 1.1em;
    margin: 0.5em 0;
}
.sub-totals strong { font-weight: 600; }

/* Exclusion banner */
.sub-banner {
    padding: 8px 12px;
    background: <<colour message-background>>;
    border-left: 3px solid <<colour message-border>>;
    margin: 0.5em 0;
    font-size: 0.9em;
}
.sub-banner-error {
    background: #fee2e2;
    border-left-color: #dc2626;
}

/* Empty state */
.sub-empty {
    padding: 2em;
    text-align: center;
    color: <<colour muted-foreground>>;
    font-style: italic;
}
```

- [ ] **Step 2: Smoke check — stylesheet is registered**

Add render fixture `tests/render/styles-loaded.tid`:
```
title: styles-loaded

<$list filter="[all[shadows]tag[$:/tags/Stylesheet]] +[search[sub-table]]">
SUBTRACKER-STYLES-PRESENT: <<currentTiddler>>
</$list>
```

Append:
```
styles-loaded	SUBTRACKER-STYLES-PRESENT
```

- [ ] **Step 3: Run tests**

```bash
bin/run-render-tests.sh
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add plugins/realaaa/subscription-tracker/styles.tid \
        tests/render/styles-loaded.tid \
        tests/render/expectations.txt
git commit -m "feat: add plugin stylesheet"
```

---

## Phase 6 — EditTemplate

### Task 6.1: Custom edit form for subscription tiddlers

**Files:**
- Create: `plugins/realaaa/subscription-tracker/templates/edit.tid`

This template is registered into the EditTemplate cascade so it only fires for tiddlers tagged with the configured tag-name.

- [ ] **Step 1: Write `templates/edit.tid`**

```
title: $:/plugins/realaaa/subscription-tracker/templates/edit
tags: $:/tags/EditTemplate
list-before: $:/core/ui/EditTemplate/body

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

<$list filter="[all[current]tags[]] +[contains{$:/plugins/realaaa/subscription-tracker/config/settings!!tag-name}]" variable="_">

<div class="tc-tiddler-edit-section">
<h3>Subscription details</h3>

<table class="sub-edit-form">
<tr>
  <td>''Status''</td>
  <td><$select tiddler=<<currentTiddler>> field="status" default="Active">
        <option value="Active">Active</option>
        <option value="Trial">Trial</option>
        <option value="Paused">Paused</option>
        <option value="Canceled">Canceled</option>
      </$select></td>
</tr>
<tr>
  <td>''Billing frequency''</td>
  <td><$select tiddler=<<currentTiddler>> field="billing-frequency" default="Monthly">
        <option value="Monthly">Monthly</option>
        <option value="Yearly">Yearly</option>
        <option value="Quarterly">Quarterly</option>
        <option value="Weekly">Weekly</option>
      </$select></td>
</tr>
<tr>
  <td>''Amount''</td>
  <td><$edit-text tiddler=<<currentTiddler>> field="amount" tag="input" type="number" step="0.01"/></td>
</tr>
<tr>
  <td>''Currency''</td>
  <td><$select tiddler=<<currentTiddler>> field="currency" default="AUD">
        <$list filter="[[$:/plugins/realaaa/subscription-tracker/config/rates]indexes[]]" variable="ccy">
          <option value=<<ccy>>><<ccy>></option>
        </$list>
      </$select></td>
</tr>
<tr>
  <td>''Renewal date''</td>
  <td><$edit-text tiddler=<<currentTiddler>> field="renewal-date" tag="input" type="date"/></td>
</tr>
<$list filter="[all[current]field:status[Trial]]" variable="_">
<tr>
  <td>''Trial ends''</td>
  <td><$edit-text tiddler=<<currentTiddler>> field="trial-ends" tag="input" type="date"/></td>
</tr>
</$list>
<tr>
  <td>''Vendor URL''</td>
  <td><$edit-text tiddler=<<currentTiddler>> field="vendor-url" tag="input" type="url"/></td>
</tr>
<tr>
  <td>''Cancel URL''</td>
  <td><$edit-text tiddler=<<currentTiddler>> field="cancel-url" tag="input" type="url"/></td>
</tr>
<tr>
  <td>''Payment method''</td>
  <td><$edit-text tiddler=<<currentTiddler>> field="payment-method" tag="input" type="text" placeholder="Visa ••4242"/>
      <small>Last 4 digits only</small></td>
</tr>
</table>
</div>

</$list>
```

- [ ] **Step 2: Render-test the cascade-skip behaviour**

Add render fixture `tests/render/edit-cascade-skip.tid`:
```
title: edit-cascade-skip

This tiddler is NOT tagged subscriptions, so the edit-form section should not render.
```

Append:
```
edit-cascade-skip	NOT tagged subscriptions
```

(The fixture's own body contains "NOT tagged subscriptions," so this just verifies the runner's output captures rendered body — sanity check, not a real assertion of edit-template behaviour.)

The real test is the manual fixture pass in Phase 8 — opening a `subscriptions`-tagged tiddler in edit mode and seeing the form.

- [ ] **Step 3: Run tests**

```bash
bin/run-render-tests.sh
```
Expected: PASS for the new fixture; no regressions.

- [ ] **Step 4: Commit**

```bash
git add plugins/realaaa/subscription-tracker/templates/edit.tid \
        tests/render/edit-cascade-skip.tid \
        tests/render/expectations.txt
git commit -m "feat: add EditTemplate cascade for subscription tiddlers"
```

---

## Phase 7 — Main view

The main view is built in pieces, each piece committed separately.

### Task 7.1: Skeleton + totals bar

**Files:**
- Create: `plugins/realaaa/subscription-tracker/views/main.tid`

- [ ] **Step 1: Write the skeleton with totals only**

```
title: $:/plugins/realaaa/subscription-tracker/views/main

\import [[$:/plugins/realaaa/subscription-tracker/macros]]

\procedure subs.tag-name() {{$:/plugins/realaaa/subscription-tracker/config/settings!!tag-name}}
\procedure subs.display-currency() {{$:/plugins/realaaa/subscription-tracker/config/settings!!display-currency}}

! Subscriptions

<!-- ===== Totals bar ===== -->

<div class="sub-totals">
<$let
    active-filter="[tag<subs.tag-name>!field:status[Canceled]]"
    excluded-rate-filter="[tag<subs.tag-name>!field:status[Canceled]] :filter[<sub.rate {{!!currency}}>is[blank]]"
    total-monthly={{{ [tag<subs.tag-name>!field:status[Canceled]] :filter[<sub.rate {{!!currency}}>!is[blank]] :map[<sub.monthly-display>] +[sum[]fixed[2]] }}}
    total-yearly={{{ [tag<subs.tag-name>!field:status[Canceled]] :filter[<sub.rate {{!!currency}}>!is[blank]] :map[<sub.yearly-display>] +[sum[]fixed[2]] }}}
    active-count={{{ [tag<subs.tag-name>!field:status[Canceled]count[]] }}}
    excluded-rate-count={{{ [tag<subs.tag-name>!field:status[Canceled]] :filter[<sub.rate {{!!currency}}>is[blank]] +[count[]] }}}
>

''<<active-count>> active'' — ''<<subs.display-currency>> <<total-monthly>>/mo'' (~''<<subs.display-currency>> <<total-yearly>>/yr'')

<$list filter="[<excluded-rate-count>compare:integer:gt[0]]" variable="_">
<div class="sub-banner sub-banner-error">
⚠ <<excluded-rate-count>> sub(s) excluded from totals (missing currency rate). [[Fix rates|$:/plugins/realaaa/subscription-tracker/config/rates]]
</div>
</$list>

</$let>
</div>
```

- [ ] **Step 2: Render-test the totals**

Add fixture `tests/render/view-main-empty.tid`:
```
title: view-main-empty

{{$:/plugins/realaaa/subscription-tracker/views/main}}
```

Append:
```
view-main-empty	0 active
```

(With no subscriptions in the test wiki, totals are 0.)

- [ ] **Step 3: Run tests**

```bash
bin/run-render-tests.sh
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add plugins/realaaa/subscription-tracker/views/main.tid \
        tests/render/view-main-empty.tid \
        tests/render/expectations.txt
git commit -m "feat(view): add main view skeleton with totals bar"
```

### Task 7.2: Filter bar + state tiddler defaults

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/views/main.tid`

The state tiddler `$:/state/subscription-tracker/filter` is created lazily — when the user first uses the dropdowns. We don't ship it as a shadow.

- [ ] **Step 1: Append filter bar to `views/main.tid`**

After the totals bar, add:

```

<!-- ===== Filter bar ===== -->

<div class="sub-filter-bar">

<label>Status:
<$select tiddler="$:/state/subscription-tracker/filter" field="status-filter" default="active">
    <option value="active">Active + Trial + Paused</option>
    <option value="all">All (including Canceled)</option>
    <option value="Active">Active only</option>
    <option value="Trial">Trial only</option>
    <option value="Paused">Paused only</option>
    <option value="Canceled">Canceled only</option>
</$select>
</label>

<label>Sort:
<$select tiddler="$:/state/subscription-tracker/filter" field="sort" default="renewal">
    <option value="name">Name</option>
    <option value="renewal">Next renewal</option>
    <option value="monthly-desc">Monthly cost (high→low)</option>
    <option value="yearly-desc">Yearly cost (high→low)</option>
</$select>
</label>

<label>Tag:
<$select tiddler="$:/state/subscription-tracker/filter" field="tag-filter" default="">
    <option value="">All</option>
    <$list filter="[tag<subs.tag-name>tags[]] -[<subs.tag-name>] +[sort[]]" variable="t">
        <option value=<<t>>><<t>></option>
    </$list>
</$select>
</label>

<$button class="tc-btn-invisible">
    <$action-createtiddler $basetitle="Untitled subscription" status="Active" tags=<<subs.tag-name>>>
        <$action-navigate $to=<<createTiddler-title>>/>
    </$action-createtiddler>
    + New subscription
</$button>

</div>
```

The `<$action-createtiddler>` widget creates a new tiddler with `$basetitle="Untitled subscription"` (TW auto-suffixes if a tiddler with that title already exists), sets `status=Active` and tags it with the configured tag-name. The `createTiddler-title` variable is set by `<$action-createtiddler>` for the navigate action to consume.

- [ ] **Step 2: Render-test that filter bar renders**

Update `view-main-empty` expectation in `tests/render/expectations.txt`:

Replace `view-main-empty	0 active` with two lines:
```
view-main-empty	0 active
view-main-empty	+ New subscription
```

(The runner reads each line independently, so we can have multiple expectations for one fixture by repeating the title.)

If the runner only reads first match per title, change one fixture to a separate name. Adjust the runner if needed — current runner does line-by-line, so multiple lines with same title both run. Confirm by reading `bin/run-render-tests.sh`.

- [ ] **Step 3: Run tests**

```bash
bin/run-render-tests.sh
```
Expected: both expectations PASS.

- [ ] **Step 4: Commit**

```bash
git add plugins/realaaa/subscription-tracker/views/main.tid \
        tests/render/expectations.txt
git commit -m "feat(view): add filter bar and + New subscription button"
```

### Task 7.3: Main table — header + body

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/views/main.tid`

This is the central piece: filtered + sorted list of subscription rows.

- [ ] **Step 1: Append the table to `views/main.tid`**

After the filter bar:

```

<!-- ===== Table ===== -->

\function subs.status-filter()
[{$:/state/subscription-tracker/filter!!status-filter}match[active]] :then[[!field:status[Canceled]]]
[{$:/state/subscription-tracker/filter!!status-filter}match[all]] :then[[]]
[{$:/state/subscription-tracker/filter!!status-filter}!match[active]!match[all]addprefix[field:status[]addsuffix[]]]
\end
\function subs.sort-clause()
[{$:/state/subscription-tracker/filter!!sort}match[name]] :then[[sort[title]]]
[{$:/state/subscription-tracker/filter!!sort}match[renewal]] :then[[sortsub:date[<sub.next-renewal>]]]
[{$:/state/subscription-tracker/filter!!sort}match[monthly-desc]] :then[[+[sortsub:number<sub.monthly-display>]reverse[]]]
[{$:/state/subscription-tracker/filter!!sort}match[yearly-desc]] :then[[+[sortsub:number<sub.yearly-display>]reverse[]]]
\end

<!-- The clauses above produce filter-fragment strings; we substitute via filter run interpolation. -->

<$let
    status-clause={{{ [<subs.status-filter>] }}}
    sort-clause={{{ [<subs.sort-clause>] }}}
    tag-clause={{{ [{$:/state/subscription-tracker/filter!!tag-filter}!is[blank]addprefix[tag[]addsuffix[]]] }}}
    row-filter={{{ [[tag[]]addsuffix<subs.tag-name>addsuffix[]]addsuffix<status-clause>addsuffix<tag-clause>addsuffix<sort-clause> }}}
>

<$list filter="[tag<subs.tag-name>] +[count[]]" variable="total">
<$list filter="[<total>compare:integer:eq[0]]" variable="_" emptyMessage="">
<div class="sub-empty">No subscriptions yet. Click ''+ New subscription'' to add one.</div>
</$list>
</$list>

<table class="sub-table">
<thead>
<tr>
    <th>Name</th>
    <th>Status</th>
    <th>Tags</th>
    <th>Billing</th>
    <th>Renewal</th>
    <th class="num">Amount</th>
    <th class="num">Monthly (<<subs.display-currency>>)</th>
    <th class="num">Yearly (<<subs.display-currency>>)</th>
</tr>
</thead>
<tbody>
<$list filter=<<row-filter>> emptyMessage="<tr><td colspan='8' class='sub-empty'>No subscriptions match the current filters.</td></tr>">
<tr>
    <td><$link to=<<currentTiddler>>><<currentTiddler>></$link></td>
    <td><<sub.status-pill {{!!status}}>></td>
    <td>
        <$list filter="[all[current]tags[]] -[<subs.tag-name>]" variable="t">
            <<sub.tag-pill <<t>>>>
        </$list>
    </td>
    <td>{{!!billing-frequency}}</td>
    <td>
        <$list filter="[all[current]get[status]match[Canceled]]" variable="_"
               emptyMessage="<$list filter='[all[current]<sub.next-renewal>!is[blank]]' variable='_' emptyMessage='—'><span class={{{ [<sub.is-renewal-soon>!is[blank]then[sub-renewal-soon]else[sub-renewal-ok]] }}}><$view filter='[<sub.next-renewal>format:date[DDth MMM YYYY]]'/></span></$list>">
            <$list filter="[all[current]get[renewal-date]!is[blank]]" variable="_" emptyMessage="—">
                <$view field="renewal-date" format="date" template="DDth MMM YYYY"/>
            </$list>
        </$list>
    </td>
    <td class="num"><<sub.amount-cell {{!!amount}} {{!!currency}}>></td>
    <td class="num">
        <$list filter="[all[current]<sub.monthly-display>!is[blank]]" variable="_" emptyMessage="—">
            <$text text={{{ [<sub.monthly-display>fixed[2]] }}}/>
        </$list>
    </td>
    <td class="num">
        <$list filter="[all[current]<sub.yearly-display>!is[blank]]" variable="_" emptyMessage="—">
            <$text text={{{ [<sub.yearly-display>fixed[2]] }}}/>
        </$list>
    </td>
</tr>
</$list>
</tbody>
</table>

</$let>
```

The renewal-date cell logic:
- If `status=Canceled` → show stored `renewal-date` as-is (or `—` if blank).
- Otherwise → use `<sub.next-renewal>` (auto-rolled), apply `sub-renewal-soon` class when within threshold.

The filter dynamic-construction (`row-filter`) concatenates fragments at runtime. This is fragile. If the `addprefix`/`addsuffix` chain doesn't construct a valid filter string, the fallback (simpler but less DRY) is to write four explicit `<$list>` blocks inside a `<$switch>` on `status-filter`. If `bin/run-render-tests.sh` shows weird filter behaviour after this task, switch to that fallback.

- [ ] **Step 2: Add a render fixture exercising one row**

Add `tests/render/view-main-with-row.tid`:
```
title: view-main-with-row

The view is rendered against a wiki containing one subscription:
{{$:/plugins/realaaa/subscription-tracker/views/main}}
```

This won't add a real subscription to the test wiki. Instead, ship a one-shot fixture *subscription* tiddler that gets staged like the render fixtures:

`tests/render/_fixture-subscription-Netflix.tid`:
```
title: Netflix
tags: subscriptions Entertainment
status: Active
billing-frequency: Monthly
amount: 13.99
currency: AUD
renewal-date: 21000601000000
```

The leading `_fixture-` prefix is just convention so we can spot it. It's staged into `tests/wiki/tiddlers/` alongside the render-test fixtures by the runner.

Append to `tests/render/expectations.txt`:
```
view-main-with-row	Netflix
view-main-with-row	13.99
view-main-with-row	1 active
```

- [ ] **Step 3: Run tests — green**

```bash
bin/run-render-tests.sh
```

If filter dynamic-construction is broken, you'll see the table render zero rows even though `Netflix` exists. Switch to the fallback `<$switch>`-on-status approach noted above.

- [ ] **Step 4: Commit**

```bash
git add plugins/realaaa/subscription-tracker/views/main.tid \
        tests/render/view-main-*.tid \
        tests/render/_fixture-subscription-Netflix.tid \
        tests/render/expectations.txt
git commit -m "feat(view): add main subscriptions table"
```

### Task 7.4: Strict-error banners (invalid amount, missing trial-ends)

**Files:**
- Modify: `plugins/realaaa/subscription-tracker/views/main.tid`

The missing-rate banner already exists from Task 7.1. Add two more banner branches.

- [ ] **Step 1: Augment the totals-bar `<$let>` with two more counters**

Inside the existing `<$let>` block, add:

```
    excluded-amount-count={{{ [tag<subs.tag-name>!field:status[Canceled]] :filter[get[amount]!is[blank]match:regexp[^-?\d+(\.\d+)?$]] +[count[]subtract<active-count>multiply[-1]] }}}
    trial-no-end-count={{{ [tag<subs.tag-name>field:status[Trial]get[trial-ends]is[blank]] +[count[]] }}}
```

The `excluded-amount-count` derivation: count subs whose amount is a valid number, subtract from active-count, flip sign. (If `match:regexp` isn't available in 5.4, use `is[number]` if the operator exists; otherwise simplify to a separate filter that detects non-numeric amounts.)

After the existing missing-rate banner, append two banners:

```
<$list filter="[<excluded-amount-count>compare:integer:gt[0]]" variable="_">
<div class="sub-banner sub-banner-error">
⚠ <<excluded-amount-count>> sub(s) excluded from totals (invalid amount).
</div>
</$list>

<$list filter="[<trial-no-end-count>compare:integer:gt[0]]" variable="_">
<div class="sub-banner sub-banner-error">
⚠ <<trial-no-end-count>> Trial sub(s) missing trial-ends date.
</div>
</$list>
```

Also add the display-currency-config-error banner:

```
<$list filter="[<sub.rate {{$:/plugins/realaaa/subscription-tracker/config/settings!!display-currency}}>match[1]] +[count[]] :filter[!compare:integer:eq[1]]" variable="_">
<div class="sub-banner sub-banner-error">
⚠ Display currency `{{$:/plugins/realaaa/subscription-tracker/config/settings!!display-currency}}` has no rate, or rate ≠ 1.0. [[Fix in plugin settings|$:/plugins/realaaa/subscription-tracker/config/settings]]
</div>
</$list>
```

- [ ] **Step 2: Add render fixtures**

`tests/render/_fixture-subscription-BadAmount.tid`:
```
title: BadAmount
tags: subscriptions Productivity
status: Active
billing-frequency: Monthly
amount: not-a-number
currency: AUD
renewal-date: 21000601000000
```

`tests/render/_fixture-subscription-TrialNoEnd.tid`:
```
title: TrialNoEnd
tags: subscriptions Entertainment
status: Trial
billing-frequency: Monthly
amount: 9.99
currency: AUD
```

Append to `tests/render/expectations.txt`:
```
view-main-with-row	excluded from totals (invalid amount)
view-main-with-row	Trial sub(s) missing trial-ends
```

- [ ] **Step 3: Run tests — green**

```bash
bin/run-render-tests.sh
```

If the `match:regexp` operator isn't available, fall back to a simpler check: a sub with `amount` blank or with non-numeric content fails the `[get[amount]<convert>...]` chain and produces empty when summed. In that case, the count of excluded-amount subs is harder to compute precisely; ship the banner anyway with a simpler message ("N sub(s) may have excluded amounts") and refine in a later patch.

- [ ] **Step 4: Commit**

```bash
git add plugins/realaaa/subscription-tracker/views/main.tid \
        tests/render/_fixture-subscription-BadAmount.tid \
        tests/render/_fixture-subscription-TrialNoEnd.tid \
        tests/render/expectations.txt
git commit -m "feat(view): add strict-error banners for invalid data"
```

---

## Phase 8 — Manual fixtures + test plan

### Task 8.1: Manual fixture set

**Files:**
- Create: 10 fixture `.tid` files under `tests/fixtures/`

These are *not* render fixtures — they're sample subscription tiddlers a developer drops into a test wiki for manual end-to-end verification.

- [ ] **Step 1: Create the fixtures folder + all 10 files**

`tests/fixtures/Netflix.tid`:
```
title: Netflix
tags: subscriptions Entertainment
status: Active
billing-frequency: Monthly
amount: 13.99
currency: AUD
renewal-date: 21000601000000
vendor-url: https://netflix.com

Happy-path Active monthly AUD subscription.
```

`tests/fixtures/Spotify-USD.tid`:
```
title: Spotify
tags: subscriptions Entertainment
status: Active
billing-frequency: Monthly
amount: 9.99
currency: USD
renewal-date: 21000615000000
vendor-url: https://spotify.com

Tests USD → AUD rate conversion.
```

`tests/fixtures/Adobe.tid`:
```
title: Adobe Creative Cloud
tags: subscriptions Productivity
status: Active
billing-frequency: Yearly
amount: 599
currency: USD
renewal-date: 21010101000000

Tests yearly→monthly math + USD conversion.
```

`tests/fixtures/Notion-Trial.tid`:
```
title: Notion AI Trial
tags: subscriptions Productivity
status: Trial
billing-frequency: Yearly
amount: 96
currency: USD
renewal-date: 21000801000000
trial-ends: 21000515000000

Trial happy path — has trial-ends.
```

`tests/fixtures/BadCurrency.tid`:
```
title: Bitcoin Miner Pro
tags: subscriptions Productivity
status: Active
billing-frequency: Monthly
amount: 50
currency: XYZ
renewal-date: 21000701000000

Strict missing-rate error path. Should appear with ⚠ glyph + excluded from totals + counted in banner.
```

`tests/fixtures/BadAmount.tid`:
```
title: Mystery Charge
tags: subscriptions Productivity
status: Active
billing-frequency: Monthly
amount: oops
currency: AUD
renewal-date: 21000701000000

Invalid amount. Should be excluded from totals + counted in banner.
```

`tests/fixtures/Trial-NoEnd.tid`:
```
title: Adobe Free Trial
tags: subscriptions Productivity
status: Trial
billing-frequency: Monthly
amount: 0
currency: AUD

Strict trial-ends-missing error. Counted in banner; row stays in totals (cost=0 anyway).
```

`tests/fixtures/Old-Renewal.tid`:
```
title: Old Domain Registration
tags: subscriptions Productivity
status: Active
billing-frequency: Yearly
amount: 30
currency: AUD
renewal-date: 20100315000000

Renewal date 16 years in the past. Auto-roll should display next future occurrence.
```

`tests/fixtures/OldCanceled.tid`:
```
title: MoviePass
tags: subscriptions Entertainment
status: Canceled
billing-frequency: Monthly
amount: 9.95
currency: USD
renewal-date: 20180101000000

Canceled with stale renewal-date. Should display as-is (no auto-roll for Canceled).
```

`tests/fixtures/Paused-NoRenewal.tid`:
```
title: Office 365 Personal
tags: subscriptions Productivity
status: Paused
billing-frequency: Yearly
amount: 110
currency: AUD

Paused, no renewal-date. Lenient case: renders `—`, no error.
```

- [ ] **Step 2: Commit**

```bash
git add tests/fixtures/*.tid
git commit -m "test: add 10 manual fixtures covering all v1 behaviours"
```

### Task 8.2: Manual test plan

**Files:**
- Create: `tests/test-plan.md`

- [ ] **Step 1: Write `tests/test-plan.md`**

```markdown
# Manual Test Plan — Subscription Tracker v1

Run this before tagging a release. Estimated time: 15 minutes.

## Setup

1. Build the plugin: `bin/test-build.sh` (or just verify the plugin folder is discovered).
2. Start a fresh TW node wiki with the plugin path set:
   ```bash
   TIDDLYWIKI_PLUGIN_PATH=plugins tiddlywiki tests/wiki --listen --port 8080
   ```
3. Open http://localhost:8080 in your browser.
4. Drop all 10 fixtures from `tests/fixtures/` into the wiki (drag-drop, or copy them into `tests/wiki/tiddlers/` before starting).

## Scenarios

### S1 — Initial render

- [ ] Open the `Subscriptions` view tiddler.
- [ ] Table renders without console errors.
- [ ] Active count, monthly total, yearly total all display sensibly (in AUD).
- [ ] No banners *except* one for `Bitcoin Miner Pro` (missing rate) and one for `Adobe Free Trial` (missing trial-ends) and one for `Mystery Charge` (invalid amount).

### S2 — Pill rendering

- [ ] `Netflix`, `Spotify`, `Adobe Creative Cloud` show ''Active'' (orange pill).
- [ ] `Notion AI Trial` shows ''Trial'' (purple pill).
- [ ] `Office 365 Personal` shows ''Paused'' (grey pill).
- [ ] `MoviePass` shows ''Canceled'' (green pill).
- [ ] Tag pills render (e.g. ''Entertainment'', ''Productivity'').

### S3 — Auto-roll

- [ ] `Old Domain Registration` (renewal stored 2010-03-15) shows a renewal date in the future, on or near March 15 of an upcoming year.
- [ ] `MoviePass` (Canceled, renewal stored 2018-01-01) shows the *original* `2018-01-01` (no auto-roll for Canceled).

### S4 — Renewal-soon highlighting

- [ ] Edit one fixture's `renewal-date` to a date 7 days from today. Save.
- [ ] That row's renewal-date column turns red.
- [ ] Edit it back to a date 30 days from today. Save.
- [ ] The red highlight goes away.

### S5 — Currency conversion

- [ ] `Spotify` (USD 9.99 monthly) shows monthly ≈ AUD 15.18.
- [ ] `Adobe Creative Cloud` (USD 599 yearly) shows monthly ≈ AUD 75.83 and yearly ≈ AUD 910.
- [ ] Open `$:/plugins/realaaa/subscription-tracker/config/settings`. Change `display-currency` from `AUD` to `USD`. Save.
- [ ] Totals + columns re-render in USD. AUD subs now have AUD-to-USD conversion (you'll need to add `AUD: <rate>` to the rates tiddler — confirm the missing-rate banner appears for AUD subs until you do).
- [ ] Restore `display-currency` to `AUD`.

### S6 — Strict errors

- [ ] `Bitcoin Miner Pro` row: amount cell shows ⚠ with `XYZ ?`. Monthly + Yearly cells show `—`. Banner counts +1 missing-rate.
- [ ] `Mystery Charge` row: amount cell shows `?`. Excluded from totals. Banner counts +1 invalid amount.
- [ ] `Adobe Free Trial` row: trial-days-left cell shows ⚠. Banner counts +1 missing trial-ends. Row contributes to totals (cost=0, but still counted as active).

### S7 — Filters

- [ ] Status filter `Active only` → table shows only Active subs (Netflix, Spotify, Adobe, Mystery Charge, Bitcoin Miner Pro, Old Domain).
- [ ] Status filter `Trial only` → only Notion AI Trial + Adobe Free Trial.
- [ ] Status filter `Canceled only` → only MoviePass.
- [ ] Status filter `All (including Canceled)` → all rows visible. Totals exclude Canceled.
- [ ] Tag filter `Entertainment` → only Entertainment-tagged subs visible.
- [ ] Tag filter `(All)` → restored.

### S8 — Sort

- [ ] Sort = `Name` → alphabetical.
- [ ] Sort = `Next renewal` → soonest-renewal first.
- [ ] Sort = `Monthly cost (high→low)` → most expensive monthly first.
- [ ] Sort = `Yearly cost (high→low)` → most expensive yearly first.

### S9 — Edit form

- [ ] Click a subscription tiddler, then enter edit mode.
- [ ] Custom edit form appears: dropdowns for status / billing / currency, date picker for renewal-date, text inputs for amount / vendor-url etc.
- [ ] Change status from Active → Trial. The `trial-ends` row appears in the form.
- [ ] Change status back to Active. The `trial-ends` row disappears (still stored in the field, just hidden in the form).
- [ ] Body editor still works for free-text notes.

### S10 — New subscription

- [ ] On the `Subscriptions` view, click `+ New subscription`.
- [ ] A new tiddler `Untitled subscription` is created and opened in edit mode.
- [ ] The custom edit form is shown (status default = Active).
- [ ] Rename the title in the field/title row to `Test Sub`.
- [ ] Set amount=5, currency=AUD, billing-frequency=Monthly, renewal-date = 30 days out.
- [ ] Save.
- [ ] Return to `Subscriptions` view → the new row appears, totals updated.
- [ ] Delete the test sub (`-1` lifecycle test in TW: actions menu → delete).

### S11 — Filter persistence

- [ ] Set status filter to `Trial only`. Reload the page.
- [ ] Filter is still on `Trial only` (state survived because `$:/state/subscription-tracker/filter` is a real tiddler).

### S12 — Empty state

- [ ] In a fresh wiki with the plugin loaded but no subscription tiddlers: the `Subscriptions` view shows `No subscriptions yet. Click + New subscription to add one.`
```

- [ ] **Step 2: Commit**

```bash
git add tests/test-plan.md
git commit -m "test: add manual end-to-end test plan"
```

---

## Phase 9 — Build smoke + release

### Task 9.1: Run the build smoke test

- [ ] **Step 1: Run `bin/test-build.sh`**

```bash
bin/test-build.sh
```
Expected: `PASS: plugin builds cleanly`

If it fails, the most likely cause is a missing or malformed `plugin.info`, or a tiddler with broken syntax that breaks the wiki load. Check the TW console output (rerun without `>/dev/null`).

- [ ] **Step 2: Confirm full render-test pass**

```bash
bin/run-render-tests.sh
```
Expected: all fixtures PASS, exit 0.

### Task 9.2: Run the manual test plan

- [ ] Walk through `tests/test-plan.md` end-to-end. Check off each scenario.
- [ ] If any scenario fails, fix it (TDD: add a render fixture if possible, then implement the fix).
- [ ] On clean pass, proceed.

### Task 9.3: Tag v0.1.0

- [ ] **Step 1: Verify `plugin.info` version is `0.1.0`** (it already is — sanity check).

- [ ] **Step 2: Tag the release**

```bash
git tag -a v0.1.0 -m "Release v0.1.0 — initial publishable build"
```

- [ ] **Step 3: Optionally produce a single-file plugin JSON for distribution**

```bash
mkdir -p dist
TIDDLYWIKI_PLUGIN_PATH=plugins tiddlywiki tests/wiki \
    --savetiddler '$:/plugins/realaaa/subscription-tracker' \
    subscription-tracker-0.1.0.json \
    --output dist
```

The resulting `dist/subscription-tracker-0.1.0.json` is the single-file plugin you drag-and-drop into any TW 5.4+ wiki.

`dist/` is already in `.gitignore` (covered by the `dist/` line in the existing gitignore).

---

## Self-review checklist (run before declaring v0.1.0 done)

- [ ] Every spec section has at least one task implementing it.
- [ ] All render fixtures pass (`bin/run-render-tests.sh`).
- [ ] Build smoke passes (`bin/test-build.sh`).
- [ ] Manual test plan walked end-to-end (`tests/test-plan.md`).
- [ ] No JavaScript anywhere in the plugin folder.
- [ ] No external plugin dependencies declared in `plugin.info`.
- [ ] `git status` clean.

---

## Known caveats / where you may need to iterate

These are spots in the plan where the WikiText syntax might need fiddling once you actually hit the engine. None are showstoppers — all have documented fallbacks above:

1. **`sub.next-renewal` `:map[<__>]` chain** (Task 3.5) — if the variable substitution in `:map` doesn't work as written, fall back to the two-function version that splits `sub.days-to-add` from `sub.next-renewal`.
2. **Dynamic filter construction in `views/main.tid`** (Task 7.3) — if `addprefix`/`addsuffix` chaining produces malformed filters, replace with explicit `<$switch>` blocks. Fallback noted in step 1 of that task.
3. **`match:regexp` operator availability in 5.4** (Task 7.4) — if not available, simplify the excluded-amount-count derivation. Fallback noted.
4. **`<$action-createtiddler>` variable name `createTiddler-title`** (Task 7.2) — confirm via TW docs; the variable name has changed across major versions. If broken, use `<$action-sendmessage>` with `tm-new-tiddler` instead.

When iterating on these, follow the same TDD discipline: red render-fixture → fix → green → commit.
