import AppKit
import CoreGraphics

/// Draws the MaXplorer app icon: a modern, simple mash-up of Windows 11 File
/// Explorer (yellow folder) and macOS Finder (blue), combining both brand
/// colors — a yellow back/tab with a Finder-style two-tone blue front and a
/// white page peeking out.
///
/// The same artwork is rendered to PNGs in `Assets.xcassets/AppIcon.appiconset`
/// (the bundled Finder/Dock icon); this factory keeps the runtime-set dock icon
/// in sync. Geometry is authored in a 1024x1024, top-left-origin space.
enum AppIconFactory {
    static func makeIcon() -> NSImage {
        let side: CGFloat = 1024
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(into: ctx, pixelSize: side)
            return true
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
               cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func fillGradient(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor],
                                     _ locs: [CGFloat], from: CGPoint, to: CGPoint) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: locs)!
        ctx.drawLinearGradient(grad, start: from, end: to,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    private static func draw(into ctx: CGContext, pixelSize: CGFloat) {
        let scale = pixelSize / 1024.0
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        // Flip to a top-left origin, y-down space of 1024x1024.
        ctx.translateBy(x: 0, y: 1024)
        ctx.scaleBy(x: 1, y: -1)

        // Tile background (macOS squircle).
        let tile = rr(96, 96, 832, 832, 186)
        fillGradient(ctx, tile,
                     [rgb(253, 254, 255), rgb(230, 238, 249)], [0, 1],
                     from: CGPoint(x: 512, y: 96), to: CGPoint(x: 512, y: 928))
        ctx.saveGState()
        ctx.addPath(tile)
        ctx.setStrokeColor(rgb(10, 40, 80, 0.10))
        ctx.setLineWidth(4)
        ctx.strokePath()
        ctx.restoreGState()

        // Soft drop shadow beneath the folder.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 26), blur: 46, color: rgb(20, 50, 90, 0.28))
        ctx.addPath(rr(250, 470, 524, 300, 46))
        ctx.setFillColor(rgb(255, 255, 255, 1))
        ctx.fillPath()
        ctx.restoreGState()

        // Yellow back folder + tab (Windows).
        let yellow = CGMutablePath()
        yellow.addPath(rr(238, 330, 250, 120, 40))
        yellow.addPath(rr(238, 396, 548, 366, 52))
        fillGradient(ctx, yellow,
                     [rgb(255, 214, 92), rgb(247, 165, 24)], [0, 1],
                     from: CGPoint(x: 512, y: 330), to: CGPoint(x: 512, y: 762))

        // White page peeking above the blue front.
        fillGradient(ctx, rr(300, 432, 424, 300, 22),
                     [rgb(255, 255, 255), rgb(226, 233, 242)], [0, 1],
                     from: CGPoint(x: 512, y: 432), to: CGPoint(x: 512, y: 732))

        // Blue Finder-style front cover.
        let front = rr(238, 486, 548, 276, 52)
        fillGradient(ctx, front,
                     [rgb(64, 170, 255), rgb(10, 108, 224)], [0, 1],
                     from: CGPoint(x: 512, y: 486), to: CGPoint(x: 512, y: 762))
        // Finder two-tone: deeper blue on the left, split diagonally.
        ctx.saveGState()
        ctx.addPath(front)
        ctx.clip()
        let twoTone = CGMutablePath()
        twoTone.move(to: CGPoint(x: 238, y: 486))
        twoTone.addLine(to: CGPoint(x: 520, y: 486))
        twoTone.addLine(to: CGPoint(x: 360, y: 762))
        twoTone.addLine(to: CGPoint(x: 238, y: 762))
        twoTone.closeSubpath()
        ctx.addPath(twoTone)
        ctx.setFillColor(rgb(9, 88, 200, 0.55))
        ctx.fillPath()
        // Top highlight strip.
        ctx.addPath(rr(238, 486, 548, 74, 52))
        ctx.setFillColor(rgb(255, 255, 255, 0.16))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.restoreGState()
    }
}
