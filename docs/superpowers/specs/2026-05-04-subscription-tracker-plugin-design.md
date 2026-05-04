# Subscription Tracker Plugin for TiddlyWiki 5.4 — Design Spec

**Status:** Approved (brainstorm 2026-05-04)
**Plugin id:** `$:/plugins/realaaa/subscription-tracker`
**Target:** TiddlyWiki 5.4.0+ (Node.js, separate-tiddler-files mode)
**License:** MIT

---

## 1. Summary

A vanilla, dependency-free TiddlyWiki plugin that turns `subscriptions`-tagged tiddlers into a Notion-style table with status / category pills, multi-currency monthly/yearly cost math, trial tracking, and a structured editor. Pure WikiText (`\function` + `\procedure`), no JavaScript, ~7 shadow tiddlers, ~450 lines total.

The plugin owns the *views* and *helpers*; the user owns the *data* (subscription tiddlers). Uninstalling the plugin leaves data intact.

Companion document: `subscription-tracker-analysis.md` (in repo root) for the broader ecosystem analysis that produced the vanilla-only direction.

## 2. Goals

- Replace the user's Notion subscription table with a TiddlyWiki-native equivalent.
- Multi-currency: native amount per row, monthly/yearly totals in a single configurable display currency.
- Trial tracking: distinct status with a "decide before" date.
- Auto-roll renewal dates at render time, so the "renewal in N days" signal stays meaningful without user maintenance.
- Distributable as a single JSON drop-in plugin (publishable on the TW forum / a plugin library).
- Zero external dependencies. Compatible with TW 5.4.0 forward.

## 3. Non-goals (v1)

- Live FX rates (no HTTP from WikiText).
- Lifetime / historical spend analytics. Post-v1.
- Family / shared-subscription split-cost math. Post-v1.
- Scheduled reminder alarms. Post-v1, layered via TiddlyTools/Time/Alarms.
- Inline-editable cells (Shiraz-style). Click-through to the tiddler editor only.
- CI / automated browser tests. Manual + build smoke only.

## 4. Decisions log

