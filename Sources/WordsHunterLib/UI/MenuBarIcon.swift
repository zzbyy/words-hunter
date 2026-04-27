import AppKit

/// Aperture mark used in the menu bar and the capture bubble.
/// Filled interpretation of the design's `MenuBarTemplate`: a bold solid
/// disc with a thin transparent ring punched out (so it reads as an
/// aperture / scope) plus four crosshair ticks outside the body.
/// Drawn in the design's 32×32 grid so the source-of-truth coords stay
/// readable at any output size.
enum MenuBarIcon {
    /// Paint the aperture mark centered on `center`, fitting a square of
    /// `size` pt, using `color` for every fill.
    static func draw(centeredAt center: NSPoint, size: CGFloat, color: NSColor) {
        guard NSGraphicsContext.current != nil else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }

        let t = NSAffineTransform()
        t.translateX(by: center.x - size / 2, yBy: center.y - size / 2)
        t.scale(by: size / 32.0)
        t.concat()

        color.setFill()

        // Body: outer disc minus a thin ring (the aperture line) plus the
        // inner signal pip. Three nested ovals + even-odd fill resolves to:
        //   r 5..9   → outer ring (filled)
        //   r 4..5   → transparent gap (the aperture line)
        //   r 0..4   → inner pip (filled)
        let body = NSBezierPath()
        body.windingRule = .evenOdd
        body.appendOval(in: NSRect(x: 16 - 9, y: 16 - 9, width: 18, height: 18))
        body.appendOval(in: NSRect(x: 16 - 5, y: 16 - 5, width: 10, height: 10))
        body.appendOval(in: NSRect(x: 16 - 4, y: 16 - 4, width: 8,  height: 8))
        body.fill()

        // Crosshair ticks outside the body, capsule-shaped.
        let tickW: CGFloat = 2.4
        let tickH: CGFloat = 3.0
        let r0: CGFloat = 9.5
        let cap = tickW / 2
        let ticks: [NSRect] = [
            NSRect(x: 16 - tickW / 2,  y: 16 + r0,           width: tickW, height: tickH), // top
            NSRect(x: 16 - tickW / 2,  y: 16 - r0 - tickH,   width: tickW, height: tickH), // bottom
            NSRect(x: 16 - r0 - tickH, y: 16 - tickW / 2,    width: tickH, height: tickW), // left
            NSRect(x: 16 + r0,         y: 16 - tickW / 2,    width: tickH, height: tickW)  // right
        ]
        for r in ticks {
            NSBezierPath(roundedRect: r, xRadius: cap, yRadius: cap).fill()
        }
    }

    /// Menu-bar template image. `isTemplate = true` lets macOS tint it for
    /// light/dark menu bars automatically.
    static func template(pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { _ in
            draw(centeredAt: NSPoint(x: pointSize / 2, y: pointSize / 2),
                 size: pointSize, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }
}
