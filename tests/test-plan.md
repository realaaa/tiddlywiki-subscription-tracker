# Manual Test Plan — Subscription Tracker v1

Run this before tagging a release. Estimated time: 15 minutes.

## Setup

1. Build smoke check: `bin/test-build.sh` — confirms the plugin packages cleanly.
2. Render-test pass: `bin/run-render-tests.sh` — confirms all 39 fixture-based tests pass.
3. Start a fresh TW node wiki with the plugin:
   ```bash
   cp tests/fixtures/*.tid tests/wiki/tiddlers/
   TIDDLYWIKI_PLUGIN_PATH=$(pwd)/plugins tiddlywiki tests/wiki --listen --port 8080
   ```
4. Open http://localhost:8080 and click into the `Subscriptions` tiddler.

## Scenarios

### S1 — Initial render

- [ ] `Subscriptions` view renders without browser-console errors.
- [ ] Active count, monthly total (AUD), yearly total (AUD) display.
- [ ] Three banners visible: missing currency rate (1 sub — Bitcoin Miner Pro), missing trial-ends (1 sub — Adobe Free Trial). The display-currency-config banner should NOT appear.

### S2 — Pill rendering

- [ ] `Netflix`, `Spotify`, `Adobe Creative Cloud`, `Old Domain Registration`, `Bitcoin Miner Pro`, `Mystery Charge` show ''Active'' pill (orange).
- [ ] `Notion AI Trial`, `Adobe Free Trial` show ''Trial'' pill (purple).
- [ ] `Office 365 Personal` shows ''Paused'' pill (grey).
- [ ] `MoviePass` shows ''Canceled'' pill (green).
- [ ] Tag pills (Entertainment / Productivity) render in orange next to status.

### S3 — Auto-roll

- [ ] `Old Domain Registration` (renewal stored 2010-03-15): renewal column shows a future date, near March 15 of an upcoming year.
- [ ] `MoviePass` (Canceled, renewal stored 2018-01-01): renewal column shows the original `1st January 2018` (no auto-roll for Canceled).

### S4 — Renewal-soon highlighting

- [ ] Edit one fixture's `renewal-date` to a date 7 days from today. Save.
- [ ] That row's renewal column turns red (CSS class `sub-renewal-soon`).
- [ ] Edit it back to a date 30 days from today. Save.
- [ ] Red highlight goes away.

### S5 — Currency conversion

- [ ] `Spotify` (USD 9.99 monthly): Monthly column shows ≈ AUD 15.18.
- [ ] `Adobe Creative Cloud` (USD 599 yearly): Monthly ≈ AUD 75.83, Yearly ≈ AUD 910.
- [ ] Open `$:/plugins/realaaa/subscription-tracker/config/settings`. Change `display-currency` from `AUD` to `USD`. Save.
- [ ] Add an `AUD` rate of `0.66` to `$:/plugins/realaaa/subscription-tracker/config/rates`, and change USD's rate to `1.0`. Otherwise the display-currency-config banner appears (which is the intended behaviour — but for this test we want a complete data set).
- [ ] Totals + columns re-render in USD.
- [ ] Restore `display-currency` to `AUD` and revert the rates.

### S6 — Strict errors

- [ ] `Bitcoin Miner Pro` row: amount cell shows ⚠ with `XYZ ?` (missing-rate). Monthly + Yearly cells show `—`. Banner counts +1 missing rate.
- [ ] `Adobe Free Trial` row: status pill is Trial. Banner counts +1 missing trial-ends. Row contributes to totals (cost=0, but counted as active).
- [ ] `Mystery Charge` row: amount cell shows `?` (the `<<sub.amount-cell>>` procedure renders the literal). Monthly + Yearly may show 0 or empty. (v1 doesn't have automated invalid-amount detection — known limitation.)

### S7 — Filters

- [ ] Status = `Active only` → table shows only Active subs (Netflix, Spotify, Adobe, Mystery Charge, Bitcoin Miner Pro, Old Domain).
- [ ] Status = `Trial only` → only Notion AI Trial + Adobe Free Trial.
- [ ] Status = `Canceled only` → only MoviePass.
- [ ] Status = `All (including Canceled)` → all rows visible. Totals exclude Canceled.
- [ ] Tag = `Entertainment` → only Entertainment-tagged subs visible.
- [ ] Tag = `(All)` → restored.

### S8 — Sort (cosmetic in v1)

- [ ] Sort dropdown displays the four options: Name / Next renewal / Monthly cost / Yearly cost.
- [ ] Note: in v1 the table is always sorted by Next renewal regardless of selection. Other options become functional in v0.2.

### S9 — Edit form

- [ ] Click a subscription tiddler, then enter edit mode.
- [ ] Custom edit form appears: dropdowns for status / billing / currency, date pickers for renewal-date, text inputs for amount / vendor-url etc.
- [ ] Change status from Active → Trial. The `trial-ends` row appears in the form.
- [ ] Change status back to Active. The `trial-ends` row disappears (still stored in the field, just hidden in the form).
- [ ] Body editor still works for free-text notes.

### S10 — New subscription

- [ ] On the `Subscriptions` view, click `+ New subscription`.
- [ ] A new tiddler `Untitled subscription` is created and opened in edit mode.
- [ ] The custom edit form is shown (status default = Active).
- [ ] Rename the title in the field/title row to `Test Sub`.
- [ ] Set amount=5, currency=AUD, billing-frequency=Monthly, renewal-date 30 days out.
- [ ] Save.
- [ ] Return to `Subscriptions` view → the new row appears, totals updated.
- [ ] Delete the test sub.

### S11 — Filter persistence

- [ ] Set status filter to `Trial only`. Reload the page.
- [ ] Filter is still on `Trial only` (state survived because `$:/state/subscription-tracker/filter` is a real tiddler).

### S12 — Empty state

- [ ] In a fresh wiki with the plugin loaded but no subscription tiddlers: the `Subscriptions` view shows `No subscriptions match the current filters.` (Note: the empty-state copy is technically the no-match copy. A dedicated "no subscriptions yet" empty state is a v0.2 polish task.)
