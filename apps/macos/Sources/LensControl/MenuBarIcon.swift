import AppKit

/// The menu-bar glyph from the design canvas (menu-bar glyph round 3, option J3):
/// a filled camera body with a slider slot cut straight through it and the lens
/// sitting on the slot as the knob, on a 16 pt canvas. One silhouette, so it
/// reads at 16 pt; the slot and knob say "control". Drawn on demand so it is
/// crisp at any backing scale, and marked as a template so macOS tints it for
/// light, dark and highlighted menu bars.
enum MenuBarIcon {
    static let normal = make(alpha: 1)
    /// 45 % when no camera is connected.
    static let dimmed = make(alpha: 0.45)

    private static func make(alpha: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let ink = NSColor.black.withAlphaComponent(alpha).cgColor
            ctx.setFillColor(ink)

            // Viewfinder hump: 7.6 × 3 from y 2, 1 pt corners; its lower half is inside the body.
            ctx.addPath(CGPath(roundedRect: CGRect(x: 4.2, y: 2, width: 7.6, height: 3),
                               cornerWidth: 1, cornerHeight: 1, transform: nil))
            ctx.fillPath()

            // Body: 14.4 × 11 from (0.8, 3.6), 2.6 pt corners.
            ctx.addPath(CGPath(roundedRect: CGRect(x: 0.8, y: 3.6, width: 14.4, height: 11),
                               cornerWidth: 2.6, cornerHeight: 2.6, transform: nil))
            ctx.fillPath()

            // Cut-outs (the template keeps the transparency): the slider slot, 11.6 × 2.2
            // with round ends, and a 3.8 pt clear ring around the lens.
            ctx.setBlendMode(.clear)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 2.2, y: 8.2, width: 11.6, height: 2.2),
                               cornerWidth: 1.1, cornerHeight: 1.1, transform: nil))
            ctx.fillPath()
            ctx.fillEllipse(in: CGRect(x: 8 - 3.8, y: 9.3 - 3.8, width: 7.6, height: 7.6))
            ctx.setBlendMode(.normal)

            // Lens as the knob: 5 pt filled disc at (8, 9.3).
            ctx.setFillColor(ink)
            ctx.fillEllipse(in: CGRect(x: 8 - 2.5, y: 9.3 - 2.5, width: 5, height: 5))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LensControl"
        return image
    }
}
