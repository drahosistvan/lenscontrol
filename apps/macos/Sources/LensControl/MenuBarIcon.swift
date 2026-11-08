import AppKit

/// The menu-bar glyph from the design canvas (menu-bar glyph round 2, option G):
/// a large filled lens disc with a small filled knob overlapping at lower right,
/// separated by a 1.5 pt transparent ring, on a 16 pt canvas. Two solid shapes,
/// so it stays legible at 16 pt on any menu bar. Drawn on demand so it is crisp
/// at any backing scale, and marked as a template so macOS tints it for light,
/// dark and highlighted menu bars.
enum MenuBarIcon {
    static let normal = make(alpha: 1)
    /// 45 % when no camera is connected.
    static let dimmed = make(alpha: 0.45)

    private static func make(alpha: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let ink = NSColor.black.withAlphaComponent(alpha).cgColor

            // Lens: filled disc, centre (6.8, 6.8), radius 5.8.
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: CGRect(x: 6.8 - 5.8, y: 6.8 - 5.8, width: 11.6, height: 11.6))

            // Gap: erase a disc of radius 4.6 around the knob so the two shapes
            // never touch (template images keep the transparency).
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: 12 - 4.6, y: 12 - 4.6, width: 9.2, height: 9.2))
            ctx.setBlendMode(.normal)

            // Knob: filled disc, centre (12, 12), radius 3.1.
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: CGRect(x: 12 - 3.1, y: 12 - 3.1, width: 6.2, height: 6.2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LensControl"
        return image
    }
}
