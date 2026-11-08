#!/usr/bin/env swift
// Renders the LensControl app icon from the design canvas (icon direction 2,
// "lens + HUD sliders") at every .iconset size with CoreGraphics, so each size is
// drawn as vector rather than downsampled. Usage:  swift Tools/MakeIcon.swift <output.iconset>
//
// Spec: macOS squircle (824/1024 of the canvas) in pale aluminium; dark barrel
// with a brushed conic ring; black inner ring; blue-black glass; one soft
// highlight. Over the lower third of the lens sits a dark control strip with two
// pill sliders, blue (exposure) and amber (white balance), each with a white
// knob: the app's own panel as the "this controls the camera" cue. At 32 px and
// below the gradients, highlight and knobs drop out so lens + two bars still read.

import AppKit

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let colorSpace = CGColorSpaceCreateDeviceRGB()

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

/// Linear interpolation between evenly spaced colour stops.
func blend(_ colors: [CGColor], at t: CGFloat) -> CGColor {
    let scaled = t.truncatingRemainder(dividingBy: 1) * CGFloat(colors.count - 1)
    let index = Int(scaled)
    let f = scaled - CGFloat(index)
    let a = colors[index].components!, b = colors[min(index + 1, colors.count - 1)].components!
    return CGColor(srgbRed: a[0] + (b[0] - a[0]) * f, green: a[1] + (b[1] - a[1]) * f,
                   blue: a[2] + (b[2] - a[2]) * f, alpha: 1)
}

/// CSS conic-gradient: angles run clockwise from the top; CoreGraphics runs
/// counter-clockwise from +x, so CSS angle a maps to 90° − a.
func cgAngle(cssDegrees: CGFloat) -> CGFloat { (90 - cssDegrees) * .pi / 180 }

func fillWedge(_ ctx: CGContext, center: CGPoint, radius: CGFloat, cssFrom: CGFloat, cssTo: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    ctx.move(to: center)
    ctx.addArc(center: center, radius: radius, startAngle: cgAngle(cssDegrees: cssFrom),
               endAngle: cgAngle(cssDegrees: cssTo), clockwise: true)
    ctx.closePath()
    ctx.fillPath()
}

/// A rect given CSS-style, as fractions of `parent` measured from its top-left.
func cssRect(in parent: CGRect, left: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    CGRect(x: parent.minX + parent.width * left,
           y: parent.maxY - parent.height * (top + height),
           width: parent.width * width,
           height: parent.height * height)
}

