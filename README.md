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

## Platform support

MacXplorer targets macOS 15 and newer. macOS 26-specific features should be added behind availability checks so the app can adopt newer system polish without dropping macOS 15 support.

Current macOS 26 enhancements:

- The path bar uses the system glass effect on macOS 26 and newer.
