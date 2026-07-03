# MaXplorer

MaXplorer is a native macOS file manager aimed at Windows Explorer-style navigation with a modern Mac feel.

## Features

- **True tabbed browsing** — open multiple folders in tabs, reorder them by dragging, duplicate tabs, and cap how many can be open at once. Finder's tabs pale in comparison.
- **Cut & paste for moves** — use `⌘X` / `⌘V` to move files the way Windows users expect, instead of hunting for Option+drag.
- **Visible copy queue with per-file progress** — watch every active transfer in a dedicated queue panel, with speed and estimated time remaining. No more wondering whether Finder finished copying.
- **Granular conflict resolution** — when pasting or dropping files that already exist, choose Overwrite, Overwrite All, Skip, Skip All, or Cancel — one conflict at a time, with no surprises.
- **Instant folder filtering** — `⌘F` focuses a live filter field that narrows the current folder in real time, no Spotlight index required.
- **Configurable columns** — show or hide Kind, Size, Date Modified, Date Created, Date Taken, and Owner per-session. Columns are persisted across launches.
- **Network browsing built in** — browse `/Network`, mounted SMB/AFP volumes, and Connect to Server without leaving the app.
- **Customisable sidebar** — pin any folder as a favourite, remove built-in locations you never use, and reorder pins by dragging.
- **Drag & drop everywhere** — drop files onto a folder row or a tab to copy or move them; spring-loaded tab switching activates the target tab automatically.
- **Liquid Glass design** — toolbar, filter field, path bar, and settings surfaces all use macOS 26 Liquid Glass, so MaXplorer looks at home alongside the rest of the system.
- **Terminal & Finder integration** — jump straight to a Terminal session or reveal any item in Finder from the context menu or keyboard shortcut.

## Keyboard Shortcuts

### File & Folder Actions
| Shortcut | Action |
| --- | --- |
| `⌘O` | Open selected item |
| `Space` | Quick View selected item |
| `⌘⇧N` | New Folder |
| `⌘⇧R` | Rename selected item |
| `⌘⌫` | Move selected items to Trash |
| `⌃⌘R` | Reveal selected item in Finder |
| `⌘⇧T` | Open Terminal at selected item/current folder |

### Edit & Clipboard
| Shortcut | Action |
| --- | --- |
| `⌘C` | Copy selected items |
| `⌘X` | Cut selected items for move on paste |
| `⌘V` | Paste copied or cut items |
| `⌘A` | Select all items in the current folder |
| `⌘⌥C` | Copy selected path, or current folder path if nothing is selected |

### View
| Shortcut | Action |
| --- | --- |
| `⌘F` | Focus the filter field |
| `⌘R` | Reload current folder |
| `⌘⇧.` | Toggle hidden files |
| `⌘⇧A` | Toggle aliases |

### Tabs
| Shortcut | Action |
| --- | --- |
| `⌘T` | New Tab |
| `⌘⇧D` | Duplicate Tab |
| `⌃⇥` | Select next tab |
| `⌃⇧⇥` | Select previous tab |

### Navigation
| Shortcut | Action |
| --- | --- |
| `⌘[` | Back |
| `⌫` | Back (when the file list is focused) |
| `⌘]` | Forward |
| `⌘↑` | Enclosing folder |
| `⌘⇧G` | Go to Folder |
| `⌘⇧H` | Home |
| `⌘K` | Connect to Server |

## Platform support

MaXplorer targets macOS 26 and newer (deployment target 26.5), so it adopts the latest system polish — most notably Liquid Glass — directly, without availability checks.

Current macOS 26 enhancements:

- Liquid Glass surfaces for the toolbar button groups, filter field, and path bar.
- The About and Settings canvases use Liquid Glass cards.
