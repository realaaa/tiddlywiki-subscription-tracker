# Subscription Tracker for TiddlyWiki 5.4.0 — Project Analysis

**Author note:** Analysis prepared for a Node.js TiddlyWiki 5.4.0 install (separate `.tid` files), assuming each subscription is its own tiddler tagged `subscriptions`.

---

## 1. TL;DR / Recommendation

Build a **native-WikiText subscriptions view** as the primary surface, and bolt on **TiddlyTools/Time/Alarms** for the renewal-reminder layer. Skip Shiraz for now — it's a great plugin, but it's pinned to TW 5.3.5 and is the wrong thing to build a long-lived PKM workflow on while 5.4.0 is fresh.

This gives you:

- A Notion-style table view, fully under your control, no plugin breakage risk.
- Automatic monthly→yearly cost math.
- Sortable / filterable / total-able rows.
- Pop-up + scheduled alarms for upcoming renewals.
- One single source of truth: each vendor stays a normal tiddler.

The rest of this document explains why, lays out the data model, and gives you starter code you can paste in.

---

## 2. State of the ecosystem (Nov 2025–May 2026)

| Option | Status | Verdict |
|---|---|---|
| **Shiraz Dynamic Tables** (kookma) | Last release 2.9.7 (Jul 2024), declared compatible with TW 5.3.5. `core-version: >=5.2.7`. Shiraz 3.0 was announced in 2022 but never shipped. | Currently the most powerful "Notion-like" table tool, but **drifting out of compatibility** with 5.4.0. Maintainer is lightly active. Risky as foundation. |
| **TiddlyTables** (ooktech) | Older, niche, no recent maintenance. | Skip. |
| **TiddlyTools/Time/Alarms + Calendar** (Eric Shulman) | Updated May 2025 with full recurring-alarm support (monthly, "third Monday", weekly, daily). Actively maintained. | **Use this** for the reminders layer. |
| **TW-EventCal** | Calendar plugin, useful for visualisation. | Optional add-on. |
| **Native WikiText (5.3+ filter math, procedures, functions)** | Built into 5.4.0. Has `sum`, `multiply`, `divide`, `:map`, `:then`/`:else`, `daysuntil` etc. | **Backbone of the recommended approach.** No external dependency, no upgrade risk. |
| **Sunny's subscription-tracker.tiddlyhost.com** | Public starter wiki from your forum thread. Worth borrowing UX patterns from. | Reference, not foundation. |

The crux: 5.4.0 is a ~100-change release including "pluginisation" of server components, plus several macro→procedure conversions in the core. Shiraz's CSS and macro assumptions were written against the older shape, so visual bugs and broken sorts/filters are exactly the kind of thing you'd expect, and that's consistent with what you've observed. Until kookma puts out a 5.4-tested build, depending on Shiraz means you're betting that a third-party patches it before your wiki notices. The native path means *you* own the only thing that can break.

---

## 3. Decomposing the problem (PM lens)

The Notion screenshot is one screen, but it actually bundles five capabilities:

1. **Per-vendor record** — a place to keep all info about each subscription (already solved: one tiddler per vendor, tagged `subscriptions`).
2. **Tabular roll-up view** — a single tiddler that lists them all in a structured table with the right columns.
3. **Derived calculations** — yearly cost from monthly, "days until renewal", monthly equivalent of a yearly bill, totals across the portfolio.
4. **Status & category visualisation** — the coloured pills in the screenshot (Active/Canceled, Entertainment/Productivity).
5. **Reminders** — heads-up before a renewal hits.

Treat each as a separate slice. You can ship #1–#3 in an evening, then layer #4 (cosmetics) and #5 (alarms) afterwards.

---

## 4. Proposed data model

A normalised schema you write into each subscription tiddler. Field names follow TW convention (lowercase, hyphen-separated).

