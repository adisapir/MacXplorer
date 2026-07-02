# MaXplorer

MaXplorer is a native macOS file manager aimed at Windows Explorer-style navigation with a modern Mac feel.

Current implementation status:

- SwiftPM macOS app target.
- Sidebar for standard locations, removable favorites, mounted volumes, and network locations.
- Network section for browsing `/Network`, mounted network volumes, and Connect to Server.
- Tabbed browsing with a configurable tab limit.
- Path/address bar with Back, Forward, Up, Reload, manual path entry, and Copy Path.
- Main file table with name, kind, size, modified date, sorting, filtering, and multi-selection.
- Current-folder filtering that does not rely on Spotlight.
- File actions: New Folder, Rename, Move to Trash, Open, Quick View, Open With, Reveal in Finder, Open in Terminal.
- Copy, cut, paste, conflict prompts, and a visible copy queue with progress.
- Alias-folder navigation inside the app.
- Settings for appearance, tab limits, Go to Folder history, and concurrent copy limits.
- Hidden-file toggle.

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘T` | New Tab |
| `⌘O` | Open selected item |
| `⌘⇧N` | New Folder |
| `Space` | Rename selected item |
| `⌘⌫` | Move selected items to Trash |
| `⌘⇧R` | Reveal selected item in Finder |
| `⌘C` | Copy selected items |
| `⌘X` | Cut selected items for move on paste |
| `⌘V` | Paste copied or cut items |
| `⌘⌥C` | Copy selected path, or current folder path if nothing is selected |
| `⌘R` | Reload current folder |
| `⌘⇧.` | Toggle hidden files |
| `⌃⇥` | Select next tab |
| `⌃⇧⇥` | Select previous tab |
| `⌘[` | Back |
| `⌘]` | Forward |
| `⌘↑` | Enclosing folder |
| `⌘⇧G` | Go to Folder |
| `⌘⇧H` | Home |
| `⌘K` | Connect to Server |
| `⌘⇧T` | Open Terminal at selected item/current folder |

## Build

```bash
swift build
```

## Run

```bash
swift run MaXplorer
```

## Platform support

MaXplorer targets macOS 15 and newer. macOS 26-specific features should be added behind availability checks so the app can adopt newer system polish without dropping macOS 15 support.

Current macOS 26 enhancements:

- The path bar uses the system glass effect on macOS 26 and newer.
