import AppKit

/// The menu-bar glyph from the design canvas (menu-bar glyph direction A): a lens
/// ring of radius 6 pt with one slider chord and a filled knob in its lower third,
/// the app icon's control strip reduced to a single line, on a 16 pt canvas.
/// Drawn on demand so it is crisp at any backing scale, and marked as a template
/// so macOS tints it for light, dark and highlighted menu bars.
enum MenuBarIcon {
    static let normal = make(alpha: 1)
    /// 45 % when no camera is connected.
    static let dimmed = make(alpha: 0.45)

    private static func make(alpha: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            let ink = NSColor.black.withAlphaComponent(alpha)
            ink.setStroke()
            ink.setFill()

            // Lens ring, centred slightly above the middle to leave room for the slider.
            let ring = NSBezierPath(ovalIn: NSRect(x: 8 - 6.2, y: 7.5 - 6.2, width: 12.4, height: 12.4))
            ring.lineWidth = 1.3
            ring.stroke()

            // Slider track: a chord across the lower third of the ring, clear of its edge.
            let track = NSBezierPath()
            track.lineWidth = 1.3
            track.lineCapStyle = .round
            track.move(to: NSPoint(x: 4.3, y: 10.6))
            track.line(to: NSPoint(x: 11.7, y: 10.6))
            track.stroke()

            // Knob at about two thirds along the track.
            NSBezierPath(ovalIn: NSRect(x: 9.3 - 1.7, y: 10.6 - 1.7, width: 3.4, height: 3.4)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LensControl"
        return image
    }
}
