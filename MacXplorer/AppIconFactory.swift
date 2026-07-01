import AppKit

enum AppIconFactory {
    static func makeIcon() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(origin: .zero, size: size)
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 34, dy: 34), xRadius: 92, yRadius: 92)
        NSColor(calibratedRed: 0.10, green: 0.37, blue: 0.72, alpha: 1).setFill()
        background.fill()

        let highlight = NSBezierPath(roundedRect: NSRect(x: 68, y: 276, width: 376, height: 118), xRadius: 44, yRadius: 44)
        NSColor(calibratedRed: 0.19, green: 0.58, blue: 0.93, alpha: 1).setFill()
        highlight.fill()

        let folderTab = NSBezierPath(roundedRect: NSRect(x: 104, y: 318, width: 146, height: 76), xRadius: 28, yRadius: 28)
        NSColor(calibratedRed: 0.44, green: 0.76, blue: 1.0, alpha: 1).setFill()
        folderTab.fill()

        let body = NSBezierPath(roundedRect: NSRect(x: 68, y: 116, width: 376, height: 252), xRadius: 54, yRadius: 54)
        NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.0, alpha: 1).setFill()
        body.fill()

        let sidebar = NSBezierPath(roundedRect: NSRect(x: 108, y: 154, width: 72, height: 176), xRadius: 22, yRadius: 22)
        NSColor(calibratedRed: 0.75, green: 0.86, blue: 0.96, alpha: 1).setFill()
        sidebar.fill()

        NSColor(calibratedRed: 0.18, green: 0.38, blue: 0.62, alpha: 1).setStroke()
        for y in [288, 242, 196] {
            let row = NSBezierPath()
            row.lineWidth = 18
            row.lineCapStyle = .round
            row.move(to: NSPoint(x: 214, y: y))
            row.line(to: NSPoint(x: 368, y: y))
            row.stroke()
        }

        return image
    }
}