| Field | Type | Example | Notes |
|---|---|---|---|
| `title` | string | `Netflix` | Vendor name |
| `tags` | tag list | `subscriptions Entertainment` | Always include `subscriptions` plus 1+ category |
| `status` | enum | `Active` | `Active` / `Canceled` / `Trial` / `Paused` |
| `billing-frequency` | enum | `Monthly` | `Monthly` / `Yearly` / `Quarterly` / `Weekly` |
| `amount` | number | `13.99` | The actual billed amount in `billing-frequency` units. Don't pre-compute monthly. |
| `currency` | string | `AUD` | ISO code |
| `renewal-date` | TW date | `20260601000000` | TW's standard date format. Empty = no known renewal (e.g. cancelled) |
| `started-date` | TW date | `20230301000000` | Optional. Useful for "how long have I had this" analytics |
| `payment-method` | string | `Visa ••4242` | **Last 4 digits only.** Never store full PANs in a wiki, especially if it ever syncs. |
| `vendor-url` | URL | `https://netflix.com` | |
| `cancel-url` | URL | `https://netflix.com/cancel` | The "rescue" link for when you decide to bail |
| `notes` | text (body) | freeform | Use the tiddler body, not a field |

**Why store `amount` in native units rather than always-monthly:** it preserves the truth of how the vendor bills you (helps with reconciliation when you read your statement), and the conversions are trivial to compute on display.

**Why not store yearly-cost as a field:** derived data shouldn't live alongside source data — change the amount once and your roll-up updates everywhere.

---

## 5. Architecture options compared

### Option A — Native WikiText only (recommended)
- Pure TW 5.4.0 features: `<$list>`, filter math, procedures, functions.
- One macro tiddler, one view tiddler, ~100 lines of WikiText total.
- **Pros:** zero dependencies, zero compat risk, fast, fully customisable, plays nicely with sync.
- **Cons:** sorting/filtering are less polished out-of-the-box than Shiraz; you write the CSS.

### Option B — Shiraz Dynamic Tables
- Use `<<table-dynamic …>>` with the `tbl-clone`, `tbl-expand`, `<<sum>>` features that Springer described in your forum thread.
- **Pros:** much less code; in-line editing of fields directly from the table; built-in totals row; "+ new row" affordance.
- **Cons:** broken/unstable on 5.4.0 right now; future-proofing is uncertain; harder to template.

### Option C — Hybrid
- Native table for display, but borrow Shiraz's `tbl-edit` widget for inline editing if/when it stabilises.
- **Pros:** best of both worlds eventually.
- **Cons:** wait-and-see; complicated.

### Option D — Sunny's starter wiki as a base
- Drag-and-drop the JSON tiddlers from `subscription-tracker.tiddlyhost.com`.
- **Pros:** instant start.
- **Cons:** you inherit someone else's design choices; still need to verify against 5.4.0; less learning value.

**My pick: A, with TiddlyTools alarms layered on later for the reminder slice.**

---

## 6. Implementation — starter code for Option A

These are the four tiddlers you'd create. Treat as a working MVP — paste in, then iterate.

### 6.1 — `$:/my/subs/macros` (functions & procedures)

```wikitext
\function sub.monthly-equiv()
[get[billing-frequency]match[Monthly]] :then[get[amount]]
[get[billing-frequency]match[Yearly]] :then[get[amount]divide[12]]
[get[billing-frequency]match[Quarterly]] :then[get[amount]divide[3]]
[get[billing-frequency]match[Weekly]] :then[get[amount]multiply[4.33]]

\function sub.yearly-equiv()
[get[billing-frequency]match[Monthly]] :then[get[amount]multiply[12]]
[get[billing-frequency]match[Yearly]] :then[get[amount]]
[get[billing-frequency]match[Quarterly]] :then[get[amount]multiply[4]]
[get[billing-frequency]match[Weekly]] :then[get[amount]multiply[52]]

\function sub.days-until-renewal()
[get[renewal-date]!is[blank]daysuntil[]]

\procedure sub.status-pill(status)
<span class={{{ [[sub-pill sub-status-]addsuffix<status>lowercase[]] }}}><$text text=<<status>>/></span>
\end

\procedure sub.tag-pill(tag)
<span class="sub-pill sub-tag"><$text text=<<tag>>/></span>
\end
```