| # | Decision | Rationale |
|---|---|---|
| 1 | Publishable plugin (proper `plugin.info` shape, configurable, namespaced under `$:/plugins/realaaa/subscription-tracker`) over loose tiddlers | Forum follow-up is a near-term goal; configurability cost is small at design time |
| 2 | v1 includes multi-currency + trials. Lifetime + family deferred. | Multi-currency and trials are where the plugin earns its keep; lifetime/family additive later |
| 3 | Auto-display-roll for renewal dates (compute next future occurrence at render time, never mutate the stored field) | Stable git diffs, preserves the "original" renewal date, signal stays accurate without user maintenance |
| 4 | Native amount per row, single configurable display currency for monthly/yearly columns + totals. Strict on missing rates. | Preserves "what the vendor bills you"; clean source data principle (user's words: "no assumptions, source data should be clean") |
| 5 | Custom EditTemplate cascade + "+ New subscription" button on main view | Polished structured-form UX without the cost of inline-edit |
| 6 | Minimal filter/sort: status filter, sort dropdown, tag filter — bound to a state tiddler | Right-sized for ~50 subscriptions; YAGNI on Notion-level UI chrome |
| 7 | Approach 1 — compact ~7 shadow tiddlers grouped by concern | Right size for v1; refactor to granular later if forum demand materialises |
| 8 | Strict on `trial-ends` when `status=Trial` (visible error glyph + banner counter) | Same data-cleanliness principle as missing currency rates |
| 9 | Manual test plan + fixture tiddlers + build smoke. No CI in v1. | Personal-publishable plugin; CI's complexity isn't justified yet |

## 5. Architecture

### 5.1 Plugin identity

```
title:        $:/plugins/realaaa/subscription-tracker
name:         Subscription Tracker
plugin-type:  plugin
core-version: >=5.4.0
license:      MIT
version:      0.1.0
```

### 5.2 Filesystem layout (source of truth in repo)

```
plugins/realaaa/subscription-tracker/
  plugin.info
  tiddlywiki.files            (optional manifest if file globbing needs control)
  readme.tid
  config/
    settings.tid              user-editable: display currency, tag-name, thresholds
    rates.json                user-editable rate map (data tiddler)
  styles.tid                  tagged $:/tags/Stylesheet
  macros.tid                  \function and \procedure definitions
  templates/
    edit.tid                  EditTemplate cascade entry
  views/
    main.tid                  the "Subscriptions" view (table + filter bar + totals)
```

The plugin is built and installed via standard TW node-mode mechanisms:

- **Development:** symlink `plugins/realaaa/subscription-tracker/` into the target wiki's plugin path, or set `TIDDLYWIKI_PLUGIN_PATH` to include the repo's `plugins/` directory.
- **Distribution:** `tiddlywiki --build plugin` emits a single JSON file; users drag-and-drop into their wiki to install.

### 5.3 Composition

- All `\function` / `\procedure` definitions live in one tiddler (`macros.tid`). Both `views/main.tid` and `templates/edit.tid` open with `\import [[$:/plugins/realaaa/subscription-tracker/macros]]` to share the same definitions.
- Settings read at render time via `{{$:/plugins/realaaa/subscription-tracker/config/settings##<field>}}`. Editing the settings tiddler immediately re-renders dependent views — no persistence layer beyond TW's tiddler store.
- Subscription tiddlers are *user-owned*, not shadows. The plugin defines the *interpretation* (functions, templates, views) but never owns or mutates user data.

### 5.4 Override discipline

Approach-1 consequence: a user wanting to customise overrides whole tiddlers (e.g. drop a personal copy of `views/main` into their wiki to shadow it). Finer-grained extension points are not exposed in v1.

## 6. Data model

### 6.1 Subscription tiddler (user-owned)

| Field | Type | Required | Example | Notes |
|---|---|---|---|---|
| `title` | string | yes | `Netflix` | Vendor name |
| `tags` | tag list | yes | `subscriptions Entertainment` | Always include the configured tag (default `subscriptions`) plus 1+ category |
| `status` | enum | yes | `Active` | `Active` / `Trial` / `Paused` / `Canceled` |
| `billing-frequency` | enum | yes | `Monthly` | `Monthly` / `Yearly` / `Quarterly` / `Weekly` |
| `amount` | number | yes | `13.99` | Stored in `currency` units, native to the bill |
| `currency` | ISO code | yes | `AUD` | Must exist in the rates tiddler (strict) |
| `renewal-date` | TW date | yes for non-Canceled | `20260601000000` | Source for the auto-rolled "next renewal" display |
| `trial-ends` | TW date | yes when `status=Trial` (strict) | `20260520000000` | Only meaningful for Trial; ignored otherwise |
| `payment-method` | string | optional | `Visa ••4242` | Last 4 only — convention; plugin doesn't validate but the EditTemplate hints |
| `vendor-url` | URL | optional | `https://netflix.com` | |
| `cancel-url` | URL | optional | `https://netflix.com/cancel` | |
| (body) | text | optional | freeform notes | |

Dropped from prior analysis §4: `started-date` — out of v1 (historical/lifetime is post-v1).

### 6.2 Settings tiddler

`$:/plugins/realaaa/subscription-tracker/config/settings`:

| Field | Default | Purpose |
|---|---|---|
| `display-currency` | `AUD` | Currency used for monthly/yearly columns + totals |
| `tag-name` | `subscriptions` | Override if your wiki already uses that tag |
| `renewal-soon-days` | `14` | Threshold for the red-highlight on renewal date |
| `show-canceled-default` | `no` | Whether the status filter starts at "include Canceled" |

### 6.3 Rates tiddler

`$:/plugins/realaaa/subscription-tracker/config/rates` — JSON data tiddler (`type: application/json`):

```json
{ "AUD": 1.0, "USD": 1.52, "EUR": 1.65, "GBP": 1.92 }
```

**Convention:** rates are expressed as 1 unit of the foreign currency in display-currency units. With `display-currency=AUD`, `USD: 1.52` means 1 USD = 1.52 AUD. The display-currency's own entry must be `1.0`.

Default ships with stubs for `AUD/USD/EUR/GBP`. User updates whenever they care.

### 6.4 State tiddler (runtime UI state)

`$:/state/subscription-tracker/filter` (plain tiddler, not shadow — survives reloads):

| Field | Default | Values |
|---|---|---|
| `status-filter` | `active` | `active` (= Active+Trial+Paused) / `all` / `Active` / `Trial` / `Paused` / `Canceled` |
| `sort` | `renewal` | `name` / `renewal` / `monthly-desc` / `yearly-desc` |
| `tag-filter` | (empty = all) | any single category tag |

## 7. Components

Listed in dependency order — later items import earlier ones.

### 7.1 `plugin.info` (~10 lines)

```json
{
  "title": "$:/plugins/realaaa/subscription-tracker",
  "name": "Subscription Tracker",
  "description": "Notion-style subscriptions table for TiddlyWiki 5.4+",
  "author": "realaaa",
  "version": "0.1.0",
  "core-version": ">=5.4.0",
  "plugin-type": "plugin",
  "list": "readme",
  "source": "https://github.com/realaaa/tiddlywiki-subscription-tracker",
  "license": "MIT"
}
```

### 7.2 `readme.tid`

Short. Links to the main `Subscriptions` view, points at `config/settings` and `config/rates` for customisation.

### 7.3 `config/settings.tid`

Plain tiddler with the four fields from §6.2, no body. Default values shipped as shadow.

### 7.4 `config/rates.json`

JSON data tiddler. Default ships with `AUD/USD/EUR/GBP` stubs. No code, just data.

### 7.5 `styles.tid` (~80 lines)

Tagged `$:/tags/Stylesheet`. Owns:

- `.sub-table` and column styling
- `.sub-pill` base + per-status / per-tag colour variants (matches Notion screenshot palette: orange-Active, green-Canceled, purple-Trial, grey-Paused)
- `.sub-renewal-soon` red highlight class
- `.sub-error` for missing-rate / strict-error glyph
- Filter-bar layout

Uses `<<colour …>>` macros for table chrome (so light/dark mode tracks the user's palette); fixed hex for the Notion-ish pills. All pill colours grouped in a single CSS block for easy re-skinning.

### 7.6 `macros.tid` (~120 lines)

Definitions only, no UI rendering. Imported by templates and views.

**Functions (return values, used in filter expressions):**

| Name | Returns | Notes |
|---|---|---|
| `sub.rate(ccy)` | rate from rates tiddler, or empty | Empty result triggers strict error path |
| `sub.next-renewal()` | TW date string | Auto-roll: if stored `renewal-date` is past *and* status ≠ Canceled, add `billing-frequency`-sized periods (Monthly = +1 month, Quarterly = +3 months, Yearly = +1 year, Weekly = +7 days) until the result is in the future. Otherwise return as-is. Implemented as bounded math (compute period count from days-since-stored), not iterative. |
| `sub.days-until-renewal()` | integer | Built on `sub.next-renewal()`, never on the raw field |
| `sub.is-renewal-soon()` | bool-ish | True if days-until ≤ `renewal-soon-days` setting |
| `sub.trial-days-left()` | integer or empty | Only meaningful for `status=Trial`; empty if `trial-ends` blank |
| `sub.monthly-native()` | number | Amount in native currency, normalised to monthly (Yearly÷12, Quarterly÷3, Weekly×4.33) |
| `sub.monthly-display()` | number | `monthly-native × rate`; empty if rate unknown |
| `sub.yearly-display()` | number | `monthly-display × 12` |

**Procedures (UI helpers, render markup):**

- `sub.status-pill(status)` — styled `<span>` for the status enum
- `sub.tag-pill(tag)` — styled `<span>` for category tags
- `sub.amount-cell(amount, currency)` — `USD 9.99` or strict error glyph if rate missing

### 7.7 `templates/edit.tid` (~80 lines)

Tagged `$:/tags/EditTemplate` with cascade condition matching tiddlers tagged with the configured `tag-name`. Renders:

- Read-only header (title)
- Labeled inputs for each schema field
- `<$select>` dropdowns for `status`, `billing-frequency`, `currency` (currency options sourced from rates tiddler keys)
- `<$edit-text type="date">` for `renewal-date` and `trial-ends`
- `trial-ends` row conditionally shown only when `status=Trial`
- Free-text body editor below the form (preserves notes-in-body convention)

### 7.8 `views/main.tid` (~150 lines)

The user-facing `Subscriptions` view. Three blocks:

**Filter bar**
- Three `<$select>` widgets bound to `$:/state/subscription-tracker/filter` (status / sort / tag)
- "+ New subscription" `<$button>` that:
  - Creates a new tiddler with a generated title (`Untitled subscription <n>`), `status=Active`, tagged with the configured tag-name, empty other fields
  - `<$action-navigate>`s to it in edit mode (EditTemplate cascade fires)
  - User renames the title from inside the editor

**Totals bar**
- Active count + monthly total + yearly total in display currency
- `+[sum[]fixed[2]]` over the filtered set
- Excludes Canceled, missing-rate rows, and invalid-amount rows
- Banner below totals when exclusions exist: counts per exclusion reason

**Table**
- Filtered + sorted via state-tiddler bindings
- One row per subscription — columns: Name / Status / Tags / Billing / Renewal / Amount / Monthly / Yearly
- Renewal column applies `.sub-renewal-soon` class when `sub.is-renewal-soon` is true (for non-Canceled rows)
- Empty-state message when no rows match: *"No subscriptions yet. Click + New to add one."*

**Total surface: ~7 shadow tiddlers, ~450 lines of WikiText + CSS + JSON. No JavaScript. No external dependencies.**

## 8. Data flow

TW is reactive — almost everything is "change a tiddler → re-render."

```
[user edits a subscription tiddler]
        ↓
  TW change event
        ↓
  views/main re-renders
        ↓
  ├─ filter bar reads $:/state/subscription-tracker/filter (unchanged)
  ├─ totals bar re-runs sub.monthly-display / sub.yearly-display via filter math
  └─ each row re-runs sub.next-renewal, sub.is-renewal-soon, etc.

[user changes display-currency in settings]
        ↓
  All references to {{...##display-currency}} re-evaluate
        ↓
  Every monthly/yearly cell + totals bar re-renders

[user changes filter dropdown]
        ↓
  $:/state/subscription-tracker/filter field updated
        ↓
  views/main filter pipeline re-runs
        ↓
  Table rows shown/hidden/re-sorted

[user clicks "+ New subscription"]
        ↓
  Button creates tiddler with status=Active, tagged subscriptions, empty fields
        ↓
  <$action-navigate> opens it in edit mode
        ↓
  EditTemplate cascade matches → form shown
        ↓
  User renames title from inside the editor
```

The auto-roll for `renewal-date` is **purely a render-time computation**. The stored field is never mutated. Implications:

- `git diff` on the wiki stays clean — no churn from time passing.
- Original renewal date remains inspectable in the field.
- Trade-off: auto-roll runs on every render. For ~50 subs this is microseconds; not worth optimising.

## 9. Error handling

Strict on currency rates and trial-ends (per data-cleanliness principle); lenient on missing optional fields. The plugin should never blow up the whole view because of one bad row, but it should never silently lie about a number either.

| Scenario | Behaviour |
|---|---|
| Missing rate for a sub's `currency` | Amount cell shows `USD ?` with `⚠` glyph (`.sub-error`). Monthly/Yearly cells show `—`. Row excluded from totals. Banner counts: *"N subs excluded from totals (missing currency rate)"* |
| Blank `renewal-date` on Active/Trial/Paused | Renewal column shows `—`. No red highlight. Row still contributes to totals (cost math doesn't depend on renewal-date) |
| Blank `renewal-date` on Canceled | Renewal column shows `—`. Expected — Canceled subs have no renewal |
| `renewal-date` in past on Canceled | Show stored date as-is (don't auto-roll Canceled — historical date is the truth) |
| `renewal-date` in past on Active/Trial/Paused | Auto-roll forward as designed |
| `status=Trial` but `trial-ends` blank | **Strict.** Trial-days-left cell shows `⚠`. Banner counts: *"N Trial subs missing trial-ends date"*. Row **not** excluded from totals (cost math is independent of `trial-ends`) |
| `amount` non-numeric or blank | Cell shows `?`. Row excluded from totals. Banner counts: *"N subs excluded (invalid amount)"* |
| Empty wiki — no subscriptions yet | Empty-state message: *"No subscriptions yet. Click + New to add one."* |
| `display-currency` not in rates tiddler (or rate ≠ 1.0) | Config error, not data error. Banner at top: *"Display currency 'XYZ' has no rate (or rate ≠ 1.0). Fix in plugin settings."* Whole table still renders; monthly/yearly columns and totals show `—` |
| Subscription tagged `subscriptions` but with no `status` | **Lenient.** Status column shows nothing. Sub treated as `status=Active` for filter purposes (assumes user is mid-add). Once user saves status, normal flow |

Principle: **visible-error-with-context > broken-table > silent-misreport.**

## 10. Testing

### 10.1 Manual test plan + fixtures

`tests/fixtures/` — sample subscription tiddlers as `.tid` files, each crafted to exercise one branch:

| Fixture | Purpose |
|---|---|
| `Netflix.tid` | Active, Monthly, AUD — happy path |
| `Spotify-USD.tid` | Active, Monthly, USD — currency conversion |
| `Adobe.tid` | Active, Yearly, USD — yearly→monthly math |
| `Notion-Trial.tid` | Trial, Yearly, valid `trial-ends` — trial happy path |
| `BadCurrency.tid` | Active, Monthly, currency=`XYZ` — strict missing-rate error |
| `BadAmount.tid` | Active, Monthly, amount=`abc` — invalid-amount error |
| `Trial-NoEnd.tid` | Trial, Monthly, no `trial-ends` — strict trial error |
| `Old-Renewal.tid` | Active, Monthly, renewal-date 6 months ago — auto-roll exercise |
| `OldCanceled.tid` | Canceled, stale renewal-date — confirms canceled rows aren't auto-rolled |
| `Paused-NoRenewal.tid` | Paused, blank renewal-date — lenient case (`—`, no error) |

`tests/test-plan.md` — manual checklist:

1. Load all fixtures into a fresh TW node wiki with the plugin installed → table renders without errors.
2. Verify totals exclude Canceled, BadCurrency, BadAmount; banner shows correct exclusion counts.
3. Change `display-currency` AUD → USD → confirm all monthly/yearly cells re-convert.
4. Toggle status filter through each value → confirm row counts match expectation.
5. Toggle sort through each option → confirm row order.
6. Click "+ New subscription" → confirm new tiddler created, edit form shown, can rename + save.
7. Edit a fixture's `status` Active → Canceled → confirm it leaves the totals immediately.
8. Change `renewal-soon-days` setting → confirm red-highlight threshold updates.
9. Verify the strict-error banners disappear when offending fixtures are corrected.

### 10.2 Build smoke test

`bin/test-build.sh` (or documented one-liner): runs `tiddlywiki --output build --build plugin` against a test wiki to confirm the plugin packages cleanly into a single `.json`. Catches manifest typos, missing files, broken JSON.

### 10.3 Out of scope (v1)

- Automated headless-browser tests (TW-in-puppeteer rendering + HTML grep).
- CI pipeline.
- WikiText assertion harness.

These are revisitable post-v1 if the plugin gains traction beyond personal use.

## 11. Roadmap (post-v1)

In rough priority order — each is a fresh spec-and-plan cycle of its own:

| Phase | Scope | Notes |
|---|---|---|
| v0.2 | Display-currency toggle (UI button cycles AUD→USD→EUR) | Easy add on top of v1 |
| v0.3 | Lifetime / historical spend (`started-date` field, lifetime cost column) | From analysis §9 |
| v0.4 | Family / shared subs (`shared-with` field, effective-cost math) | From analysis §9 |
| v0.5 | TiddlyTools/Time/Alarms integration for renewal reminders | Optional dependency, gated behind a setting |
| v0.6 | Inline-editable cells | Only if forum demand materialises |
| v0.7 | Charts / cost-per-category breakdown | Probably needs a charting plugin dependency |

## 12. Open questions

None at spec-write time. All clarifying questions resolved during brainstorm.
