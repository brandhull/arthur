# Changelog

All notable changes to Arthur. Versioning rules are in `VERSIONING.md`.
Sections: **Added**, **Changed**, **Fixed**, **Removed**.

## [Unreleased]

## [1.0.1] - 2026-10-10

### Changed
- The splash screen holds for about 10 seconds instead of 5.

### Fixed
- ArthurBar's Quick Task and Quick Capture hotkeys each open their own panel
  (both used to open Quick Capture).
- Seneca now reads every row in the table, not just the first 200.
- Error messages in Quick Capture, Quick Task, and ArthurBar's Quick Capture
  clear when you try again, instead of lingering after a later success.
- Document capture no longer creates a duplicate page when a retry follows a
  failed body save, and its folder list refreshes each time it's opened
  instead of loading once per app run.

## [1.0.0] - 2026-10-08

First versioned release; a baseline of everything built so far.

### Added
- Mac sidebar layout (collapsible, resizable), mirrored on iPad landscape;
  iPhone/iPad portrait use a drawer. One centered quick-add modal everywhere.
- Quick Capture for Craft (destination search, sub-pages, optional separator)
  and Baserow rows; Rocks, Tasks, and Reflection tabs.
- Search Craft: natural-language Q&A over Craft using Claude with its own
  search/read tools.
- Document quick-add: create a new Craft page in a chosen folder.
- Splash screen showing a rotating Seneca quote from Baserow, biased toward
  quotes not shown recently.
- Settings synced across devices through iCloud key-value storage.
- ArthurBar menu-bar app: Quick Task and Quick Capture panels with
  configurable global hotkeys.
- Editor: hanging indent and auto-continue for `- ` bullets and `1. `
  numbered lists (Return continues, Return on an empty item exits).
- Version and build number shown in Settings and ArthurBar's menu.

### Changed
- All iOS/iPadOS text standardized to one size; borders thinned app-wide.
- Appearance (System/Light/Dark) is now per-device, not synced.

### Fixed
- Rocks and Reflection saves add the new text before deleting the old, and
  keep your draft open if a save fails (previously a failed save could leave
  the page empty).
- Settings no longer clears the Seneca table when the table fetch fails.
- Seneca rotation no longer skips a quote or queues duplicates on refill.
- Spellcheck now shows on Mac; text no longer vanishes mid-typing on iPad.
- Force Sync and pull-to-refresh now refresh Quick Capture's document list.