A few syntax notes:
- `\function` and `\procedure` are the modern (5.3+) replacements for `\define` macros — they don't have the substitution-by-string footguns that `\define` has, and they're how the core is being rewritten.
- `daysuntil[]` is a built-in 5.x date filter operator — returns days from today (negative = past).
- The `addsuffix<x>lowercase[]` chain builds the CSS class name dynamically (e.g. `sub-status-active`).

### 6.2 — `$:/my/subs/styles` (tag this with `$:/tags/Stylesheet`)

```css
.sub-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.95em;
}
.sub-table th, .sub-table td {
  padding: 8px 12px;
  border-bottom: 1px solid <<colour table-border>>;
  text-align: left;
}
.sub-table th {
  background: <<colour table-header-background>>;
  font-weight: 600;
}
.sub-table td.num { text-align: right; font-variant-numeric: tabular-nums; }
.sub-table tr:hover { background: <<colour table-footer-background>>; }

.sub-pill {
  display: inline-block;
  padding: 2px 10px;
  border-radius: 10px;
  font-size: 0.85em;
  margin-right: 4px;
}
.sub-status-active   { background: #c2410c; color: #fff; }
.sub-status-canceled { background: #15803d; color: #fff; }
.sub-status-trial    { background: #7e22ce; color: #fff; }
.sub-status-paused   { background: #525252; color: #fff; }
.sub-tag             { background: #b45309; color: #fff; }

.sub-renewal-soon { color: #dc2626; font-weight: 600; }
.sub-renewal-ok   { color: inherit; }
```

The status colours roughly match the Notion screenshot you shared — tweak to taste. The hover state and the `<<colour …>>` macros pick up your active TW palette so it stays consistent in light/dark mode.

### 6.3 — `Subscriptions` (the main view tiddler)

```wikitext
\import [[$:/my/subs/macros]]

! Subscriptions

<$let
  total-monthly={{{ [tag[subscriptions]!field:status[Canceled]] :map[<sub.monthly-equiv>] +[sum[]fixed[2]] }}}
  total-yearly={{{ [tag[subscriptions]!field:status[Canceled]] :map[<sub.yearly-equiv>] +[sum[]fixed[2]] }}}
  active-count={{{ [tag[subscriptions]!field:status[Canceled]count[]] }}}
>

''<<active-count>> active'' — ''<<total-monthly>>/mo'' (~''<<total-yearly>>/yr'')

</$let>

<table class="sub-table">
<thead>
<tr>
  <th>Name</th>
  <th>Status</th>
  <th>Tags</th>
  <th>Billing</th>
  <th>Renewal</th>
  <th class="num">Amount</th>
  <th class="num">Monthly</th>
  <th class="num">Yearly</th>
</tr>
</thead>
<tbody>
<$list filter="[tag[subscriptions]sort[title]]">
<tr>
  <td><$link to=<<currentTiddler>>><<currentTiddler>></$link></td>
  <td><<sub.status-pill {{!!status}}>></td>
  <td>
    <$list filter="[all[current]tags[]] -[[subscriptions]]" variable="t">
      <<sub.tag-pill <<t>>>>
    </$list>
  </td>
  <td>{{!!billing-frequency}}</td>
  <td>
    <$list filter="[all[current]get[renewal-date]!is[blank]]" variable="_" emptyMessage="—">
      <span class={{{ [<sub.days-until-renewal>compare:integer:lt[14]then[sub-renewal-soon]else[sub-renewal-ok]] }}}>
        <$view field="renewal-date" format="date" template="DDth MMM YYYY"/>
      </span>
    </$list>
  </td>
  <td class="num">{{!!currency}} <$view field="amount"/></td>
  <td class="num"><$text text={{{ [<sub.monthly-equiv>fixed[2]] }}}/></td>
  <td class="num"><$text text={{{ [<sub.yearly-equiv>fixed[2]] }}}/></td>
</tr>
</$list>
</tbody>
</table>
```

