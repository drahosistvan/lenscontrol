import AppKit

/// The menu-bar glyph from the design (option 1k): a ring of radius 6.6 pt with
/// six aperture-blade strokes meeting a hexagonal opening, on a 16 pt canvas.
/// Drawn on demand so it is crisp at any backing scale, and marked as a template
/// so macOS tints it for light, dark and highlighted menu bars.
enum MenuBarIcon {
    static let normal = make(alpha: 1)
    /// 45 % when no camera is connected.
    static let dimmed = make(alpha: 0.45)

    private static func make(alpha: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.withAlphaComponent(alpha).setStroke()

            let ring = NSBezierPath(ovalIn: NSRect(x: 8 - 6.6, y: 8 - 6.6, width: 13.2, height: 13.2))
            ring.lineWidth = 1.3
            ring.stroke()

            let blades = NSBezierPath()
            blades.lineWidth = 1.1
            blades.lineJoinStyle = .round
            blades.lineCapStyle = .butt
            // Hexagonal opening.
            blades.move(to: NSPoint(x: 8, y: 5))
            blades.line(to: NSPoint(x: 10.6, y: 6.5))
            blades.line(to: NSPoint(x: 10.6, y: 9.5))
            blades.line(to: NSPoint(x: 8, y: 11))
            blades.line(to: NSPoint(x: 5.4, y: 9.5))
            blades.line(to: NSPoint(x: 5.4, y: 6.5))
            blades.close()
            // Six blades, each running from a hexagon corner out to the ring.
            let strokes: [(NSPoint, NSPoint)] = [
                (NSPoint(x: 10.6, y: 6.5), NSPoint(x: 14.55, y: 8.78)),
                (NSPoint(x: 10.6, y: 9.5), NSPoint(x: 10.6, y: 14.07)),
                (NSPoint(x: 8, y: 11), NSPoint(x: 4.05, y: 13.28)),
                (NSPoint(x: 5.4, y: 9.5), NSPoint(x: 1.45, y: 7.22)),
                (NSPoint(x: 5.4, y: 6.5), NSPoint(x: 5.4, y: 1.93)),
                (NSPoint(x: 8, y: 5), NSPoint(x: 11.96, y: 2.72)),
            ]
            for (from, to) in strokes {
                blades.move(to: from)
                blades.line(to: to)
            }
            blades.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LensBar"
        return image
    }
}
