# Disk Storage Analyzer feature

## Design Specs

Space Analyzer inherits the design concept from apps such as GrandPerspective (https://grandperspectiv.sourceforge.net/).
The concept is to show a map of the of everything under a specific path, including statistics at the bottom of Total/Free space (for the selected volume)

### Tab Rules

- When Space Explorer is used, it shows as an additional tab in the top pane. The tab should have a different color, to differentiate between regular folder tabs
- There can only be a single space explorer tab
- The tab default location is always the left-most position, although it can be moved like the other tabs later (by user mouse drag)
- The tab should have an icon next to its name. The Icon should look like a few colorful rectangles. Keep it simple yet modern

### Getting into Space Explorer

To enter Space Explorer (when still not visible tab) provide the following options:
1. A new option between "Network" and "Copy Queue" sections on the left pane
2. A new icon at the top toolbar, with the same icon as the tab
3. Right clicking a folder should introduce a new option: "Space Explorer under selected folder"

### Look and feel

When entering space explorer, it should indicate when scanning (both surface and tab) and when complete.
Scanning should have a "Cancel" option (appears on the Space Explorer surface as a button)
Space Explorer surface should also contain a "Root Folder" textbox that can be changed by the user, and a "Refresh" button
Post acanning, tiles are displayed. Each tile displays the file/folder name at the bottom
Clicking a tile does nothing
Right-Clicking a tile provides the following options:
- Open: attempt to open the file, just like double-clicking a file
- Browse Location: open a new tab on the selected location (folder or network location)
- Copy Path to Clipboard

#### Colors

Colors should match the App modern theme. Modern and simple
Attempt to use colors by file categories, such as:
- Media (Videos)
- Media (Music)
- Apps
- Archives
- Images

Unrecognized categories should all have the same color.
Make the categories a configurable .json file that can be easily changed later
Colors style should be solid (not gradient)