func pill(_ rect: CGRect) -> CGPath {
    let r = rect.height / 2
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

func drawIcon(_ ctx: CGContext, px: Int) {
    let s = CGFloat(px)
    let simple = px <= 32
    let unit = s / 256   // the spec is written on a 256 pt canvas

    // Squircle, 25/256 in from each edge, radius 46/206 of its side.
    let inset = 25 * unit
    let squircle = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = squircle.width * 46 / 206
    let squirclePath = CGPath(roundedRect: squircle, cornerWidth: radius, cornerHeight: radius, transform: nil)

    if !simple {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * unit), blur: 16 * unit, color: rgb(0x000000, 0.22))
        ctx.addPath(squirclePath)
        ctx.setFillColor(rgb(0xe0e0dd))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    if simple {
        ctx.setFillColor(rgb(0xe6e6e2))
        ctx.fill(squircle)
    } else {
        ctx.drawLinearGradient(gradient([(rgb(0xf7f7f5), 0), (rgb(0xd4d4cf), 1)]),
                               start: CGPoint(x: 0, y: squircle.maxY), end: CGPoint(x: 0, y: squircle.minY), options: [])
        // inset 0 2px 0 rgba(255,255,255,.85): a bright line along the top edge
        ctx.setFillColor(rgb(0xffffff, 0.85))
        ctx.fill(CGRect(x: squircle.minX, y: squircle.maxY - 2 * unit, width: squircle.width, height: 2 * unit))
    }
    // hairline inside the edge
    ctx.addPath(squirclePath)
    ctx.setStrokeColor(rgb(0x000000, simple ? 0.10 : 0.08))
    ctx.setLineWidth(max(2, 2 * unit))   // half of it is clipped away
    ctx.strokePath()
    ctx.restoreGState()

    // Barrel: circle inset 12 % of the squircle, brushed conic ring.
    let barrel = squircle.insetBy(dx: squircle.width * 0.12, dy: squircle.height * 0.12)
    let center = CGPoint(x: barrel.midX, y: barrel.midY)
    let barrelRadius = barrel.width / 2
    if simple {
        ctx.setFillColor(rgb(0x3a3c40))
        ctx.fillEllipse(in: barrel)
    } else {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * unit), blur: 12 * unit, color: rgb(0x000000, 0.35))
        ctx.setFillColor(rgb(0x2b2c2f))
        ctx.fillEllipse(in: barrel)
        ctx.restoreGState()
        let brushed = [rgb(0x2b2c2f), rgb(0x5c5e63), rgb(0x2b2c2f), rgb(0x505257), rgb(0x2b2c2f), rgb(0x5c5e63), rgb(0x2b2c2f)]
        ctx.saveGState()
        ctx.addEllipse(in: barrel)
        ctx.clip()
        let step: CGFloat = 1
        var a: CGFloat = 0
        while a < 360 {
            fillWedge(ctx, center: center, radius: barrelRadius + 1, cssFrom: a, cssTo: a + step + 0.6,
                      color: blend(brushed, at: a / 360))
            a += step
        }
        ctx.restoreGState()
    }

    // Glass. Simple: one blue disk inset 14 % of the barrel. Full: near-black
    // inner ring inset 8 %, then the glass inset a further 7 % with a radial
    // blue-black gradient from the upper left and a soft highlight.
    if simple {
        let glass = barrel.insetBy(dx: barrel.width * 0.14, dy: barrel.height * 0.14)
        ctx.setFillColor(rgb(0x1a2c46))
        ctx.fillEllipse(in: glass)
    } else {
        let inner = barrel.insetBy(dx: barrel.width * 0.08, dy: barrel.height * 0.08)
        ctx.setFillColor(rgb(0x0c0d0f))
        ctx.fillEllipse(in: inner)
        ctx.setStrokeColor(rgb(0xffffff, 0.08))
        ctx.setLineWidth(1.5 * unit)
        ctx.strokeEllipse(in: inner.insetBy(dx: 0.75 * unit, dy: 0.75 * unit))

        let glass = inner.insetBy(dx: inner.width * 0.07, dy: inner.height * 0.07)
        ctx.saveGState()
        ctx.addEllipse(in: glass)
        ctx.clip()
        let focus = CGPoint(x: glass.minX + glass.width * 0.38, y: glass.maxY - glass.height * 0.34)
        let farthest = max(hypot(glass.maxX - focus.x, focus.y - glass.minY),
                           hypot(focus.x - glass.minX, glass.maxY - focus.y))
        ctx.drawRadialGradient(gradient([(rgb(0x4a6f9e), 0), (rgb(0x101b2c), 0.55), (rgb(0x04070b), 1)]),
                               startCenter: focus, startRadius: 0, endCenter: focus, endRadius: farthest, options: [])
        // Soft highlight: ellipse 60 % × 45 % at (32 %, 24 %).
        let hx = glass.minX + glass.width * 0.32, hy = glass.maxY - glass.height * 0.24
        let rx = glass.width * 0.60, ry = glass.height * 0.45
        ctx.translateBy(x: hx, y: hy)
        ctx.scaleBy(x: 1, y: ry / rx)
        ctx.drawRadialGradient(gradient([(rgb(0xffffff, 0.26), 0), (rgb(0xffffff, 0), 0.7)]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rx, options: [])
        ctx.restoreGState()
    }

    // Control strip over the lower third: left/right 14 %, bottom 15 %, height 31 % of the squircle.
    let strip = cssRect(in: squircle, left: 0.14, top: 1 - 0.15 - 0.31, width: 0.72, height: 0.31)
    let stripRadius = squircle.width * 14 / 206
    let stripPath = CGPath(roundedRect: strip, cornerWidth: stripRadius, cornerHeight: stripRadius, transform: nil)
    if simple {
        ctx.addPath(stripPath)
        ctx.setFillColor(rgb(0x16181c))
        ctx.fillPath()
        // Two solid bars: blue full-ish width, amber shorter.
        ctx.setFillColor(rgb(0x0a84ff))
        ctx.addPath(pill(cssRect(in: strip, left: 0.12, top: 0.24, width: 0.76, height: 0.16)))
        ctx.fillPath()
        ctx.setFillColor(rgb(0xffb340))
        ctx.addPath(pill(cssRect(in: strip, left: 0.12, top: 0.60, width: 0.48, height: 0.16)))
        ctx.fillPath()
    } else {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * unit), blur: 14 * unit, color: rgb(0x000000, 0.35))
        ctx.addPath(stripPath)
        ctx.setFillColor(rgb(0x16181c, 0.8))
        ctx.fillPath()
        ctx.restoreGState()
        // inset 0 0 0 1px rgba(255,255,255,.14)
        ctx.saveGState()
        ctx.addPath(stripPath)
        ctx.clip()
        ctx.addPath(stripPath)
        ctx.setStrokeColor(rgb(0xffffff, 0.14))
        ctx.setLineWidth(2 * unit)
        ctx.strokePath()
        ctx.restoreGState()

        // Sliders: track left/right 12 % of the strip, 11 % of its height tall;
        // fill to `value`, white knob 19 % of the track width in diameter.
        func slider(top: CGFloat, value: CGFloat, fill: CGColor) {
            let track = cssRect(in: strip, left: 0.12, top: top, width: 0.76, height: 0.11)
            ctx.setFillColor(rgb(0xffffff, 0.22))
            ctx.addPath(pill(track))
            ctx.fillPath()
            ctx.setFillColor(fill)
            ctx.addPath(pill(CGRect(x: track.minX, y: track.minY, width: track.width * value, height: track.height)))
            ctx.fillPath()
            let d = track.width * 0.19
            let knob = CGRect(x: track.minX + track.width * value - d / 2, y: track.midY - d / 2, width: d, height: d)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -1 * unit), blur: 3 * unit, color: rgb(0x000000, 0.4))
            ctx.setFillColor(rgb(0xffffff))
            ctx.fillEllipse(in: knob)
            ctx.restoreGState()
        }
        slider(top: 0.27, value: 0.64, fill: rgb(0x0a84ff))
        slider(top: 0.62, value: 0.36, fill: rgb(0xffb340))
    }
}

func render(px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    drawIcon(ctx, px: px)
    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: MakeIcon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (name, px) in sizes {
    try render(px: px).write(to: outDir.appendingPathComponent("\(name).png"))
}
print("wrote \(sizes.count) sizes to \(outDir.path)")
