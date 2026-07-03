# Change Log

## 2026-07-03 (later) — v1.02

- New **Space Analyzer** (disk storage map): a GrandPerspective-style treemap of everything under a chosen folder, opened from the sidebar, a toolbar button, a distinct coloured tab, or a folder's right-click menu. Only one analyzer tab exists at a time.
- Scanning runs fully in the background (UI stays responsive), shows live progress, has an always-visible Cancel Scan button, and keeps running when you switch tabs.
- Tiles are coloured by file category via an editable `file-categories.json` (Videos, Music, Images, Apps, Archives, Documents). Right-click a tile for Open, Browse Location, or Copy Path.
- Scans ignore symlinks and Finder aliases so only physical items are measured.
- Status bar now shows volume Used / Free (with free-space %) instead of the current folder path.
- Context menu items now display their keyboard shortcuts.
- Favorites and Network sidebar sections can be collapsed/expanded (remembered between runs).
- Long-press a file row to rename it; hover tooltips follow the cursor and dismiss on right-click.

## 2026-07-03

- Conflict resolution now works per-file: each clash shows the filename and prompts Overwrite, Overwrite All, Skip, Skip All, or Cancel. "All" variants apply to the rest of the queue without further prompts.
- Conflict resolution also applies to move operations (drag-drop onto a folder, cut-paste), not just copies.
- Duplicate Tab added (⌘⇧D).
- ⌘F focuses the filter field directly from the keyboard.
- About surface gains a README button that opens the project README in a popup, rendered with the same markdown viewer as the changelog.
- Keyboard shortcuts table in README reorganised into sections and brought up to date.
- README "Current implementation status" section replaced with a user-facing Features section.

## 2026-07-02 (later)

- Drag & drop to copy files from Finder or another tab into the current folder.
- Drag a file onto a tab to spring-load switch to it, then drop to copy in.
- Reorder folder tabs by dragging; right-click a tab for Sort by Name / Close Duplicate Tabs.
- Configurable file columns (Kind, Size, Date Modified/Created/Taken, Owner), remembered between runs; Name is always shown.
- Sidebar rows gain a modern glass hover effect; drag folders in to pin and reorder favorites.

## 2026-07-02

- Added keyboard shortcuts: Quick View (Space), Select All (⌘A), Rename (⌘⇧R); Reveal in Finder moved to ⌃⌘R.
- Fixed menu keyboard shortcuts that stayed disabled because the commands did not observe the active tab's model.
- Modernized the look and feel with Liquid Glass across the toolbar, filter field, and path bar.
- Added Settings and About surfaces to the sidebar, shown on the main canvas.
- About includes a "View Changelog" button that opens this changelog in a popup.
- Resolved all Swift 6 concurrency build warnings.

## 2026-07-01

- Changelog started
