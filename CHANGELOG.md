# Changelog

All notable changes to Arthur. Versioning rules are in `VERSIONING.md`.
Sections: **Added**, **Changed**, **Fixed**, **Removed**.

## [Unreleased]

## [1.9.0] - 2026-11-26

### Added
- ArthurBar: Clip Screenshot. One hotkey (⌥⌘4 by default, rebindable), drag
  over part of the screen, and the picture is appended to the clip page.
  Escape cancels. The clipboard is untouched unless sending fails. Needs
  Screen Recording permission. Mac only.

## [1.8.0] - 2026-11-26

### Added
- ArthurBar: Clip Selection sends images. Copy a screenshot or picture, then
  press the clip hotkey with nothing selected, and it is appended to the clip
  page. The image is shrunk to a JPEG that fits Craft's request limit
  (images under 100 px on a side are refused).

### Fixed
- iPhone: the hide-keyboard button now has even space around its icon on all
  sides.

## [1.7.1] - 2026-11-24

### Added
- iPhone and iPad portrait: swipe right from the left edge of the screen to
  open the navigation panel; the panel follows your finger, and dragging it
  left closes it. The hamburger button and tapping outside still work.

## [1.7.0] - 2026-11-24

### Added
- ArthurBar: Clip Selection. Select text in any app, press a hotkey (⌥⌘S by
  default, rebindable) and it is appended as plain text to a chosen clip page
  in Craft, with a small quiet toast as confirmation. Grabs the selection
  through the Accessibility API, falling back to a synthetic ⌘C that restores
  the clipboard. If nothing is selected it uses the clipboard; if the save
  fails the text is copied to the clipboard. A Recent Clips submenu lists the
  last 8. The clip page picker has a Refresh button to pull newly created
  pages from Craft. Mac only.

### Changed
- ArthurBar's Hotkeys window is now Settings (clip page, Accessibility status,
  hotkeys) and follows Arthur's light/dark choice instead of always dark.

## [1.6.7] - 2026-11-24

### Changed
- Append Page: a chosen sub-page now shows the page it lives in (a second
  line under its title; a top-level page shows its folder). The collapsed
  Destination bar reads "Parent › Sub-page" and the confirmation names both.

## [1.6.6] - 2026-11-23

### Changed
- New Task layout in the Destination card: Inbox picker first (no label),
  then the "Set a due date" box (no label), then Save. The card is taller for
  tasks so the Inbox picker is no longer cut off. On Mac the date picker sits
  beside the checkbox.

## [1.6.5] - 2026-11-18

### Changed
- Quick Capture: Save moved out of the writing panel into the Destination
  card, bottom right under the fields. It's always there, dimmed until there
  is something to save.
- Destination card: while expanded, the header shows only the chosen page,
  folder or table; the destination type is already in the picker below.

### Fixed
- iPhone: the date in the top bar no longer wraps. The eye and light/dark
  buttons are slightly narrower, and the date keeps one line (shrinking a
  little only if it must).

## [1.6.4] - 2026-11-15

### Changed
- Save and Push show just the word, no icon.
- iPhone: the keyboard-down button is a rounded rectangle matching the
  Destination card, on a keyboard-styled strip with room around it.

## [1.6.3] - 2026-11-12

### Changed
- Save and Push are outlined in the icon's subtle blue (#36568A) with a fill
  matching the current light or dark background, instead of a solid blue fill.

## [1.6.2] - 2026-11-12

