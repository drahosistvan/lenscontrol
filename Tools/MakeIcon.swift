#!/usr/bin/env swift
// Renders the LensBar app icon from the Claude Design spec (option 1l) at every
// .iconset size with CoreGraphics, so each size is drawn as vector rather than
// downsampled. Usage:  swift Tools/MakeIcon.swift <output.iconset>
//
// Spec: macOS squircle (824/1024 of the canvas) in pale aluminium; dark barrel
// with a brushed conic ring; black inner ring; six-blade disk; hexagonal opening
// with a blue-black glass gradient; one soft highlight. At 32 px and below the
// gradients and highlight drop out so the ring-and-hexagon still reads.

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

func hexagon(in rect: CGRect) -> CGPath {
    // CSS polygon(50% 0, 100% 25%, 100% 75%, 50% 100%, 0 75%, 0 25%), y measured from the top.
    let p = CGMutablePath()
    func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * fx, y: rect.maxY - rect.height * fy)
    }
    p.move(to: pt(0.5, 0))
    p.addLine(to: pt(1, 0.25)); p.addLine(to: pt(1, 0.75)); p.addLine(to: pt(0.5, 1))
    p.addLine(to: pt(0, 0.75)); p.addLine(to: pt(0, 0.25))
    p.closeSubpath()
    return p
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
    ctx.drawLinearGradient(gradient([(rgb(0xf7f7f5), 0), (rgb(0xd4d4cf), 1)]),
                           start: CGPoint(x: 0, y: squircle.maxY), end: CGPoint(x: 0, y: squircle.minY), options: [])
    if !simple {
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

    // Barrel: circle inset 13 % of the squircle, brushed conic ring.
    let barrel = squircle.insetBy(dx: squircle.width * 0.13, dy: squircle.height * 0.13)
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

    // Inner ring: inset 8 % of the barrel, near-black.
    let inner = barrel.insetBy(dx: barrel.width * 0.08, dy: barrel.height * 0.08)
    ctx.setFillColor(rgb(0x0c0d0f))
    ctx.fillEllipse(in: inner)
    if !simple {
        ctx.setStrokeColor(rgb(0xffffff, 0.08))
        ctx.setLineWidth(1.5 * unit)
        ctx.strokeEllipse(in: inner.insetBy(dx: 0.75 * unit, dy: 0.75 * unit))
    }

    // Blade disk: inset 6 % of the inner ring, six flat wedges from 12°.
    let disk = inner.insetBy(dx: inner.width * 0.06, dy: inner.height * 0.06)
    let diskCenter = CGPoint(x: disk.midX, y: disk.midY)
    let diskRadius = disk.width / 2
    ctx.saveGState()
    ctx.addEllipse(in: disk)
    ctx.clip()
    if simple {
        ctx.setFillColor(rgb(0x27292c))
        ctx.fill(disk)
    } else {
        let blades = [rgb(0x2e3034), rgb(0x222427), rgb(0x323438), rgb(0x1f2124), rgb(0x2f3135), rgb(0x232528)]
        for (i, color) in blades.enumerated() {
            let from = 12 + CGFloat(i) * 60
            fillWedge(ctx, center: diskCenter, radius: diskRadius + 1, cssFrom: from, cssTo: from + 60.5, color: color)
        }
    }

    // Hexagonal opening: inset 31 % of the disk, glass gradient from the upper left.
    let opening = disk.insetBy(dx: disk.width * 0.31, dy: disk.height * 0.31)
    let hex = hexagon(in: opening)
    ctx.saveGState()
    ctx.addPath(hex)
    ctx.clip()
    if simple {
        ctx.setFillColor(rgb(0x1a2c46))
        ctx.fill(opening)
    } else {
        let focus = CGPoint(x: opening.minX + opening.width * 0.38, y: opening.maxY - opening.height * 0.34)
        let farthest = max(hypot(opening.maxX - focus.x, focus.y - opening.minY),
                           hypot(focus.x - opening.minX, opening.maxY - focus.y))
        ctx.drawRadialGradient(gradient([(rgb(0x4a6f9e), 0), (rgb(0x101b2c), 0.55), (rgb(0x04070b), 1)]),
                               startCenter: focus, startRadius: 0, endCenter: focus, endRadius: farthest, options: [])
    }
    ctx.restoreGState()

    // Soft glass highlight over the disk: ellipse 60 % × 45 % at (32 %, 24 %).
    if !simple {
        ctx.saveGState()
        let hx = disk.minX + disk.width * 0.32, hy = disk.maxY - disk.height * 0.24
        let rx = disk.width * 0.60, ry = disk.height * 0.45
        ctx.translateBy(x: hx, y: hy)
        ctx.scaleBy(x: 1, y: ry / rx)
        ctx.drawRadialGradient(gradient([(rgb(0xffffff, 0.26), 0), (rgb(0xffffff, 0), 0.7)]),
                               startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: rx, options: [])
        ctx.restoreGState()
    }
    ctx.restoreGState()   // disk clip
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
