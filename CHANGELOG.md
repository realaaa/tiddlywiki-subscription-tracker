# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.10] - 2026-05-09

### Fixed
- **Convert to Subscription is now actually in the ▾ dropdown by default.** The shipped visibility-config shadow at `$:/config/ViewToolbarButtons/Visibility/<button-title>` had its text stored as `"hide\n"` (trailing newline) because it was authored as a `.tid` body and the file ended with a newline. TW's main-toolbar gate `:filter[lookup[]!match[hide]]` and the dropdown's `<$reveal type="match" text="hide">` both use **strict equality** — `"hide\n" !== "hide"`. So both gates failed: the button stayed in the main toolbar (the stray ⊕ icon) and never appeared in the dropdown alongside core actions. Switched the .tid to field-form (`text: hide` as a header field, no body) so the text is exactly `"hide"`. Verified with a render probe: lookup value is now `"hide"` (4 chars), toolbar gate output is empty (button hidden), dropdown gate output is 1 (button shown). Closes [#4](https://github.com/realaaa/tiddlywiki-subscription-tracker/issues/4).

### Notes for upgraders
- Users on v0.1.6–v0.1.9 who **never** enabled the button via **More → Tools** will see the button move from the main toolbar into the dropdown automatically when they upgrade to v0.1.10. No cleanup needed.
- Users who **did** enable the button via Tools (per v0.1.6's old README) still have a real-tiddler override at the same config path with text `show`. That override still wins over the now-correctly-shipped shadow `hide`. Delete the override tiddler manually one time — the README's "Upgrading from v0.1.6" callout walks through the path.

## [0.1.9] - 2026-05-09

### Changed
- Convert button label is now **Convert to Subscription** (capital S on Subscription) — applied to caption, aria-label, and the button text. User preference, sentence-cased noun reads better in the dropdown alongside TW core actions like `clone`, `delete`, `info`.

### Documentation
- README "Convert an existing tiddler" section gains an **Upgrading from v0.1.6** callout. Anyone who followed v0.1.6's older README and enabled the button via **More → Tools** will have a leftover real-tiddler override at `$:/config/ViewToolbarButtons/Visibility/$:/plugins/realaaa/subscription-tracker/buttons/convert-to-subscription` with text `show` — which survives plugin upgrades and pins the button to the main toolbar instead of letting the shadow default (`hide`, which routes it into the ▾ dropdown) take effect. README now tells users to delete that override tiddler one time.

## [0.1.8] - 2026-05-09

### Fixed
- **Convert to subscription no longer wipes existing tags.** Critical data-loss bug introduced in v0.1.6 (and not actually fixed in v0.1.7): the button used `<$action-listops $field="tags" $subfilter="+[<tagname>]"/>`. I had `+[X]` semantics wrong — in TiddlyWiki filter syntax, `+[X]` doesn't mean "add X to the list", it means "**pipe** the previous output as input to filter `[X]`". The widget internally builds the filter `[all[]] +[X]`: `[all[]]` returns the existing tags list, then `+[X]` pipes those tags into filter `[X]` which returns just X regardless of input. Result: every existing tag gets dropped, only the configured subscription tag remains. User report: "BUT - it replaced ALL existing tags with ONE new tag sub - this is DATA LOSS". Closes [#3](https://github.com/realaaa/tiddlywiki-subscription-tracker/issues/3).
- Switched the action to use the purpose-built `$tags` parameter with no-prefix filter: `<$action-listops $tags="[{$:/.../config/settings!!tag-name}]"/>`. The listops widget's `$tags` handler computes `stringifyList(oldtags) + " " + filter`, so the full filter for a tiddler tagged `[Entertainment, Streaming]` becomes `[[Entertainment]] [[Streaming]] [<tag-name>]`. Multiple no-prefix runs union with de-dup, producing `[Entertainment, Streaming, <tag-name>]`. The widget also short-circuits the field write when the new tag list is identical (after sort) to the old one, so re-clicking on an already-converted tiddler is a no-op.

## [0.1.7] - 2026-05-09

### Fixed
- **Convert to subscription** now actually appends the configured tag. The button in v0.1.6 referenced `<subs.tag-name>` via `\import [[macros]]`, but `subs.tag-name` is defined inline in `views/main.tid`, not in `macros.tid` — so the function was out of scope in the button's tiddler. Both the gate filter and the listops subfilter silently evaluated to empty, which is why the button rendered (gate failed open) and set the four core fields, but never added the tag. Switched to text-reference syntax `{$:/.../config/settings!!tag-name}` directly in both the gate filter and the subfilter — no function-scope dependency.

### Documentation
- README "Convert an existing tiddler" section rewritten. The button is **already** in TiddlyWiki's overflow dropdown by default (the down-arrow ▾ icon next to edit/close) — TW's `$:/core/ui/Buttons/more-tiddler-actions` automatically lists every ViewToolbar button whose visibility config is `hide`, which is exactly what the plugin ships. So the previous instructions to "enable via More → Tools" were misleading: enabling promotes the button from the dropdown into the main toolbar, useful only for bulk-onboarding sessions. Default access is one click in the dropdown.

## [0.1.6] - 2026-05-09

### Added
- **Convert to subscription** view-toolbar button. Adds the configured subscription tag and pre-fills core fields (`status=Active`, `billing-frequency=Monthly`, `currency=<display-currency>`, `renewal-date=today+30days`) on existing tiddlers in one click, so vendor tiddlers (e.g. an existing `Netflix` note) can be converted without losing their body or other fields. Hidden by default to avoid cluttering toolbars; enable per-user via **More → Tools**.

### Documentation
- README: new **Convert an existing tiddler to a subscription** section walks through enabling the button and the conversion behaviour.
- New `CHANGELOG.md` (this file) covering all releases from v0.1.1 onward.

## [0.1.5] - 2026-05-09

### Added
- The **+ New subscription** button now creates a fully-populated tiddler instead of a near-empty stub. Defaults: `status=Active`, `billing-frequency=Monthly`, `currency=<display-currency>` (read from `config/settings`), `renewal-date=today+30days`, plus empty placeholders for `amount`, `trial-ends`, `vendor-url`, `cancel-url`, `payment-method`.
- New JS filter operator `[daysfromnow[N]]` returns now + N days as a TiddlyWiki timestamp string. Self-contained ~10-line module at `modules/daysfromnow.js`. Added because TW 5.4 core has no date-arithmetic filter ops.

## [0.1.4] - 2026-05-05

### Added
- Dedicated docs tiddler `$:/plugins/realaaa/subscription-tracker/docs/editing-fields` ("How to edit plugin settings"), exposed as a second tab in the plugin info view alongside `readme`.

### Changed
- `config/settings` body trimmed to a one-line warning + link to the new docs tiddler + the field reference table.
- `.gitignore`: anchored `docs/` rule to `/docs/` so it only matches the repo-root internal-working-docs folder, not nested `docs/` folders inside plugin source.

## [0.1.3] - 2026-05-05

### Changed
- Expanded the `config/settings` tiddler body with step-by-step instructions on how to edit plugin settings via the field editor (4-step click path + verification snippet + "common mistake" callout). Superseded in v0.1.4 by extracting these to a dedicated docs tiddler.

## [0.1.2] - 2026-05-05

### Fixed
- **Drag-drop import of the dist JSON now actually works.** v0.1.1's release artifact was built with `--savetiddler`, which writes the inner plugin payload `{"tiddlers": {...}}` — that's the shape that lives **inside** a plugin tiddler's `text` field, not a TiddlyWiki import bundle. Drag-drop import showed an empty preview and silently installed nothing. Switched to `--rendertiddler $:/core/templates/exporters/JsonFile` with an `exportFilter` variable, which produces the correct 1-element-array bundle. Closes [#1](https://github.com/realaaa/tiddlywiki-subscription-tracker/issues/1).
- README install Option B (Node-mode) rewritten — the previous symlink/copy recipe (`cp -R plugins/realaaa /your-wiki/plugins/realaaa`) didn't work because the wiki's local `plugins/` folder is flat. Two correct shapes now documented: `TIDDLYWIKI_PLUGIN_PATH` (with publisher folder + `tiddlywiki.info` entry), or flat drop into the wiki's local `plugins/` (without publisher folder + no `tiddlywiki.info` entry).

### Changed
- `bin/test-build.sh` now asserts the import-bundle shape explicitly (1-element array, plugin tiddler, payload stringified into `text` field) so a regression like #1 cannot recur silently.

## [0.1.1] - 2026-05-04

### Added
- Initial public release. v1 feature set: Notion-style subscriptions table; multi-currency monthly + yearly totals (single configurable display currency); render-time auto-rolled renewal dates (no field churn); trial countdown; structured EditTemplate cascade for `subscriptions`-tagged tiddlers; status, sort, and tag filters; **+ New subscription** button.
- Two small JS filter modules (`daysuntil.js`, `nextrenewal.js`) to fill in date math missing from TW 5.4 core.

[Unreleased]: https://github.com/realaaa/tiddlywiki-subscription-tracker/compare/v0.1.10...HEAD
[0.1.10]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.10
[0.1.9]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.9
[0.1.8]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.8
[0.1.7]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.7
[0.1.6]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.6
[0.1.5]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.5
[0.1.4]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.4
[0.1.3]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.3
[0.1.2]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.2
[0.1.1]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.1
