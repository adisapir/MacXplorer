# MacXplorer

MacXplorer is a native macOS file manager aimed at Windows Explorer-style navigation with a modern Mac feel.

Current implementation status:

- SwiftPM macOS app target.
- Sidebar for standard locations and mounted volumes.
- Path/address bar with Back, Forward, Up, Reload, and Copy Path.
- Main file table with name, kind, size, and modified date.
- Current-folder filtering that does not rely on Spotlight.
- Basic actions: New Folder, Rename, Move to Trash, Open, Reveal in Finder, Open in Terminal.
- Hidden-file toggle.

## Build

```bash
swift build
```

## Run

```bash
swift run MacXplorer
```

The first implementation targets macOS 15 and newer.
