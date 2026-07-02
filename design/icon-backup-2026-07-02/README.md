# App Icon Backup — 2026-07-02

Backup of the **original** MaXplorer app icon, taken before the yellow+blue
Windows-Explorer × Finder rebrand.

| File | What it is |
|------|-----------|
| `AppIconFactory.swift.bak` | Original programmatic icon source (blue Finder-style folder) |
| `AppIcon-current-512.png` | 512px render of the original icon for visual reference |
| `AppIcon.appiconset.Contents.json.bak` | Original asset-catalog manifest (had no PNGs — icon was runtime-only) |

## How to restore

1. Copy `AppIconFactory.swift.bak` back over `MaXplorer/AppIconFactory.swift`.
2. Copy `AppIcon.appiconset.Contents.json.bak` back over
   `MaXplorer/Assets.xcassets/AppIcon.appiconset/Contents.json`.
3. Delete the generated `icon_*.png` files from
   `MaXplorer/Assets.xcassets/AppIcon.appiconset/`.