### Changed
- Save and Push buttons use the most subtle of the app icon's three blues
  (#36568A) with white text.

## [1.6.1] - 2026-11-12

### Changed
- Save (Bits, Reflection, Craft pages, tasks) is now right-aligned, matching
  Push for Baserow, and both use Arthur's blue.

## [1.6.0] - 2026-11-11

### Added
- Offline queue, stage 2: New Craft Page, Craft tasks and Baserow rows now
  queue when the device is clearly offline, like Bits, Reflection and Append
  Page. A new page that was created but whose body didn't land resumes on the
  same page instead of creating a duplicate. A task that fails for another
  reason now keeps its text on screen with the error, instead of vanishing.
- iPhone: a keyboard-down button above the keyboard in the capture text box,
  and dragging the text down dismisses the keyboard.

## [1.5.2] - 2026-11-11

### Changed
- iPhone: the Destination bar and picker use short names (Bits, New Page,
  Append Page, New Task, Reflection, Baserow). The destination type never
  truncates; a chosen page, folder or table follows it and gives way first.
  Mac and iPad keep the full names.

## [1.5.1] - 2026-11-11

### Changed
- The collapsed Destination bar stays on one line: the "Destination" label
  never wraps, the description truncates in the middle, and a new page shows
  just its folder's name. With nothing chosen it shows only the destination
  type (no "choose a page" hint). Long page and folder rows truncate too.

## [1.5.0] - 2026-11-11

### Changed
- One capture screen. The Destination card at the bottom now chooses where
  the text goes: Append Craft Page (search, with sub-pages), New Craft Page in
  any folder or sub-folder, Reflection, Bits, a Craft task, or Baserow. The
  collapsed bar shows the current target. Save sits above the card.
- A Craft page stays selected after Save; Bits, Reflection and task snap back
  to Craft page after sending.
- Settings has a "Quick Capture opens to" choice: which destination the app
  starts on and returns to after a one-off send (default: Append Craft Page).
- Baserow: typed text carries into a text field of your choice (remembered per
  table; defaults to one that isn't a "comments" field).
- The sidebar starts closed and lists Quick Capture, Rocks, Bits, Tasks,
  Reflection (no Craft/Baserow sub-rows).

### Removed
- Both "New" buttons (sidebar and the iPhone floating button), the New menu,
  and the separate Bits / Reflection / Document capture screens.

### Fixed
- Craft folders with no document count (e.g. Blog and its sub-folders) were
  missing from folder lists; nested folders now show as "Parent / Child".

## [1.4.0] - 2026-11-09

### Added
- Offline queue (stage 1): Bits, Reflection and Quick Capture to Craft are
  saved to disk when the device is clearly offline, the screen clears, and
  they send in order when the connection returns. A "N waiting to send" pill
  shows what's queued (Copy / Discard, plus Retry if a send fails for another
  reason). Timeouts and server errors are never queued, to avoid duplicates.

## [1.3.1] - 2026-11-08

### Changed
- Quick Capture's Baserow form picks a sensible table for you (the database's
  only table, else the last one you used, else "All") and presets a Source
  field to Arthur when the table has one.
- The iPhone's floating "new" button hides while the keyboard is up.

### Fixed
- Picking a database or table in the Baserow form is instant after the first
  time: it shows the last-known tables and fields right away and refreshes
  behind them. The same applies to the table pickers in Settings.
- Baserow reads time out after 15 seconds and retry once, instead of a stalled
  connection leaving a spinner for up to a minute; if loading still fails, the
  form shows the error with a Retry button.

## [1.3.0] - 2026-10-19

### Added
- Markdown preview: an eye button in the top bar (on Quick Capture's Craft
  side, New Document, and New Reflection) swaps the text box for how the note
  will land in Craft, following Craft's own import rules — blocks and line
  breaks, lists and nesting, checkboxes, dividers, quotes, code blocks, and
  inline bold/italic/code/links/strikethrough/highlight. Quick Capture's
  preview includes the separator when Add Separator is on, and New Document
  shows the first line as the page title.

### Changed
- Bigger menu icons on iPhone and iPad: the hamburger (iPhone, iPad portrait),
  and the sidebar toggle and New button on iPad.

## [1.2.1] - 2026-10-15

### Changed
- The Destination bar in Quick Capture and New Document opens and collapses
  from a tap or click anywhere on it, on every platform, not just the chevron.

### Fixed
- Long notes in Quick Capture, New Document and the other text boxes no
  longer blank out, bounce, or lose the cursor while typing. The list-indent
  code no longer restyles the whole note on every keystroke, and the editor
  uses the older text layout engine that handles long text reliably. ArthurBar's
  Quick Capture panel gets the same engine.

## [1.2.0] - 2026-10-10

### Changed
- New Reflection (from the New menu) is now a full capture screen like New
  Bit and New Document, instead of a small popup. Saving appends to today's
  note and shows the Reflection tab.
- The new-Document screen shows Save as a plain bottom-right button once
  there's a title and a chosen folder, and its error messages show even while
  the Destination card is collapsed.
- The iPhone's floating "new" button hides on every capture screen.

### Removed
- Search Craft: the tab, its Anthropic API key setting, and all its code.

## [1.1.3] - 2026-10-10

### Changed
- The New (quick-add) menu now springs open and closed, growing from the side
  its button is on, instead of a faint fade.
- The menu's rows are text only (icons removed on every platform) and have
  more vertical room.

## [1.1.2] - 2026-10-10

### Changed
- The new-Bit capture screen only shows Save once there's text, as a plain
  button without a surrounding box; the iPhone's floating "new" button hides
  while it's open.

## [1.1.1] - 2026-10-10

### Fixed
- The Mac cursor no longer turns into a text I-beam over cards and buttons
  when a hidden screen's text editor sits underneath.

## [1.1.0] - 2026-10-10

### Added
- Bits tab (between Rocks and Tasks): your Bits from Baserow as cards, newest
  50 first, each with Edit / Copy / Archive / Delete; tap a card's text to edit
  it in place with Cancel / Save. An Archive view lists archived Bits with
  Copy / Restore / Delete. Pick the Bits table in Settings.
- "Bits" row in the New (quick-add) menu: a blank capture screen that saves a
  new Bit and then shows the Bits list.

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
