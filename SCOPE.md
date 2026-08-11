# Arthur — Scope Doc

Status: **v1 built, iterating on UI/UX feedback.**

## What this is

A personal agenda + daily note app, native on Mac/iPad/iPhone, inspired by [Parchment](https://apps.apple.com/us/app/parchment-agenda-daily-note/id6779987526). Unlike Parchment, no calendar *data* integration (no reading/creating events) — the calendar icon is just a shortcut launcher to the OS's own Calendar app. Three sections on the main screen:

1. **Filter bar** — All / Overdue / Today / Tomorrow, segmented control.
2. **Task list** — pulled live from Craft, filtered per the bar above, with a "+" to quick-add a task into one of several configured Craft "inbox" documents.
3. **Daily note** — a text box that autosaves (debounced) into Craft's Today daily note as you type.

Craft is the only backend. No Baserow, no separate database — this app is a native front end over the Craft MCP link endpoint, the same integration mechanism [[craft-quick-capture-app]] already proved out from a Swift app.

## Precedent apps

- **[[craft-quick-capture-app]]** (`~/Projects/craft-quick-capture`) — proves a native Swift app can call the Craft MCP link endpoint directly via raw JSON-RPC POST (stateless, no handshake, single-event SSE response). This app extends that same client to task commands (`tasks list`, `tasks add`) instead of just `blocks`/`documents`.
- **[[project_cannon-app]]** / **[[project_winston-app]]** — establish the "personal reader/tracker with PIN-free native shell" visual pattern, though those are web apps; not directly reused here since this is native SwiftUI, but worth a glance for typography/spacing conventions.
- **[[project_clark-app]]** SCOPE.md — format precedent for this document.

## Main screen layout (from Brandon's Parchment screenshots + walkthrough)

**Top bar**: on iPhone/iPad, calendar icon left-aligned (opens the device's default Calendar app — `calshow://` on iOS/iPadOS; just a launcher, no event data ever touches Arthur), Settings icon right-aligned (opens Settings sheet: Craft MCP link field, light/dark mode override). **Mac has no calendar icon** — intentional, confirmed: Brandon keeps his calendar open in a browser tab on Mac already, so the larger screen makes an in-app shortcut redundant there. Mac toolbar is just Settings (and whatever native window chrome SwiftUI gives for free).

**Filter bar**: segmented control, four options — **All / Overdue / Today / Tomorrow**. "All" shows every fetched task unfiltered; the other three are the client-side date buckets already scoped. (Supersedes the earlier three-bucket-only plan — add "All" as a fourth display mode over the same fetched data, no new API calls needed.)

**Task list**: rows for the active filter, "+" button at the section's trailing edge to add a new task.

**Daily note**: text box at the bottom, autosaves as you type (debounced) straight into Craft's Today daily note — resolves the earlier open question of debounce-vs-explicit-save in favor of autosave, matching how Brandon described it.

**Icons**: SF Symbols only, no emoji anywhere in the UI (matches what Parchment's screenshots show, and Brandon's explicit preference).

## Adding a task (from the "+" button)

- Sheet/modal with: task text, **optional** due date, **optional** destination picker among the configured inbox documents.
- Both fields optional with sensible defaults: no due date = task has none (shows in "All" only, not Overdue/Today/Tomorrow); no destination chosen = falls back to a designated default inbox (first-configured document, changeable in Settings).

## Task row interactions

- **Tap checkbox** → mark task done inline (writes back to Craft via `tasks update --id <id> --state done`).
- **Tap task name/text** → inline edit mode for the task text.
- **Long-press (tap and hold)** → confirmation prompt, then opens the task's exact block in Craft via its `clickableLink` (`craftdocs://open?spaceId=...&blockId=...`, fetched via `blocks get --fetchMetadata`). The confirmation step exists so a long-press doesn't accidentally yank you out of Arthur into Craft.

## Typography

- **Noto Serif** (Google Fonts, SIL Open Font License 1.1) — free for commercial/app use, bundle-and-embed permitted, just can't be sold standalone or re-licensed. Bundle the font files directly in the app rather than relying on system availability (Noto Serif isn't a system font on iOS/macOS/iPadOS).

## Design language

Aesthetic matters more for this app than for past projects — it's the daily-use surface, not a utility.

- **Palette**: lifted from the Bits app icon (`~/Projects/bits/public/icon-512.png`) — near-black dark background with a blue accent that fades across three tones (bright `#5b9bff` → mid `#3d6db3`-ish → dark `#2e4d78`-ish). Same blue family as Bits/Cannon/Winston's `#2563eb` light / `#5b9bff` dark accent, just applied here as the whole visual identity rather than a single accent color.
- **Dark mode**: near-black background (matches the icon), blue accent scale for hierarchy (brightest = primary/active, dimmer = secondary/completed).
- **Light mode**: explicitly **not** pure white — a slight off-white background (something like `#F7F6F3`–`#FAF9F6` range, warm-neutral rather than cool-gray) is easier on the eyes and what Brandon wants here. Same blue accent scale on top of it. Exact hex to be tuned visually once in Xcode with real content, not locked on paper.
- Applies consistently across all three platforms and the Mac menu bar quick-add panel — one shared color asset catalog, not per-platform tweaks.

## Complexity vs. past projects

Rough ranking, least to most complex to build:

**Bits** (web PWA, ~880 lines) < **Cannon/Winston** (web PWA, ~1,100–1,250 lines, Baserow schema) < **craft-quick-capture** (native Swift, Mac-only, ~2,000+ lines — drag/drop images, table capture, multi-space, settings) ≈ **Arthur**, roughly the same order of magnitude as craft-quick-capture but the effort shifts to a different axis:

- **Narrower feature surface than craft-quick-capture**: no image drag/drop, no table/collection capture, no multi-space support planned. The Craft-client logic itself (tasks + daily note only) is simpler.
- **Wider platform surface**: craft-quick-capture is Mac-only. Arthur is Mac + iPad + iPhone from one codebase, plus the menu bar companion — that's effectively 3–4 UI surfaces to lay out, test, and keep visually consistent, where every past app (including craft-quick-capture) shipped to exactly one surface (or, for the web apps, one responsive layout that degrades gracefully rather than needing distinct native layouts).
- **New axis: dedicated visual-design effort.** None of the prior apps had a custom aesthetic beyond "reuse Cannon/Winston's shell" or "functional menu bar utility." Arthur's off-white/dark-blue identity, tuned per-platform (compact iPhone agenda vs. iPad split view vs. Mac window), is real hours that don't have a direct precedent to copy wholesale — expect this to be the single biggest time sink relative to the other apps, more than the Craft integration itself (which is largely proven out already via craft-quick-capture).
- **Net**: comparable total effort to craft-quick-capture, but weighted toward SwiftUI layout/polish across three targets rather than toward API/networking edge cases (those are mostly de-risked already).

## Architecture

- **Single Xcode project, SwiftUI multiplatform** targeting macOS + iOS + iPadOS from one shared codebase (this is a native Swift app, not a PWA — matches Parchment's shape and reuses [[craft-quick-capture-app]]'s Swift/Craft-client code directly, more than a web app would).
- **Craft client**: a small Swift package (lift-and-extend from craft-quick-capture's networking layer) wrapping the MCP link JSON-RPC endpoint. Commands needed:
  - `tasks list --scope active` / `--scope upcoming` — active covers overdue+today (task date <= today), upcoming covers everything from tomorrow on; bucket client-side into Overdue / Today / Tomorrow / Later by comparing each task's date to local `today`.
  - `tasks add --markdown <text> [--schedule <date>] [--deadline <date>]` targeted at one of the pre-configured destination documents (see below).
  - `blocks get --date today` to fetch today's daily note rootBlockId, then `blocks add --id <id> --markdown <text> --position end` to append the note.
  - `documents resolve-link <url>` — one-time setup step to turn the inbox doc URLs (pasted once, in Settings) into stable rootBlockIds, cached locally.
- **No cross-device content sync needed** — every device hits Craft directly and Craft is the single source of truth, so there's no "which device has the latest copy" problem the way Clark's Baserow layer had to solve.
- **Settings sync via iCloud** (key-value store or CloudKit) for the inbox-document rootBlockIds + display names, so configuring them once on Mac shows up on iPad/iPhone. Requires the Apple Developer Program renewal (see Distribution) — iCloud entitlements aren't available on a free personal team for anything beyond local debug builds.

## Task filtering (v1 scope decision)

Craft's `tasks list` has no folder filter — only `--scope active|upcoming|inbox|logbook|document|all`. Folder filtering would require fetching a broader task set and cross-referencing each task's parent document against a folder list, which isn't a small addition.

**Decision: v1 ships due-date filtering only** (All / Overdue / Today / Tomorrow — see Main screen layout above). Folder filtering is a fast-follow, not v1.

## Adding tasks (configured inbox documents)

- Settings screen: paste in each Craft doc URL, resolved via `documents resolve-link` into rootBlockIds + cached display names (e.g. "Personal", "Work", "Someday"); pick which is the default.
- Add-task sheet (see above): text + optional due date + optional destination, defaulting to the designated inbox. Submits via `tasks add --markdown <text> [--schedule <date>]` targeted at that document (or `blocks add` with `- [ ]` markdown if `tasks add` turns out to need document targeting we haven't confirmed — flag this as a build-time API check, not yet verified against the live MCP schema for a `--document` flag on `tasks add`).

## Daily note

- On load, `blocks get --date today` to find/create today's daily note block, show its current content (read-only preview or none) plus the autosaving append box.
- Autosave, debounced (confirmed, not explicit-save): `blocks add --id <dailyNoteId> --position end --markdown <text>` fires after a pause in typing.
- No local caching of past notes — this app only ever writes to *today's* note, matching the "no calendar, just today" scope from Parchment's Daily Note panel.

## Mac menu bar quick-add

- Reuses [[craft-quick-capture-app]]'s pattern directly: `LSUIElement` menu bar app, global hotkey opens a small panel, text field + destination picker (the same inbox docs), submits via the same Craft client.
- This is in addition to the main windowed app (agenda + daily note), not a replacement — the main app is still the primary surface on all three platforms.

## Distribution

- Apple Developer Program membership is currently **expired**. Free personal team signing means installs on physical iPhone/iPad expire after 7 days and need re-building/re-installing from Xcode each time.
- Brandon is willing to renew ($99/yr) once the app is built and ready to compile — do the build against a free personal team first, renew before final install/iCloud setup.
- iCloud settings sync (inbox-doc config) needs the paid account's entitlements — build this behind a flag or stub it with local-only `UserDefaults` first, wire up real `NSUbiquitousKeyValueStore`/CloudKit once the account is active.

## Explicitly out of scope for v1

- Folder-based task filtering (due-date buckets only; folder filtering is v2)
- Calendar/event integration (explicitly not wanted, unlike Parchment)
- Home screen widgets / Lock Screen widgets on iOS/iPadOS (Mac menu bar quick-add only, for now)
- Multi-user / multi-space Craft support beyond whatever single space the inbox docs live in
- Editing or reading past daily notes (only today's, append-only)
- Offline mode — app requires network to reach Craft's MCP endpoint, same constraint craft-quick-capture already accepts

## UI/UX revision round 2 (2026-07-24)

Applied after seeing v1 running:
- **Palette**: `#011528` for the "Arthur" title, both pill buttons, and the
  Tasks/Daily Note headings; light mode background changed from warm off-white
  to a neutral light grey (`#F3F3F5`). Title/heading sizes bumped 150% (20→30,
  16→24). Dark mode text is light grey, not white; two selectable dark
  backgrounds (Navy `#011528` / Charcoal, default) via Settings.
- **Daily Note redesigned**: now shows the actual note fetched from Craft
  (read-only) instead of an always-editable autosave box; a rounded pill "Add"
  button opens a compose sheet that appends and reloads. Resolves the old
  "clears mid-sentence" risk from the autosave-on-type design.
- **Rounded pill buttons** (icon + label, `#011528`/light-grey rounded rect)
  replace the bare floating "+" for both Add Task and Add Note.
- **Draggable Tasks/Daily Note divider**, position persisted to
  `Config.dividerFraction`, restored on next launch.
- **Splash screen**: "Be Grateful. Be Smart. Be Clean. Be True. Be Humble. Be
  Prayerful." fades through in sequence on cold launch, ~1s per phrase.
- **Settings**: added dark-style (Navy/Charcoal) picker and a Force Sync
  button that re-fetches both tasks and the daily note.
- **Sheet fonts**: Add Task / Add Note / Settings were rendering in the system
  sans-serif by default (SwiftUI Form controls don't inherit the main view's
  custom font automatically) — fixed via explicit `.font(Theme.serif(...))` on
  form content plus a global `UINavigationBarAppearance` override for nav
  titles (iOS only; set once at launch after font registration).
- **Quick capture redesign**: dropped the plan to make the Mac menu bar app
  the primary capture surface. Added a floating capture button (bottom-right,
  circular, matches the pill button color) **in the main app**, on all three
  platforms — a third action alongside Add Task and Add Note, not a
  replacement for either. Opens a sheet: free text + a searchable picker
  across **every document in the space** (not just the 3 task inboxes),
  ported from craft-quick-capture's document-list/search/cache pattern
  (`CraftDocument`, `listAllDocuments`, `DocumentStore` with on-disk caching
  and recents). The Mac menu bar quick-add (ArthurBar) stays as-is, unchanged,
  for when Arthur isn't in focus — the two are complementary, not redundant.

## UI/UX revision round 3 (2026-07-24)

- **Force Sync error surfacing fixed**: `refresh()` and `loadDailyNote()` used
  to silently no-op if the Craft link wasn't configured — Force Sync would
  look like it succeeded while doing nothing. Both now set a "No Craft link
  set" error instead. `forceSync()` also clears any stale error before
  running, so a leftover message from a previous failure can't be misread as
  describing the current attempt.
- Confirmed (no change needed): configured-but-failing syncs already surface
  a specific reason via `CraftError` — HTTP status code, Craft's own tool
  error text, or "Unexpected response from Craft" for a parse failure — not a
  generic "something went wrong."
- **Inbox documents vs. Quick Capture, clarified** (no change, just a note for
  future reference): Inbox documents are intentionally a short, fixed list —
  destinations for Add Task, kept small so that picker stays one-tap. Quick
  Capture's document search is the broad, full-space counterpart. The two are
  deliberately different scopes, not overlapping/redundant.

## Real folder structure + a default-inbox bug (2026-07-24)

Brandon's actual Craft setup: dedicated task pages exist for Business
(Business folder), BYUI (BYUI folder), and Church (Church folder) — those
three become the configured inbox docs. Leapcure and Personal are messier and
should keep landing in **Craft's standard inbox**, not a custom doc.

That exposed a real bug: `Config.defaultInbox` fell back to `inboxes.first`
when no default was explicitly set, and Settings auto-set the first-added
inbox doc as the default the moment you added it. Net effect: as soon as
Business Tasks was configured, "Default" would silently become "Business
Tasks" instead of the standard inbox — exactly wrong for Leapcure/Personal
tasks. Fixed:
- `defaultInbox` no longer falls back to `inboxes.first` — unset means
  Craft's standard inbox, full stop.
- Settings no longer auto-assigns a newly added inbox doc as the default.
- The Default picker in Settings now lists "Craft Inbox (standard)" as an
  explicit, selectable option alongside the named docs, so it's a
  conscious choice either way, not an accident of add-order.

**Update, same day**: Brandon went ahead and created dedicated pages for
Personal and Leapcure too — so the real count is 5 inbox docs (Business,
BYUI, Church, Personal, Leapcure), not 3. No code change was needed: the
inbox list was always a dynamic `[InboxDestination]` array, never hardcoded to
3, in the Add Task picker, the Settings list, or the Mac menu bar picker —
only a couple of comments still said "three," fixed for accuracy. Rationale
for having a dedicated page per folder rather than leaning on the standard
inbox + manual filing: "the purpose of this app is quick review, quick add"
— a wrong destination is a cheap fix (move the task in Craft directly), so
optimizing for capture speed over up-front destination precision is the
right tradeoff here.

## Sync cadence (2026-07-24)

Answering "how often does this sync" surfaced a real gap: sync only ran on
cold launch (SwiftUI's `.task` fires once per view lifecycle), pull-to-refresh,
and Settings' Force Sync — **not** when resuming from the background, which is
what "every time I open it" means for most people in practice. Fixed via
`scenePhase` — refresh fires whenever the app becomes active again, in
addition to the cold-launch fetch. Still no scheduled/periodic background
sync (would need the BackgroundTasks framework + entitlements — real work,
not yet justified for a personal app you open manually to check).

All three targets (Arthur-iOS, Arthur-Mac, ArthurBar) build clean and Arthur-iOS
was verified rendering correctly in the iOS Simulator — off-white background,
Noto Serif, blue accent, four-way filter bar, SF Symbols, all matching this doc.
Source lives at `~/Projects/arthur` (ArthurKit package + App + Bar targets,
`project.yml` regenerates `Arthur.xcodeproj` via `xcodegen generate`).

Resolved open items:
- **`tasks add` has no confirmed `--document` flag** — settled by always routing
  destination-targeted adds through `blocks add --id <inboxId> --markdown "- [ ] ..."`
  instead, which is confirmed to work generically on any block ID.
- **Config storage**: a shared JSON file at `~/Library/Application Support/Arthur/config.json`,
  not UserDefaults — Arthur-Mac and ArthurBar are separate bundle IDs and would
  never see each other's UserDefaults domain otherwise. iOS/iPadOS get their own
  copy in-container; cross-device sync is still the planned iCloud follow-up.
- **Noto Serif Regular/Bold are separate static files** with distinct PostScript
  names (`NotoSerif-Regular` / `NotoSerif-Bold`), not one variable-weight family —
  `Theme.serif(_:weight:)` selects the file directly rather than relying on
  SwiftUI's `.weight()` modifier, which doesn't switch files on its own.

Still open, deferred to Brandon's own hands-on pass:
- Real interaction testing (tap-to-edit, long-press-to-confirm, checkbox) —
  remote simulator coordinate mapping proved unreliable during the build
  session; needs verification with real touch/mouse input.
- Craft link + the three inbox documents aren't configured yet — first launch
  needs Brandon to paste his Craft MCP link and inbox doc URLs into Settings.
- Real device installs (signing, 7-day free-tier resign cycle) — per
  "Distribution" above.

## Rough size estimate

Comparable to craft-quick-capture's core (~1,000–1,500 lines for the Craft client + task/note UI), plus SwiftUI multiplatform layout work and the menu bar companion (~300–400 more, mostly reused). Smaller than Clark's e-reader scope — no rendering pipeline, no highlight anchoring, no Baserow schema to design.

## Full code review + iconography + polish (2026-07-24)

Requested review for leanness, cleanliness, and no hardcoded personal
details. Confirmed clean on the personal-data front — no real Craft links,
space/block IDs, or other secrets anywhere in source; only comments
mentioning "Brandon" as design rationale (harmless) and the `com.brandonhull.*`
bundle IDs (normal reverse-DNS convention). Found and fixed real bugs along
the way, verified live against Brandon's actual Craft space each time:

- **Task dates were silently never parsed, at all.** `tasks list`'s plain-text
  output puts an optional `(schedule: YYYY-MM-DD, deadline: YYYY-MM-DD)` line
  *between* the task header and the "in:" container line — confirmed live by
  creating real scheduled/deadlined test tasks (then deleting them). The
  parser never accounted for that line, so `scheduleDate`/`deadlineDate` were
  always nil and Overdue/Today/Tomorrow could never have worked even after
  Brandon started dating tasks in Craft — this was a structural bug, not just
  "empty because no dates exist yet." Rewrote the parser to consume that line
  and extract both dates; verified against the real captured text formats
  with a throwaway test harness (3/3 cases correct) before removing it.
- **Due dates were silently dropped when a task also had a specific
  destination.** `addTask`'s destination path built the `--schedule`/
  `--deadline` command flags and then discarded them entirely, falling back
  to a plain `blocks add` with no date metadata. Fixed by using `blocks add`'s
  response (which returns the new block's ID — confirmed live) to chain a
  follow-up `tasks update --schedule/--deadline` call.
- Settings: deleting an inbox doc that was set as the default left a
  dangling `defaultInboxId` pointing at nothing; now cleared on save.
- Splash screen hardcoded Charcoal as its dark-mode background regardless of
  which style was actually saved in Settings; now reads the real value.
- A few dead/unused imports (`ArthurKit` in `ContentView`/`ArthurApp` where
  nothing from it was referenced) and stale "Default (none set)" wording in
  the Bar target's picker, now consistent with the main app's "Craft Inbox."

**Calendar icon clarification**: iOS/iPadOS has no "default calendar app"
setting at all (only browser and mail support that, since iOS 14) —
`calshow://` always opens Apple's own Calendar app specifically, never a
third-party one like Google Calendar or Fantastical. Worth knowing if
Brandon's actual calendar lives elsewhere.

**Iconography added** (Brandon: "the UI is bland without any iconography"):
- `pencil.and.outline` next to "Tasks", `pencil.and.scribble` next to "Daily
  Note" — same size (`Theme.sectionIconSize`), aligned with the heading and
  the pill button.
- `brain.head.profile` next to "Arthur" in the top bar, playing the native
  SF Symbols `.bounce` effect once when the app opens.
- Required bumping the deployment target to iOS 17 / macOS 14 (`.symbolEffect`
  needs it) — a reasonable trade for a personal app running on current-gen
  devices, not something needing old-OS support.

**Polish fixes from live screenshots, in order**:
- Splash screen now always renders dark-background/grey-text regardless of
  the device's light/dark setting — reads better at any hour, rather than
  flipping to light-navy-on-grey in daytime.
- Fixed a real layout bug: removing the two `Spacer()`s around the Tasks
  empty-state text (to match Daily Note's alignment, per earlier feedback)
  left the section's `.frame(maxHeight: .infinity)` centering its now-short
  content in the tall imposed height — added `alignment: .top` to pin it
  where it belongs.
- The position fix above didn't carry the *styling* — "Nothing here." was
  still the default system font while "Nothing in today's note yet." used
  `Theme.serif(15)`. Matched it (font, leading alignment) so both empty
  states are now genuinely identical in look, not just position.

## Replay splash on tap, iPad windowing, calendar link swap (2026-07-24)

- **Brain icon is now interactive**: tapping it (not just on cold launch) both
  plays the bounce and restarts the full "Be Grateful...Be Prayerful" splash
  sequence — Brandon's own self-talk ritual, on demand. `AgendaView` takes an
  `onReplaySplash` closure from `ContentView` (which owns `showingSplash`)
  rather than owning that state itself.
- **iPad Split View / Slide Over / windowed Stage Manager**: confirmed
  already supported by the existing proportional (`GeometryReader`-based)
  layout with no fixed-width frames anywhere — made it explicit rather than
  implicit by setting `UIRequiresFullScreen: false` in Info.plist. Verified
  live on an iPad Air 11" simulator: renders correctly, uses the extra width
  naturally, no code changes needed beyond the explicit plist key.
- **Calendar icon now opens `https://calendar.google.com`** (a universal
  link — Google Calendar claims it if installed, else falls through to the
  browser) instead of `calshow://`, which only ever opens Apple's own
  Calendar app regardless of what Brandon actually uses day to day.
- Confirmed (no change needed): the "No Craft link set" warning is driven
  entirely by `Config.isConfigured` at call time, not hardcoded — it
  disappears the moment a real Craft link is saved in Settings.

## Device compatibility, memory footprint, platform-default appearance (2026-07-24)

- **Target devices** (iPhone 16 Pro, iPad Pro 12.9" M1, Mac mini M1): no
  compatibility concerns. All three run current OS versions well above the
  iOS 17 / macOS 14 minimums, and the app does nothing hardware-intensive
  (no Metal/GPU rendering, no ML, no video) that would stress even the
  oldest of these chips.
- **Memory footprint measured live, not estimated**: ~32.5MB physical
  footprint (34.2MB peak) for the iOS debug build in the simulator; ~92MB
  RSS for the Mac debug build. Both are lightweight for their platform —
  no image/video caching, no database, just small text data (tasks, one
  daily note, a cached document list of titles/folders).
- **Platform-specific default appearance**: `AppearanceMode.platformDefault`
  resolves at compile time via `#if os(macOS)` — `.dark` on iOS/iPadOS,
  `.light` on Mac — used as `Config`'s default `appearance` value. Only
  affects a fresh install (no `config.json` yet); Settings' System/Light/Dark
  picker still fully overrides it same as before. Verified live on the iOS
  simulator: renders dark even with the simulator's system-level appearance
  set to light, confirming the app-level default is independent of the OS
  setting as intended.

## Mac visual polish + icon (2026-07-24)

Prompted by Brandon actually seeing the Mac window for the first time:
- **Title/heading weight**: full Bold read as "cheap" on macOS. Downloaded
  Noto Serif SemiBold (same OFL family, confirmed available at the same
  GitHub source as Regular/Bold) and switched "Arthur"/"Tasks"/"Daily Note"
  to it via `Theme.serif(_:weight: .semibold)`. Button labels (Add/Cancel/
  Push/Done) intentionally left at full Bold — not what was flagged.
- **Bounded content boxes**: added `ContentBox` (rounded-rect stroke border,
  8pt corner radius, inset 20pt from the section edges) wrapping the task
  list and daily note content, matching Brandon's mockup — previously the
  content bled to the window's full width.
- **App icon**: Brandon wants a Mac icon matching his "Bro" app's style
  (navy squircle, white bold short-name text) shortened to "Art." First pass
  generated programmatically (SF Pro Rounded Heavy on a navy gradient
  squircle, matching `Theme.baseColor`) — rejected; Brandon is providing his
  own icon to work from instead. Not yet wired into the Xcode project.
- **iPad simulator visibility**: not a bug — multiple iPad simulators were
  installed/booted across the session and only one can be the focused panel
  at a time. Re-attaching to the specific iPad Air 11" udid and relaunching
  with the latest build fixed it; content boxes and SemiBold render
  correctly there too.

## Settings window + icon wired in as placeholder (2026-07-24)

- **Mac Settings window fixed**: the native macOS `Form` default style renders
  as an awkward two-column right-aligned-label layout (what Brandon's
  screenshot showed) — applied `.formStyle(.grouped)` to match the cleaner,
  left-aligned, properly-padded grouped-list look, plus an explicit min/ideal
  window size so it doesn't render cramped.
- **App icon wired in from Brandon's `~/Downloads/Art.png`**: his reference
  was only 144×144 (too low-res to upscale cleanly for a 1024×1024 icon set),
  so regenerated at full resolution using the exact recipe he gave — Avenir
  Black, 84pt scaled proportionally from his 144px canvas, same sampled
  gradient colors, plus a lighter highlight band in the top ~20% per his
  follow-up correction (his reference has a subtle lightening there a flat
  linear gradient didn't capture). **Explicitly a placeholder** — Brandon is
  designing an original cross-platform icon later; this unblocks seeing an
  icon in the meantime.
- Wiring required splitting the resources folder: `Assets.xcassets` moved to
  a new Mac-only `App/Resources-Mac` (added only to the Arthur-Mac target in
  `project.yml`) rather than the shared `App/Resources` — the iOS build
  failed otherwise, since Xcode validates any `AppIcon.appiconset` in a
  target's catalog against that platform's idioms, and this one only has
  `"idiom": "mac"` entries.
- Verified via `Info.plist` (`CFBundleIconFile`/`CFBundleIconName` = "AppIcon")
  and the compiled `Assets.car` in the built `.app`, not just visually.

## Even lighter weight, thinner border (2026-07-24)

SemiBold still read too heavy for Brandon's minimalist preference. Downloaded
**Noto Serif Medium** (confirmed available at the same GitHub source as the
other weights) and switched "Arthur"/"Tasks"/"Daily Note" to it —
`Theme.serif(_:weight: .medium)`, one step up from Regular rather than two.
`ContentBox`'s border thinned from 1pt/25% opacity to a 0.5pt hairline at 15%
opacity. Splash screen phrases intentionally left at full Bold (separate,
deliberately impactful display, not "the name and section heads" that were
flagged).

**Bug, same round**: after adding `NotoSerif-Medium.ttf`, rebuilt directly via
`xcodebuild` without first re-running `xcodegen generate` — xcodegen snapshots
a folder's contents into the `.xcodeproj` at generation time rather than a
live folder reference, so the new file silently wasn't included as a build
resource. Result: `Font.custom("NotoSerif-Medium", ...)` couldn't find the
font and SwiftUI fell back to the system sans-serif for every heading using
that weight. Caught by Brandon noticing the wrong font, confirmed by checking
the built `.app`'s `Contents/Resources` directly (font file genuinely
missing), fixed by regenerating before rebuilding. **Lesson for future font/
resource additions to this project: `xcodegen generate` is required after
adding a new file to `App/Resources`, not just after editing `project.yml`.**

## Quick Capture cleanup + regular weight everywhere in dialogs (2026-07-24)

- **`.formStyle(.grouped)`** applied to `CaptureSheet` (the awkward native
  Form layout Settings had, same root cause) plus proactively to
  `AddTaskSheet`/`AddNoteSheet` too, even though Brandon only showed a
  screenshot of Quick Capture — same underlying issue, no reason to wait for
  a second screenshot to fix the other two. All four dialogs (Settings, Add
  Task, Add Note, Quick Capture) now share the same clean grouped-list Mac
  presentation, plus a sensible min/ideal window size each.
- **All bold weight removed from dialog fonts** — "Done"/"Add"/"Push" buttons
  across all four sheets were `Theme.serif(17, weight: .bold)`, now plain
  `Theme.serif(17)` (Regular). Matches Brandon's stated preference for
  minimalism: these are functional buttons, not headings, and shouldn't
  compete visually the way "Arthur"/"Tasks"/"Daily Note" do.

## FAB icon centering + CaptureSheet matching home-screen boxes (2026-07-24)

- **Floating capture button's pencil icon nudged up 2pt** (`.offset(y: -2)`)
  — `square.and.pencil`'s pencil overlay sits low in its glyph box, so true
  geometric centering reads as visually bottom-heavy. Same fix applies on
  both iOS and macOS since it's shared code.
- **CaptureSheet rebuilt without `Form`/`Section`**: the native
  `.formStyle(.grouped)` box styling (used for Settings/Add Task/Add Note) is
  system-drawn and can't be restyled to match `ContentBox`'s thin hairline
  border. Rebuilt Quick Capture's layout by hand — same `Text` + `ContentBox`
  pattern as the home screen's Tasks/Daily Note sections — so all three
  dialogs' bounding boxes are now the exact same border width/opacity as the
  main screen, not just visually similar. Verified live in the simulator.

## Notion-style header, all three platforms (2026-07-24)

Brandon flagged the full-width divider under the filter bar as visually
separating the header from the content it was supposed to belong to — asked
for a better structure rather than just tuning the divider. Rebuilt the top
bar Notion-style, on all three platforms (this is shared code, not
Mac-specific): "Arthur" left-aligned at `Theme.headingSize` (same size as
"Tasks"/"Daily Note", not the larger `titleSize`), same 20/16/12 padding as
the section headings so its left edge lines up with them, calendar icon
(iOS-only, unchanged) moved from the far-left to sit just left of the
settings gear on the trailing side. The divider is gone — the shared
alignment column does the anchoring work it used to do. Also nudged the
brain icon `-1pt` horizontally next to "Arthur," the same class of fix as
the floating capture button's pencil-icon offset — `brain.head.profile`'s
glyph isn't perfectly balanced within its own bounding box either.

## Custom filter pills, Mac single-row layout (2026-07-24)

- **No more system blue on the filter selector.** The native `.pickerStyle(.segmented)`
  is themed by the system accent color on both platforms with no supported
  way to override just the selected segment's colors, so replaced it with a
  hand-built capsule control. Selected pill: light grey background/charcoal
  text in dark mode, charcoal background/light grey text in light mode — the
  inverse of the mode's own background/text pairing, reusing the existing
  `darkText`/`darkCharcoalBackground` constants rather than new colors
  (`Theme.selectedFilterBackground/Foreground`).
- **Mac-only**: filter now sits on the same row as "Tasks" and the Add
  button, since the wider window has the room — `#if os(macOS)` inserts it
  into `taskSection`'s heading row instead of its own row below `topBar`.
  iOS/iPadOS unchanged (filter stays on its own row).
- Caught and fixed before Brandon saw it: the custom control's "Tomorrow"
  label wrapped to two lines on iPhone width — the native segmented control
  auto-truncated/sized, the custom one didn't yet. Added
  `.lineLimit(1).minimumScaleFactor(0.8)`.

## Font scope narrowed: system font for utility text, Noto Serif only for the three named headings (2026-07-24)

Asked for Claude's opinion on serif-everywhere vs. system-font-for-utility-text
first (no code change); Brandon's answer split the difference rather than
picking one extreme:
- **System font** (not Noto Serif) for: the "Nothing here."/"Nothing in
  today's note yet." empty-state placeholders, the All/Overdue/Today/Tomorrow
  filter labels (already system font from when the custom pill control was
  built — no change needed there), and Settings' form content on all three
  platforms (`.font(Theme.serif(17))` removed from `SettingsView`).
- **Noto Serif kept** for "Arthur", "Tasks", "Daily Note" specifically — the
  three headings that carry the app's identity — and for the daily note's
  *real* content once written (only the empty-state placeholder switched to
  system font; splitting those apart into separate `Text` views was
  necessary since they'd shared one view/font before).
- Add Task/Add Note/Quick Capture's non-heading text was left alone (Brandon
  named "settings" specifically, not those three) — worth asking if he wants
  the same treatment there for consistency.
- **Mac-only, one more weight step down**: even Medium still read "cheap" to
  Brandon on Mac specifically (screen/rendering differences make the same
  weight look heavier there than on iOS) for the three named headings.
  Backed down to Regular via `Theme.headingWeight` (`#if os(macOS)` computed
  property) — iOS/iPadOS keep Medium.

## Mac-only tagline (2026-07-24)

"Habits shape identity." added after the brain icon in the top bar, Mac only
(`#if os(macOS)`), system font at 15pt matching the "Nothing here."
placeholder size, `.secondary` foreground like the other placeholder text.

## Corner-radius unification, ContentBox top-edge bug, dark-style-aware sheets (2026-07-24)

- **PillButton's corner radius unified to 8pt**, matching `ContentBox` —
  asked for Claude's opinion first (full-round for standalone controls like
  the FAB/filter selector is justified; two *different* fixed radii for
  otherwise-similar chrome wasn't). Agreed, implemented.
- **Real bug fixed**: Daily Note's `ContentBox` was missing its top border
  edge specifically — `.background()` draws the stroke *behind* content, and
  the `ScrollView`'s own edge rendering painted over it. Tasks' `List`
  happened to survive the same issue by luck. Switched `.overlay()` instead
  of `.background()` for the stroke — always draws on top regardless of what
  the child content does, fixes it for both and any future ContentBox use.
- **Real bug fixed**: Settings (and by the same root cause, Add Task/Add
  Note/Quick Capture) never applied `Theme.background(...)` at all — they
  just inherited the generic system sheet background, which looks
  charcoal-ish regardless of the actual Navy/Charcoal selection. So picking
  Navy never visibly changed Settings' own background. Added
  `Theme.effectiveScheme(appearance:system:)` (shared helper, avoids
  duplicating the switch in four places) plus
  `.scrollContentBackground(.hidden)` + `.background(Theme.background(...))`
  + `.preferredColorScheme(...)` to all four dialogs. Settings uses its
  *live* (uncommitted) Picker selections for this, not store.config, so
  toggling Navy/Charcoal previews immediately rather than waiting for Done.
- **"Add inbox document" clarified** (Q&A, no code change): always a real
  `Button`, just `.disabled()` until Name + URL + the Craft MCP link (also on
  this screen) are all present — the MCP-link dependency is easy to miss.
- **"Navy" label** — dropped the "(#011528)" hex suffix per request, just
  "Navy" now.

## Mac-only: even lighter/smaller headings, tagline, stale iPad build (2026-07-24)

- **Noto Serif Light downloaded** (confirmed available at the same source as
  the other weights) — "Arthur"/"Tasks"/"Daily Note" on Mac now use Light
  weight (down from Regular) *and* a smaller size (18pt vs. the 24pt
  `headingSize` iOS/iPadOS keep), via new `Theme.brandHeadingSize`
  (Mac-conditional) alongside the existing `Theme.headingWeight`. Rationale:
  only two sections on the page — the headings don't need to visually
  compete for attention. iOS/iPadOS unaffected (Medium weight, full size,
  looked "great" per Brandon as-is).
- **"Habits shape identity."** tagline confirmed working, logged above.
- **Stale iPad build was the real cause of "recent edits missing" on iPad** —
  only the iPhone simulator and Mac had been reinstalled with each round's
  latest build for several rounds running; the iPad Air 11" simulator was
  still running a build from before the Notion-style header redesign, so the
  calendar icon still showed in its old left-side position there. Reinstalled
  the current build — confirmed via screenshot the icon now sits correctly
  next to Settings, matching iPhone. Not a code bug, a verification-process
  gap: worth reinstalling on *every* booted simulator each round going
  forward, not just the one most recently screenshotted.

## Gear icon chrome removed, system font extended to all four dialogs (2026-07-24)

- **Settings gear**: `.buttonStyle(.plain)` added (removes macOS's default
  bordered-button background — a gear glyph alone already reads as
  "Settings," per Brandon, no chrome needed) + bumped to 18pt since it no
  longer has button-background weight of its own. Applied on all platforms,
  not just Mac, per Brandon's request, though iOS's plain-Button-in-HStack
  didn't show the chrome issue to begin with.
- **System font extended from Settings to all four dialogs**, after Brandon
  asked whether leaving Add Task/Add Note/Quick Capture in serif was
  deliberate. It wasn't — that was scope creep from following his literal
  wording ("settings" specifically) rather than the underlying principle.
  Recommended and implemented one consistent rule: system font for all
  dialog chrome and input, Noto Serif reserved for "Arthur"/"Tasks"/"Daily
  Note" and the Daily Note's actual saved content.
  - AddTaskSheet: fully system font now (task text is metadata/a label, not
    app content).
  - AddNoteSheet: buttons switched to system font; the `TextEditor` itself
    **deliberately kept serif** — unlike the other two, this text literally
    becomes the real Daily Note content once saved (which stays serif), so
    composing matches reading it back later.
  - CaptureSheet: fully system font (headings, text editor, search field,
    results, buttons) — this text goes to an arbitrary Craft document Arthur
    never redisplays, so there's no "matches how you'll read it back"
    argument the way Add Note has.

## Quick Capture section labels matched to Add Task's native style (2026-07-24)

"Capture"/"Push to" were custom `Text` at `Theme.headingSize` (24pt, medium)
— dramatically bigger than Add Task's labels, because those are *native Form
section headers* (small, secondary-colored, uppercase), not comparable custom
text. Since Quick Capture intentionally doesn't use `Form` (needed the custom
`ContentBox` border treatment instead), replicated the native section-header
look by hand: `.font(.system(.footnote, weight: .semibold))` +
`.textCase(.uppercase)` + `.foregroundStyle(.secondary)`.

**Corrected same round**: the `.textCase(.uppercase)` was wrong — modern
`.formStyle(.grouped)` section headers render in sentence case (Add Task
shows "Task", not "TASK"), not the old iOS 6-era all-caps style I misremembered.
Removed it; "Capture"/"Push to" were already correctly-cased text, so that
was the only change needed.

**Empirically verified and re-fixed (2026-07-24)**: Brandon suspected the
"Capture"/"Push to" labels still didn't match Add Task's native header in
size or color, and asked whether the actual coded font size could be
checked. Add Task's native Form section header isn't an `NSTextField` — a
full AppKit subview walk found no `NSTextField` anywhere in the hierarchy,
confirming it's drawn via private CoreText/compositing machinery with no
introspectable `.font` property. Measured it empirically instead: a
standalone Swift/AppKit script rendered both the native header and the
custom label into real on-screen `NSWindow`s (off-screen `ImageRenderer`
rendering came back blank for the Form — likely because grouped-Form content
needs real window compositing, not a headless snapshot), captured each via
`NSView.cacheDisplay(in:to:)`, then scanned raw pixel rows for ink to find
glyph height and average ink color.

Result: native header band was 10px tall, avg ink RGB (93,93,93). The old
`.footnote/.secondary` label was 9px, RGB (149,149,149) — Brandon's instinct
was right on both counts. Root cause of the color gap wasn't weight (bold at
the same size barely moved the reading) but style: `.secondary` vs
`.primary`. Landed on `.system(.subheadline, weight: .semibold)` +
`.foregroundStyle(.primary)`, which measured at the same 10px band and RGB
(100,100,100) — matching native within noise. Applied to both "Capture" and
"Push to" in CaptureSheet.swift.

## Removed placeholder prompts; renamed "Push to" → "Destination" (2026-07-24)

Brandon: don't need placeholder prompt text in fields where the field is
self-explanatory. Removed:
- Add Task's "What needs doing?" (Task field)
- Settings' "Craft MCP link" (Craft connection field)

Kept, per explicit exception — these need the reminder:
- Settings' Inbox section: "Name (e.g. Personal)", "Craft document URL",
  "Add inbox document"
- Quick Capture's "Search documents…" (already had no prompt in the
  free-text capture field itself, and the search field's placeholder is a
  functional affordance, not unnecessary "prompt" text)

Also renamed Quick Capture's "Push to" label to "Destination" to match Add
Task's wording for the same concept — same fix location as the label
size/color correction above.

Rebuilt and reinstalled on Mac, iPhone 17 Pro, and iPad Pro 13" (M5)
simulators; verified via screenshot on iPhone that the Task field, Craft MCP
link field, and Quick Capture's Capture/Destination labels all render
correctly.

## App display name + icon for real-device install (2026-07-24)

Moving from simulator-only to installing on Brandon's actual iPhone/iPad/Mac
via Xcode surfaced two things simulator testing never showed:

- Neither target had an explicit `PRODUCT_NAME`, so `CFBundleName` fell back
  to the raw Xcode target name — the app would have installed on the home
  screen literally labeled "Arthur-iOS" / showed as "Arthur-Mac" in the Dock.
  Added `PRODUCT_NAME: Arthur` to both the Arthur-iOS and Arthur-Mac targets
  in project.yml.
- No iOS AppIcon.appiconset existed at all (only Mac had one, from the
  earlier placeholder-icon round) — iOS installs would have used the blank
  default icon. Brandon asked to reuse the Bits app's icon exactly (dark
  rounded square, three fading-blue horizontal bars,
  ~/Projects/bits/public/icon-512.png) rather than design something new.
  Generated the full Mac iconset (10 sizes, replacing the earlier "Art"
  placeholder) and a single 1024×1024 universal iOS icon from that same
  512px source via Lanczos resampling — simple flat geometric shapes hold up
  fine upscaled 2x. Added `App/Resources/Assets.xcassets/AppIcon.appiconset`
  (new catalog + Contents.json) and `ASSETCATALOG_COMPILER_APPICON_NAME:
  AppIcon` on Arthur-iOS. Verified both fixes together via simulator home
  screen: icon renders correctly and the label reads "Arthur".

Also note for future rounds: running `xcodegen generate` regenerates
project.pbxproj from scratch, which resets each target's Signing &
Capabilities "Team" back to blank (DEVELOPMENT_TEAM is intentionally left
"" in project.yml rather than hardcoding Brandon's personal team ID into
version control) — after any project.yml change + regenerate, Team needs
reselecting in Xcode before an on-device Run will succeed again.

## Bug fixes from first real-device test pass (2026-07-24)

Testing on Brandon's actual iPhone (not just simulator) surfaced real bugs
simulator testing had masked or hadn't exercised yet:

- **Daily Note showed raw `<page id="...">...</page>` markup.** Craft's
  `blocks get --format markdown` echoes the page's own empty wrapper tags
  when the day's note has no blocks yet, rather than returning true empty
  content. `CraftClient.dailyNoteMarkdown` now detects that empty-shell shape
  via regex and returns "" instead, so the "Nothing in today's note yet."
  placeholder shows correctly.
- **Task list rows had an ugly solid-black background.** Not a Navy/Charcoal
  bug — `.scrollContentBackground(.hidden)` hides the `List`'s own
  background, but each row still paints its own default background
  underneath, which resolves to near-black in iOS dark mode regardless of
  Arthur's theme. Added `.listRowBackground(Color.clear)` per row in
  AgendaView's task List so the ContentBox's themed background shows through
  instead.
- **Quick Capture's typed content looked smaller than its own field labels.**
  The "Capture"/"Destination" labels use a Dynamic-Type text style
  (`.subheadline`), which scales with the device's text-size setting; the
  actual content fields (TextEditor, search field, results) were hardcoded
  `.system(size: 15/14/13)` — fixed sizes that don't scale. On a device with
  larger-than-default text size, the label grows and the content doesn't,
  producing a visible mismatch that the simulator's default text size never
  exposed. Switched all of CaptureSheet's content text to the matching
  Dynamic-Type styles (`.subheadline` / `.footnote`) so they track together
  at any text-size setting, not just the default one.
- **"Tasks"/"Daily Note" section headings sized down, "Arthur" unchanged.**
  Brandon: with only two sections on the page, the section labels don't need
  to stand out as much as the app's own title, and the earlier round had
  accidentally coupled them to the same `brandHeadingSize` constant. Added a
  separate `Theme.sectionHeadingSize` (20pt iOS/iPadOS, 15pt Mac — smaller
  than brandHeadingSize on both) and pointed "Tasks"/"Daily Note" at it,
  leaving "Arthur" on `brandHeadingSize` untouched. "Add Task"/"Add to Daily
  Note"/"Quick Capture" are unaffected — those are native/large sheet
  titles, not this constant.

## Second real-device pass: label color bug, field-style consistency, deeper Daily Note fix (2026-07-24)

- **CaptureSheet's "Capture"/"Destination" labels rendered navy-blue and bold
  instead of neutral grey like Add Task's native header**, even after the
  earlier size/weight fix. Root cause: `.foregroundStyle(.primary)` on the
  label is SwiftUI's *hierarchical* `.primary` token, not an absolute
  color — it tints relative to whatever ancestor `.foregroundStyle` is
  already active. CaptureSheet's outer VStack sets
  `.foregroundStyle(Theme.primary(effectiveScheme))` (Brandon's navy), so the
  descendant's `.primary` inherited and bolded that navy rather than
  resolving to the native neutral grey Add Task uses (whose Form has no such
  ancestor override). Fixed by forcing the literal `Color.primary` type
  instead of the hierarchical `ShapeStyle.primary` token — disambiguates
  which "primary" Swift picks.
- **Daily Note's earlier "empty shell" fix was incomplete.** Turns out Craft
  wraps *every* `blocks get --format markdown` response in
  `<page>/<pageTitle>/<content>` tags, not only empty ones — verified live
  with actual note content present (`<content>Adding a quick test note.
  </content>` came back inside the same wrapper). The prior fix only
  special-cased the fully-empty shell (no `<content>` tag at all); real
  content fell straight through and displayed with all its surrounding
  markup intact. Replaced `stripEmptyPageShell` with
  `extractDailyNoteContent`, which pulls the actual `<content>...</content>`
  text (de-indenting it) and treats "no `<content>` tag at all" as truly
  empty.
- **Quick Capture's fields looked like a different design language than Add
  Task's.** Add Task's native Form field is a solid filled pill; Quick
  Capture's `ContentBox` is hairline-stroke-only with no fill — intentional
  for ContentBox's actual job (Tasks/Daily Note read-only display), wrong
  for an editable input. Added `FieldBox` (App/Sources/App/FieldBox.swift) —
  filled rounded container using a new `Theme.fieldBackground(_:)`
  (`UIColor.secondarySystemGroupedBackground` / `NSColor.
  controlBackgroundColor`) — and switched CaptureSheet's two input
  containers to it, leaving ContentBox itself untouched for its original
  read-only use on the home screen. Unified internal padding to 12pt across
  the Capture text editor and the destination search/selected-doc rows
  (previously 8/10 — inconsistent, per Brandon's ask).
- **Settings: inbox documents now support drag-to-reorder.** Added
  `.onMove` alongside the existing `.onDelete` on the inbox ForEach, plus an
  `EditButton()` in the iOS toolbar (macOS Lists reorder directly without
  needing Edit mode).

## Task fetch: query "all" scope instead of active+upcoming+inbox (2026-07-24)

Confirmed the "only one task shows in All" bug: Craft's `tasks list --scope`
actually supports `active|upcoming|inbox|logbook|document|all` (documented
higher up in this file, in "Task filtering (v1 scope decision)" — Arthur
just wasn't using `all`). The three scopes `refresh()` merged
(active/upcoming/inbox) only return a task if it has a schedule/deadline
date (active/upcoming) or lives in Craft's bare inbox specifically — any
task sitting in a regular document with no date fell through all three
gaps. Brandon has two dozen+ tasks exactly in that shape. Replaced the
three-way merge with a single `client.listTasks(scope: "all")` call.
Client-side bucketing (Overdue/Today/Tomorrow) and the done-task filter in
`filteredTasks` are unaffected — same per-task parsing, just a more complete
source list.

## Trash-related state bug + iPad/iPhone icon spacing (2026-07-24)

- **Mac: toggling/editing a task whose document is in Craft's trash showed a
  false "success" state.** Brandon hit "Cannot modify task: Cannot modify
  document in trash. Restore it first." from Craft's own write API — a real,
  expected failure since `tasks list --scope all` (added this session)
  doesn't exclude tasks living in trashed documents. But `toggleDone` and
  `updateText` both applied their change to local state optimistically
  *before* awaiting the API call, and neither reverted it on failure — so a
  failed toggle left the checkbox looking checked (or edited text looking
  saved) even though nothing persisted. Fixed both to revert the optimistic
  local change back to its prior value when the API call throws, so the UI
  never shows a state Craft doesn't actually have. The underlying "this
  task's doc is trashed" case still surfaces via the existing error alert —
  Craft's own message is already clear, no need to embellish it further.
- **iPhone/iPad: calendar and gear icons sat too close together, causing
  mis-taps.** Both used the topBar's default 8pt HStack spacing (meant for
  the tight "Arthur [brain icon]" pairing, not this pair) with no explicit
  tap-target frame — just the bare glyph's own small bounding box. Moved
  calendar+gear into their own nested HStack at 20pt spacing, and gave each
  an explicit 44×44 frame with `.contentShape(Rectangle())` (Apple's minimum
  recommended touch target) so the tappable area is meaningfully larger than
  the visible glyph. Also added a `topBarIconSize` computed property that
  reads `horizontalSizeClass` — 22pt on iPad's regular width, 18pt on
  iPhone's compact width — per Brandon's request that iPad's larger screen
  get slightly bigger icons, not just the same size with more surrounding
  space.

## Replaced Tasks/Daily Note divider with a three-tab home screen (2026-07-25)

Brandon: the draggable divider was "clever... not as useful," and the
floating Quick Capture button just "takes up real estate hovering in the
bottom right corner." Replaced both with a minimalist tab bar (text +
icon, bold + underline for the selected tab — matching a reference
screenshot Brandon liked) with three tabs: Tasks, Daily Note, Quick
Capture. Each now gets the full remaining screen height instead of sharing
a fixed split.

- Removed `DividerHandle.swift`, `GeometryReader`-based height math, and
  `dragFraction`/`Config.dividerFraction`/`TaskStore.setDividerFraction`
  entirely — all dead once there's no divider to persist a position for.
- Top bar (Arthur + brain icon + calendar/gear) is unchanged, per Brandon's
  explicit instruction to keep it as-is.
- New `HomeTab` enum owns the icon-swap Brandon asked for: Tasks keeps
  `pencil.and.outline`; Daily Note moves to `calendar.badge.plus`; Quick
  Capture picks up Daily Note's old `pencil.and.scribble`.
- "Tasks"/"Daily Note" no longer show their own heading text+icon in their
  content area — that's what the tab bar shows now, so repeating it there
  would be redundant. Each screen keeps its filter row/Add button (Tasks)
  or Add button (Daily Note).
- `CaptureSheet` converted from a modal (`NavigationStack` + toolbar
  Cancel/Push + `.sheet`) into a plain embeddable view: dropped the modal
  chrome, added an inline "Push" `PillButton` (matches Add Task/Add Note's
  style), and on success it resets its fields instead of dismissing —
  it's a persistent tab now, not a one-shot dialog.
- All three tabs' content stays mounted simultaneously in a `ZStack`
  (opacity + `allowsHitTesting` toggling on `selectedTab`, not a
  conditional/switch that destroys and recreates views) — so a
  partially-typed Quick Capture note or an in-progress task edit survives
  switching to another tab and back, matching how a native `TabView` keeps
  backgrounded tabs alive.
- **Bug caught in the simulator before shipping it**: "Quick Capture" at
  `Theme.sectionHeadingSize` doesn't fit three-across on iPhone width — it
  wrapped into four broken lines. Fixed by wrapping the tab row in a
  horizontal `ScrollView` with `.fixedSize()` on each label, so it scrolls
  instead of wrapping when it doesn't fit, without shrinking the font size
  Brandon asked to keep matching the old section headings. Confirmed all
  three tabs also fit on one line with no scrolling needed on iPad's wider
  screen.

Verified in the iPhone and iPad simulators per Brandon's request to start
there before rebuilding on real devices — all three tabs switch correctly,
icons match the requested swap, filter/Add row and Daily Note's Add button
work as before, and Quick Capture's embedded Push flow renders correctly
(disabled until a destination is selected, same as before).

## Tab bar sizing + unified input font across all compose fields (2026-07-25)

Quick follow-up round after seeing the new tab bar and Quick Capture tab
live on iPhone:

- **Tab labels didn't fit on iPhone without scrolling.** The initial fix
  (horizontal ScrollView fallback) technically worked but Brandon wanted
  all three visible with no scrolling at all, not a scrollable overflow.
  Added `tabFontSize`/`tabIconSize` (12pt text / 14pt icon on iPhone's
  compact width, unchanged at Theme.sectionHeadingSize/sectionIconSize on
  iPad and Mac — both confirmed fine already), tightened inter-tab spacing
  20→14 and icon-to-text gap 8→5, and removed the ScrollView entirely now
  that a plain HStack fits. Verified via screenshot: "Quick Capture" now
  renders in full on one line, no truncation, no scrolling.
- **Doubled the whitespace below the Arthur/calendar/settings row**, per
  Brandon's request — tabBar's top padding went from 8pt to 28pt (topBar's
  own 12pt bottom padding + this 28pt = 40pt total, double the original
  20pt gap).
- **Unified compose-field font across Add Task, Add Note, and Quick
  Capture.** Brandon: Quick Capture's typed text was too small and
  inconsistent with Add Task/Add Note, "let's use the system font to begin
  with, then test an initial font size that's good for readability, but
  adapts to screen size." Added `Theme.inputFontSize(horizontalSizeClass:)`
  — 14pt Mac, 16pt iPhone, 18pt iPad — and applied it to all three fields:
  Add Task's Task `TextField`, Add Note's `TextEditor` (switched off Noto
  Serif — a deliberate reversal of the earlier "matches how you'll read it
  back" reasoning, per this explicit new instruction), and Quick Capture's
  `TextEditor` (previously `.subheadline`, visibly smaller than the other
  two). Verified visually in the simulator: typed the same test string into
  both Add Task's Task field and Quick Capture's Capture field side by side
  — same size now.

## Folder-tab polish: outline, aligned tops, left-aligned, Mac font sizes (2026-07-25)

Four fixes after Brandon reviewed the new folder tabs live:

- **Selected tab had no visible shape.** Its background deliberately matches
  the content behind it (that's the "merges with content" mechanism), but
  on a dark background that meant no outline at all — it just looked like
  the tab vanished rather than "selected." Added a hairline stroke (same
  0.15-opacity treatment as ContentBox elsewhere) on the selected tab's
  top/left/right — no bottom edge, since the missing bottom is exactly what
  makes it read as merged with the content below.
- **Tab tops weren't aligned with each other.** Root cause: tabs were only
  vertically padded, not given a fixed height, so the selected tab's
  semibold text rendered a hair taller than its regular-weight siblings —
  and since the row is bottom-aligned (to line up with the shared
  baseline), that height difference showed up as misaligned tops. Fixed by
  giving every tab a shared fixed `tabRowHeight` instead of relying on
  padding alone.
- **Tabs were centered, not left-aligned.** The `tabBar` view was sized to
  fit its own content (no `Spacer`), and the outer `VStack`'s default
  `.center` alignment centered that content within the full-width column —
  visually jarring since tab labels have different lengits, per Brandon's
  point. Added `.frame(maxWidth: .infinity, alignment: .leading)` to
  `tabBar` (and made the baseline `Rectangle` explicitly `.frame(maxWidth:
  .infinity)` rather than relying on implicit shape-expansion sizing) so
  the whole row pins to the left edge, matching "Arthur" and the content
  below.
- **Mac field labels and filter labels too small.** `FieldLabel` used the
  `.subheadline` Dynamic Type token (resolves quite small on macOS
  specifically) and the Task filter pills were a fixed 13pt on every
  platform. Bumped both to an explicit 15pt/14pt on Mac only — iOS/iPadOS
  weren't flagged, so they keep their original sizing.

## Tab row height bumped again — text nearly clipped (2026-07-25)

The `tabRowHeight` fix a round ago (26/30/24 on iPhone/iPad/Mac) fixed the
top-alignment issue but was too tight — Brandon: "the text almost gets cut
off." Bumped to 34/38/30. Verified via zoomed screenshot: clear breathing
room below the text now, tops still aligned, still fits without scrolling
on iPhone.

## Mac tab breathing room bumped again + iPad re-verified (2026-07-25)

Brandon: Mac still felt tight even after the previous bump (30→40 this
round), and iPad hadn't actually been re-checked since before the
folder-tab redesign (all verification up to this point was iPhone +
Mac only). Bumped Mac's `tabRowHeight` to 40 and confirmed iPad live in
the simulator for the first time with the new tabs — outline, aligned
tops, left-alignment, and spacing all correct there too (38pt height,
unchanged from the prior round, already reads fine on iPad's wider
screen).

## iPad breathing room + selected-tab outline was too thin to see (2026-07-25)

- iPad still felt tight even at 38pt (iPhone's regular-width value) —
  bumped iPad specifically to 44pt, unchanged for iPhone (34) and Mac (40,
  from the round before).
- Brandon asked directly whether the selected-tab outline was actually
  missing on iPad or just hard to see. Checked by sampling pixel colors
  along the "Tasks" tab's top edge — the stroke was measurably there
  (colors matched the expected opacity-0.15 blend over the background) but
  at `lineWidth: 0.5` it was sub-pixel-thin on retina and barely
  registered visually, explaining why it read as "missing." Bumped to
  `lineWidth: 1` and opacity 0.15→0.35. Re-verified via zoomed screenshot:
  now clearly visible — light-grey border on top/left/right of the
  selected tab, no bottom edge, unselected tabs still show no border.

## "Nothing here yet." placeholder added to Quick Capture + Add Note compose fields (2026-07-25)

Brandon wanted the same system-font, secondary-color empty-state style
already used elsewhere (Tasks list, Daily Note display) applied to Quick
Capture's Capture field and Add Note's compose field — neither had any
placeholder at all, since `TextEditor` doesn't support one natively.
Added a `ZStack`-overlaid `Text("Nothing here yet.")` (hidden once typing
starts, `.allowsHitTesting(false)` so it never blocks tapping into the
field) to both, matching font size/color/positioning. Verified in the
iPhone simulator: shows correctly in Quick Capture's Capture field, styled
consistently with the rest of the app.

## Correction: empty-state text wasn't actually consistent (2026-07-25)

Called the previous round done too early — Brandon caught that Tasks
("Nothing here."), Daily Note ("Nothing in today's note yet."), and the
newly-added Quick Capture/Add Note text ("Nothing here yet.") were three
different strings, not the shared wording the request asked for. Changed
all four to the literal same string, "Nothing here yet." Verified each
individually in the simulator this time (Tasks, Daily Note, and Quick
Capture screenshotted directly) rather than assuming consistency from only
checking one.

## ContentBox border was the same too-faint stroke bug as the tab outline (2026-07-25)

Brandon spotted the Mac Daily Note/Quick Capture screenshots looked
inconsistent — Quick Capture's `FieldBox` reads as clearly boxed (filled
background), while Daily Note's `ContentBox` looked nearly borderless next
to it. Root cause: `ContentBox` still had the exact same `0.15 opacity /
0.5pt` stroke that we'd already found and fixed for the selected tab's
outline a few rounds ago (too thin to register on retina displays). Bumped
to the same values that fixed it there (`0.35 opacity / 1pt`). Verified in
the iPhone simulator: Daily Note's box now shows a full, clearly visible
outline on all four sides, matching FieldBox's visibility. Since ContentBox
is shared by both the Tasks list and Daily Note across all three platforms,
this one fix covers both the Mac and iPhone instances Brandon flagged.

## FieldBox never actually had a border — added one (2026-07-25)

Brandon caught that the previous round's fix didn't touch Quick Capture at
all — correct, because `FieldBox` was never using a stroke in the first
place; what read as a "border" before was purely the fill color
(`Theme.fieldBackground`) contrasting against the page background. Added
an actual stroke overlay to `FieldBox` (same `0.35 opacity / 1pt` as
ContentBox), plus the three places in `SettingsView` that bypass FieldBox
with their own raw `RoundedRectangle` fill (the inbox documents List
background, "Add inbox document" button, "Force Sync" button) — all three
had the identical no-stroke gap. Verified via screenshot: Quick Capture's
Capture and Destination boxes now show a clear border on all sides,
matching ContentBox and the tab outline.

## Box alignment, no-bold tabs, placeholder padding, and a genuine color bug (2026-07-25)

Four items from one review pass:

- **Content box top-edge alignment (Tasks/Daily Note/Quick Capture).** Added
  a shared `Theme.headerRowHeight` (44pt) and applied `.frame(height:)`
  (replacing asymmetric top/bottom padding) to all three tabs' header rows,
  plus a same-height invisible `Color.clear` spacer in place of Quick
  Capture's removed "Capture" label. Also removed Quick Capture's outer
  `ScrollView` (unnecessary — its results list already scrolls internally)
  and added `.frame(maxHeight: .infinity, alignment: .top)` to match
  `taskSection`'s pattern. **Correction while verifying:** an initial pixel
  measurement suggested an 89px misalignment persisted after these fixes.
  Root-caused via a controlled diagnostic (temporarily coloring both the
  Tasks header row and Quick Capture's spacer solid red to compare
  side-by-side) — the "misalignment" was a measurement artifact: my sample
  column happened to pass through the Tasks tab's "All" filter pill (which
  only exists on that tab), not the actual content box. All three were
  correctly aligned already at the point the header-row-height fix landed;
  confirmed via the same diagnostic that both tabs' boxes start at the
  identical y once measured through a column that isn't accidentally
  crossing tab-specific chrome.
- **Selected tab no longer bold.** Brandon: the background fill/outline
  already signals which tab is active; bolding on top of that was
  redundant. All tabs now render at the same `Theme.headingWeight`
  regardless of selection.
- **Placeholder padding unified.** Quick Capture/Add Note's "Nothing here
  yet." placeholder used `.padding(.horizontal, 17).padding(.top, 20)`,
  inconsistent with Tasks/Daily Note's uniform `.padding(12)` on their real
  content text. Changed to match exactly.
- **Real bug: placeholder text color differed by tab.** Brandon caught
  "Nothing here yet." rendering a visibly different gray on Quick Capture
  than Tasks/Daily Note. Root cause: identical to the earlier tab-label
  color bug — `.foregroundStyle(.secondary)` is SwiftUI's *hierarchical*
  `.secondary` token, which tints relative to the nearest ancestor
  `.foregroundStyle`, not an absolute color. Quick Capture/Add Note apply
  `.foregroundStyle(Theme.primary(...))` at their outer container level
  (wrapping the placeholder), while Tasks/Daily Note apply that override
  only to their header row (a sibling, not an ancestor, of the placeholder)
  — so the same `.secondary` token resolved to two visibly different
  colors. Added `Theme.secondaryText(_:)` (concrete
  `UIColor.secondaryLabel`/`NSColor.secondaryLabelColor`, immune to
  ancestor tinting) and applied it to all four placeholders. Verified by
  sampling the actual rendered pixel color in both the Tasks and Quick
  Capture screenshots: both now read exactly `(152,152,159)`.

iPad reinstalled with all of the above (hadn't been updated since the
button-height round).

Not changed, pending confirmation from Brandon:
- **HTTP 502 immediately after saving the Craft MCP link** — every request
  since has succeeded (tasks loaded, Quick Capture pushed fine), so this
  looks like a one-off transient failure right as Force Sync fired on
  Settings' Done, not a client bug. Revisit only if it recurs.
- **Only one task appeared in "All"** — Arthur's `refresh()` only queries
  three `tasks list` scopes (active/upcoming/inbox); per earlier SCOPE.md
  notes, most of Brandon's real Craft tasks have no schedule/deadline dates
  and may live inside specific project documents outside all three scopes.
  Likely "working as coded, not matching real usage" rather than a parsing
  bug — CraftTask.parseList handles multiple tasks fine. Waiting on Brandon
  to confirm whether the one task that did show up was schedule-dated or
  sitting in the bare inbox before deciding whether "All" needs to mean
  something broader.

## Left-align typed text in Form text fields (2026-07-24)

Brandon noticed macOS Form rows right-align typed text (e.g. "sdfljksfk" in
the Craft MCP link field, "dgsdfgdfg" in Task) — this is native
`TextField(title:text:)`-in-`Form` behavior on macOS (same convention as the
trailing-aligned Picker value), but he wanted left alignment as a consistent
rule across all input fields. Added `.multilineTextAlignment(.leading)` to:
Add Task's Task field; Settings' Craft MCP link, inbox Name, and inbox
Craft document URL fields. Verified on iOS by typing "Test alignment" into
the Task field and confirming it renders left-aligned; same SwiftUI code
path applies identically on Mac.

## Fourth tab: Baserow quick capture, iPhone dropdown selector (2026-08-05)

Brandon wanted a 4th home-screen tab that works like the standalone
baserow-quick-push Chrome extension: pick a database, pick a table, and a
form builds itself from that table's live field schema. Ported straight
from that extension's design:

- **ArthurKit**: `BaserowClient` (token-auth REST client — `listTables`
  filters `/api/database/tables/all-tables/` client-side since the
  per-database endpoint and the databases-list endpoint are both JWT-only,
  same limitation the extension's background.js already documented) and
  `BaserowModels` (`BaserowDatabase`/`BaserowTable`/`BaserowField`, plus the
  same readOnly/unsupported type-exclusion lists as the extension's
  config.js).
- **Config**: added `baserowToken`, `baserowDatabases` (hand-entered
  id+name pairs — token auth can't list a workspace's databases, so this is
  configured once in Settings, same as the extension's own options page),
  and `lastBaserowDatabaseId`/`lastBaserowTableId` (remembered only after a
  successful push, not on every selection change). Gave `Config` a custom
  `init(from:)` using `decodeIfPresent` for every field — otherwise the
  synthesized `Decodable` would fail on Brandon's existing config.json
  (which predates these keys) and `load()` would silently fall back to a
  blank `Config`, wiping his craftLink/inboxes/etc. Confirmed this matters:
  his real Mac config.json didn't have the new keys and loaded correctly
  after the change.
- **BaserowCaptureView**: database/table `Picker`s + dynamically rendered
  fields (text/url/email/phone as plain `TextField`, `long_text` as
  `TextEditor` with the same cursor-alignment fix as Quick Capture/Add Note,
  `boolean` as `Toggle`, `number`/`rating` as numeric `TextField`, `date` as
  a toggle-gated `DatePicker` matching Add Task's due-date pattern,
  `single_select`/`multiple_select` as `Picker`/`Toggle` rows) — same
  FieldBox/FieldLabel styling as every other input surface. Skipped fields
  (formula, lookup, file, link_to_table, etc.) are listed, not silently
  dropped, matching the extension's "Skipped (unsupported/read-only)" note.
- **Settings**: new "Baserow connection" (token) and "Baserow databases"
  (name + numeric ID list, add/delete) sections, styled identically to the
  existing Inbox documents list. Caught and fixed a formatting bug here
  during testing: `Text("\(db.id)")` applies locale number grouping to an
  interpolated Int (showed "487,176" instead of "487176") — fixed with
  `Text(String(db.id))`.
- **iPhone can't fit 4 folder tabs** on compact width (tried it — even at
  the smallest readable sizes it truncated or wrapped). iPad/Mac keep the
  folder tabs; iPhone gets a new `Menu`-based dropdown (`tabDropdown`)
  showing only the active tab, styled with the same 0.15-opacity hairline
  outline as everything else rather than looking like a bare system
  control. `AgendaView.tabSelector` picks between them by
  `horizontalSizeClass`.

Verified end-to-end on iPhone simulator (fresh install, no config): dropdown
opens and shows all 4 tabs with correct icons, selecting Baserow shows the
"No databases configured" empty state, adding a database in Settings
("Captures", ID 487176) correctly populates the Database picker on the
Baserow tab, and selecting it correctly triggers `loadTables` and surfaces
"No Baserow API token set" — the real, expected error with no token
configured. Verified on iPad simulator that all 4 folder tabs render
without truncation/wrapping. Verified on Mac that the folder tab bar
renders all 4 tabs correctly with Brandon's real Craft data still loading
on the other three tabs (confirming the Config migration didn't disturb his
existing settings).

## Splash screen replaced with Seneca quotes (2026-08-05)

Brandon's building a commonplace book — a new Baserow database named
"Seneca" — and wanted a way to periodically resurface words/ideas/
principles he's saved there, the same way Cannon and Winston resurface
starred highlights. Landed on reusing the splash screen's real estate
rather than adding a 5th tab or any notification/background-agent
infrastructure: cold launch shows one Seneca quote instead of the old
fixed "Be Grateful."-style phrase cycle — those statements aren't gone,
Brandon's making them entries in Seneca itself, in rotation with
everything else there. The brain-icon tap (already wired to replay the
splash) doubles as "shuffle to the next quote" for free, with no new code
needed for that part.

- **ArthurKit**: `BaserowClient` gained `listRows`/`updateRowField` (rows
  have no fixed schema, so these hand back/accept raw `[String: Any]`
  rather than a Codable type). New `SenecaStore` actor manages a small
  local cache (`senecaCache.json`, alongside config.json) of ~10 quotes +
  a rotation pointer — `currentQuote()` is an instant local read (no
  network wait on cold launch, per Brandon's explicit ask), `advance()`
  moves the pointer for next time, `refillIfNeeded` tops the buffer back
  up in the background once it drops below 3 remaining (candidate pool of
  30, shuffled, biased toward whatever hasn't been shown recently via an
  optional "Last shown" date field), `markShown` PATCHes that field on the
  row just displayed. All silent-on-failure by design — no token, no
  table configured, network error, wrong field names — the splash just
  keeps showing whatever's cached rather than ever erroring on what's
  meant to be a quiet, ambient screen. An actor specifically because the
  splash's own task and a detached background refill both touch the same
  cache file concurrently.
- **Config**: `senecaDatabaseId`/`senecaTableId` (which table), plus
  user-configurable `senecaQuoteField`/`senecaAuthorField` (default
  "Quote"/"Author") since Brandon controls his own Seneca schema. The
  "Last shown" field name is NOT configurable — Arthur writes it, Brandon
  never reads it, so there's nothing for a setting to let him rename.
  Extended the existing custom `init(from:)` migration pattern.
- **SplashView**: single quote + italic attribution line (only shown if
  the author field isn't empty), sized down from the old titleSize(30) to
  24pt to accommodate full sentences instead of two-word phrases, capped
  at 480pt width so longer quotes wrap instead of spanning edge-to-edge.
  Fallback text ("Be Grateful.", id -1) only for before Seneca's ever been
  configured/synced.
- **Settings**: new "Seneca (commonplace book)" section — same
  Database→Table cascade as the Baserow tab itself, plus the two
  field-name text fields and a caption explaining the optional "Last
  shown" Date field Brandon can add to Seneca for staleness-biased
  rotation to kick in. Caught and fixed a real bug while wiring this up:
  the onChange handler that reloads the table list on database-selection
  was also nil-ing out the restored `senecaTableId` on initial appear,
  racing against `loadFromStore`'s own restore of that same value —
  fixed by having `loadSenecaTables` only clear the selection if it
  genuinely doesn't belong to the freshly-fetched table list, rather than
  unconditionally clearing on every database change.

Verified: all three targets (Arthur-Mac, Arthur-iOS, ArthurBar) build
clean. Fresh iPhone simulator install (no Seneca configured) correctly
shows the "Be Grateful." fallback on cold launch, styled consistently
with the old splash. Settings' new Seneca section renders with the same
FieldBox/FieldLabel/Picker pattern as the Baserow section directly above
it, and the Database/Table cascade + field-name inputs are wired
identically to that already-verified section. Not yet verified against a
real, populated Seneca table (Brandon hasn't configured a token/database
yet) — the "Last shown"-field-missing degrade path and the actual
staleness-biased rotation will only be provable once he does.
