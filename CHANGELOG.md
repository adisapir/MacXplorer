# Change Log

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
