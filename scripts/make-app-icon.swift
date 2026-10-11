import AppKit
import CoreGraphics

// Trip Butler app icon: a jet climbing through soft clouds into a warm sky.
// Run from the AppIcon.appiconset folder:
//   swift ../../../scripts/make-app-icon.swift

enum Variant { case light, dark, tinted }

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// A puffy cloud: overlapping circles on a flat base, as one path.
func cloud(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let h = w * 0.34
    p.addRoundedRect(in: CGRect(x: x, y: y + h * 0.45, width: w, height: h * 0.55), cornerWidth: h * 0.27, cornerHeight: h * 0.27)
    p.addEllipse(in: CGRect(x: x + w * 0.10, y: y + h * 0.20, width: w * 0.34, height: w * 0.34 * 0.9))
    p.addEllipse(in: CGRect(x: x + w * 0.30, y: y - h * 0.15, width: w * 0.44, height: w * 0.44 * 0.9))
    p.addEllipse(in: CGRect(x: x + w * 0.58, y: y + h * 0.15, width: w * 0.30, height: w * 0.30 * 0.9))
    return p
}

/// Side-on airliner pointing right, nose at the origin's right; drawn in a 600-wide box centred at (0,0).
func plane() -> CGPath {
    let p = CGMutablePath()
    // Fuselage
    p.addRoundedRect(in: CGRect(x: -300, y: -34, width: 560, height: 68), cornerWidth: 34, cornerHeight: 34)
    // Nose cone
    p.move(to: CGPoint(x: 230, y: -34))
    p.addQuadCurve(to: CGPoint(x: 300, y: 4), control: CGPoint(x: 300, y: -34))
    p.addQuadCurve(to: CGPoint(x: 230, y: 34), control: CGPoint(x: 290, y: 34))
    p.closeSubpath()
    // Main wing (sweeps back and down toward the viewer)
    p.move(to: CGPoint(x: 90, y: 10))
    p.addLine(to: CGPoint(x: -70, y: 230))
    p.addLine(to: CGPoint(x: -150, y: 230))
    p.addLine(to: CGPoint(x: -50, y: 10))
    p.closeSubpath()
    // Tail fin
    p.move(to: CGPoint(x: -220, y: -20))
    p.addLine(to: CGPoint(x: -300, y: -160))
    p.addLine(to: CGPoint(x: -340, y: -160))
    p.addLine(to: CGPoint(x: -300, y: -20))
    p.closeSubpath()
    // Tail plane
    p.move(to: CGPoint(x: -240, y: 10))
    p.addLine(to: CGPoint(x: -300, y: 80))
    p.addLine(to: CGPoint(x: -340, y: 80))
    p.addLine(to: CGPoint(x: -300, y: 10))
    p.closeSubpath()
    return p
}

func render(_ v: Variant, to path: String) {
    let S: CGFloat = 1024
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1) // y-down

    // Sky: deep blue at the top into a warm sunrise glow near the horizon.
    let sky: [CGColor] = switch v {
    case .light: [color(0x1D4ED8), color(0x3B82F6), color(0x7DD3FC), color(0xFDBA74)]
    case .dark: [color(0x0B1430), color(0x13244D), color(0x1E3A6B), color(0x5B3A4A)]
    case .tinted: [color(0x000000), color(0x000000), color(0x000000), color(0x000000)]
    }
    ctx.drawLinearGradient(CGGradient(colorsSpace: cs, colors: sky as CFArray, locations: [0, 0.45, 0.78, 1])!,
                           start: CGPoint(x: S / 2, y: 0), end: CGPoint(x: S / 2, y: S), options: [])
    if v != .tinted {
        // Sun glow low on the right.
        let sun = CGGradient(colorsSpace: cs, colors: [color(0xFFE7A3, v == .light ? 0.85 : 0.35), color(0xFFE7A3, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(sun, startCenter: CGPoint(x: S * 0.78, y: S * 0.80), startRadius: 0,
                               endCenter: CGPoint(x: S * 0.78, y: S * 0.80), endRadius: S * 0.45, options: [])
    }

    let cloudBack: CGColor = v == .tinted ? color(0xFFFFFF, 0.35) : (v == .light ? color(0xFFFFFF, 0.55) : color(0xC7D2FE, 0.25))
    let cloudFront: CGColor = v == .tinted ? color(0xFFFFFF, 0.8) : (v == .light ? color(0xFFFFFF) : color(0xE0E7FF))

    // Back clouds (behind the plane).
    ctx.setFillColor(cloudBack)
    ctx.addPath(cloud(60, 250, 360)); ctx.fillPath()
    ctx.addPath(cloud(640, 170, 300)); ctx.fillPath()

    // Contrail behind the plane.
    ctx.saveGState()
    ctx.translateBy(x: 520, y: 470); ctx.rotate(by: -0.42)
    let trail = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0), color(0xFFFFFF, v == .tinted ? 0.5 : 0.75)] as CFArray, locations: [0, 1])!
    ctx.addRect(CGRect(x: -620, y: -14, width: 360, height: 28)); ctx.clip()
    ctx.drawLinearGradient(trail, start: CGPoint(x: -620, y: 0), end: CGPoint(x: -260, y: 0), options: [])
    ctx.restoreGState()

    // The plane, climbing up and to the right.
    ctx.saveGState()
    ctx.translateBy(x: 530, y: 440); ctx.rotate(by: -0.42); ctx.scaleBy(x: 1.05, y: 1.05)
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 30, color: color(0x0B1430, v == .tinted ? 0.2 : 0.35))
    ctx.addPath(plane())
    ctx.setFillColor(v == .tinted ? color(0xFFFFFF) : color(0xFFFFFF))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    if v != .tinted {
        // Window stripe and an accent on the tail.
        ctx.setFillColor(color(0x1D4ED8, v == .light ? 0.9 : 0.7))
        for i in 0..<9 { ctx.fillEllipse(in: CGRect(x: 150 - CGFloat(i) * 44, y: -12, width: 20, height: 18)) }
        // Orange tail fin.
        ctx.setFillColor(color(0xF97316))
        let fin = CGMutablePath()
        fin.move(to: CGPoint(x: -220, y: -30)); fin.addLine(to: CGPoint(x: -300, y: -160))
        fin.addLine(to: CGPoint(x: -340, y: -160)); fin.addLine(to: CGPoint(x: -300, y: -30)); fin.closeSubpath()
        ctx.addPath(fin); ctx.fillPath()
    }
    ctx.restoreGState()

    // Front clouds the plane is bursting out of.
    ctx.setFillColor(cloudFront)
    // A billowing bank of clouds across the bottom (no flat edge).
    for (x, y, w) in [(-90.0, 690.0, 470.0), (250, 735, 430), (560, 680, 520), (-60, 820, 560), (380, 840, 700), (-40, 900, 600), (480, 910, 640), (200, 930, 520)] {
        ctx.addPath(cloud(CGFloat(x), CGFloat(y), CGFloat(w))); ctx.fillPath()
    }
    ctx.fill(CGRect(x: 0, y: 830, width: S, height: S - 830))

    let image = ctx.makeImage()!
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(.light, to: "AppIcon.png")
render(.dark, to: "AppIcon-Dark.png")
render(.tinted, to: "AppIcon-Tinted.png")