What this gives you out of the box:
- All `subscriptions`-tagged tiddlers, alphabetically.
- A status pill and category pills per row.
- Amount in original billing units, plus computed monthly + yearly equivalents.
- Renewal date, with red highlighting if it's within the next 14 days.
- A header with totals — only counting `Active`/`Trial`/`Paused`, never `Canceled` (the `!field:status[Canceled]` clause).

### 6.4 — `$:/_EditTemplate/subscription` (optional, nicer editing)

If you want a structured editor when you open a subscription tiddler in edit mode, add this and tag it `$:/tags/EditTemplate` — but cascade-condition it so it only shows for `subscriptions`-tagged tiddlers (use the EditTemplate cascade introduced in 5.3). I'd skip this for v1; the default editor with explicit field-name input boxes is fine to start.

---

## 7. Phased roadmap

| Phase | Scope | Effort |
|---|---|---|
| **P0 — schema clean-up** | Pick the field names from §4. Migrate your existing `subscriptions`-tagged tiddlers to use them consistently. | 30 min once-off |
| **P1 — MVP table** | Paste in the four tiddlers from §6. Verify totals are right. | 1 hour |
| **P2 — filters & sort** | Add a status filter (`<$select>` bound to a state tiddler), a "by next renewal" sort toggle, and a "show cancelled?" checkbox. | 1 hour |
| **P3 — alarms layer** | Install [TiddlyTools/Time/Alarms](https://tiddlytools.com/#TiddlyTools%2FTime%2FAlarms), [Calendar](https://tiddlytools.com/#TiddlyTools%2FTime%2FCalendar), `Ticker` and `action-timeout.js`. Auto-create alarms from each subscription's `renewal-date`. | 2 hours |
| **P4 — currency normalisation** | Add a `$:/my/subs/exchange-rates` data tiddler so you can compare USD subs against AUD ones. Multiply in the `sub.monthly-equiv` function. | 1 hour |
| **P5 — analytics** | Charts? Cost-per-category breakdown? "How much have I spent on Netflix lifetime?" using `started-date`. | open-ended |

P0–P2 is the version that already replaces the Notion table. P3 is the bit Notion doesn't do at all — actual scheduled alarms.

---

## 8. Risks & callouts

- **5.4.0 is brand new** — even native code can hit edge cases. Keep nightly backups of your wiki folder during this build (you're on Node.js single-file-per-tiddler, so just `git init` the directory if you haven't already).
- **Don't trust filter results silently.** The `daysuntil` operator's behaviour around blank fields varies by version — the `!is[blank]` guard above is deliberate. If you see `NaN`s in the table, that's almost always a missing field on a tiddler.
- **Don't put real card numbers in tiddlers.** Last-4 only. If your `tiddlers/` folder ever leaks (shared backup, sync misconfiguration, accidental commit), you don't want to be on the hook.
- **Watch Shiraz's roadmap.** If Mohammad ships a 5.4-compatible build, the option of *adding* Shiraz's table on top of your data (which is already in clean fields) becomes a low-cost upgrade — your tiddlers don't need to change. That's another reason to keep the data layer plugin-independent.
- **Forum follow-up:** worth posting back on [your thread](https://talk.tiddlywiki.org/t/subscriptions-tracker-in-tiddlywiki/12631) once you've got an MVP — Sunny, Springer and Eric have all engaged with this and would likely refine it further.

---

## 9. Open questions for you

A few decisions I'd want your input on before going further:

1. **Multi-currency** — do you have subs billed in USD and AUD both? If yes, P4 moves up.
2. **Trials** — do you want a separate workflow for "this trial ends in N days, decide before then"? That's a slightly different UX from a recurring sub.
3. **Historical view** — interested in tracking total-spent-to-date per vendor, or just current-state?
4. **Family/shared subs** — any need to record "this is split with X person"?

Answers to those nudge the schema in §4 (`shared-with` field, `trial-ends` field, etc.) and it's much cheaper to add them on day 1 than to migrate later.
