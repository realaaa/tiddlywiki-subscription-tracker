# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/realaaa/tiddlywiki-subscription-tracker/compare/v0.1.6...HEAD
[0.1.6]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.6
[0.1.5]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.5
[0.1.4]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.4
[0.1.3]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.3
[0.1.2]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.2
[0.1.1]: https://github.com/realaaa/tiddlywiki-subscription-tracker/releases/tag/v0.1.1
