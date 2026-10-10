import AppKit
import CoreGraphics

// Trip Butler app icon: a butler's serving cloche on a tray, with a map pin as its handle
// ("your trip, served"). Run from the AppIcon.appiconset folder:
//   swift ../../../scripts/make-app-icon.swift

enum Variant { case light, dark, tinted }

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Teardrop map pin: round head of radius r centred at (cx, cy), tip at tipY.
func pinPath(cx: CGFloat, cy: CGFloat, r: CGFloat, tipY: CGFloat) -> CGPath {
    let d = tipY - cy
    let alpha = acos(r / d)
    let left = CGPoint(x: cx - r * sin(alpha), y: cy + r * cos(alpha))
    let right = CGPoint(x: cx + r * sin(alpha), y: cy + r * cos(alpha))
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx, y: tipY))
    p.addLine(to: left)
    p.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: atan2(left.y - cy, left.x - cx),
             endAngle: atan2(right.y - cy, right.x - cx), clockwise: false)
    p.closeSubpath()
    return p
}

func render(_ v: Variant, to path: String) {
    let S: CGFloat = 1024
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1) // y-down

    // Background: deep navy into teal, with a warm glow behind the dome.
    let bg: [CGColor] = switch v {
    case .light: [color(0x123A5A), color(0x0E5E6F), color(0x0B7A74)]
    case .dark: [color(0x0A1724), color(0x08141C), color(0x050B10)]
    case .tinted: [color(0x000000), color(0x000000)]
    }
    let g = CGGradient(colorsSpace: cs, colors: bg as CFArray, locations: bg.count == 3 ? [0, 0.55, 1] : [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: S * 0.15, y: 0), end: CGPoint(x: S * 0.85, y: S),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    if v != .tinted {
        let glow = CGGradient(colorsSpace: cs, colors: [color(0xFFC86B, v == .light ? 0.30 : 0.16), color(0xFFC86B, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S / 2, y: S * 0.52), startRadius: 0,
                               endCenter: CGPoint(x: S / 2, y: S * 0.52), endRadius: S * 0.55, options: [])
    }

    let cx = S / 2
    let trayY: CGFloat = 742          // top of the tray
    let domeR: CGFloat = 318          // dome radius (half-ellipse)
    let domeH: CGFloat = 300          // dome height

    // Soft shadow under the tray.
    ctx.saveGState()
    ctx.setFillColor(color(0x000000, v == .tinted ? 0.25 : 0.22))
    ctx.fillEllipse(in: CGRect(x: cx - 360, y: trayY + 52, width: 720, height: 56))
    ctx.restoreGState()

    // Dome (cloche): polished silver, or white for tinted.
    let dome = CGMutablePath()
    dome.move(to: CGPoint(x: cx - domeR, y: trayY))
    dome.addCurve(to: CGPoint(x: cx, y: trayY - domeH),
                  control1: CGPoint(x: cx - domeR, y: trayY - domeH * 0.62), control2: CGPoint(x: cx - domeR * 0.58, y: trayY - domeH))
    dome.addCurve(to: CGPoint(x: cx + domeR, y: trayY),
                  control1: CGPoint(x: cx + domeR * 0.58, y: trayY - domeH), control2: CGPoint(x: cx + domeR, y: trayY - domeH * 0.62))
    dome.closeSubpath()
    ctx.saveGState()
    ctx.addPath(dome); ctx.clip()
    let silver: [CGColor] = switch v {
    case .light: [color(0xFFFFFF), color(0xE9EEF2), color(0xB9C6D0)]
    case .dark: [color(0xE6ECF0), color(0xC3CED6), color(0x8E9EAA)]
    case .tinted: [color(0xFFFFFF), color(0xDDDDDD), color(0xAAAAAA)]
    }
    let sg = CGGradient(colorsSpace: cs, colors: silver as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(sg, start: CGPoint(x: cx - domeR, y: trayY - domeH), end: CGPoint(x: cx + domeR, y: trayY), options: [])
    // Highlight streak on the upper left of the dome.
    let hl = CGMutablePath()
    hl.addEllipse(in: CGRect(x: cx - 230, y: trayY - 250, width: 120, height: 210), transform: CGAffineTransform(translationX: cx - 170, y: trayY - 145).rotated(by: -0.55).translatedBy(x: -(cx - 170), y: -(trayY - 145)))
    ctx.addPath(hl)
    ctx.setFillColor(color(0xFFFFFF, 0.55)); ctx.fillPath()
    ctx.restoreGState()

    // Tray: gold band with a rim.
    let gold: [CGColor] = v == .tinted ? [color(0xFFFFFF), color(0xCCCCCC)] : [color(0xFFD27A), color(0xE9A23B)]
    let tray = CGPath(roundedRect: CGRect(x: cx - 380, y: trayY - 6, width: 760, height: 58), cornerWidth: 29, cornerHeight: 29, transform: nil)
    ctx.saveGState(); ctx.addPath(tray); ctx.clip()
    ctx.drawLinearGradient(CGGradient(colorsSpace: cs, colors: gold as CFArray, locations: [0, 1])!,
                           start: CGPoint(x: 0, y: trayY - 6), end: CGPoint(x: 0, y: trayY + 52), options: [])
    ctx.restoreGState()

    // Handle: a coral map pin sitting on the top of the dome.
    let pinR: CGFloat = 92, pinCY: CGFloat = trayY - domeH - 120, pinTip: CGFloat = trayY - domeH + 14
    let pin = pinPath(cx: cx, cy: pinCY, r: pinR, tipY: pinTip)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x000000, 0.28))
    ctx.addPath(pin)
    ctx.setFillColor(v == .tinted ? color(0xFFFFFF) : color(0xFF6B5B))
    ctx.fillPath()
    ctx.restoreGState()
    if v != .tinted {
        ctx.saveGState(); ctx.addPath(pin); ctx.clip()
        let coral = CGGradient(colorsSpace: cs, colors: [color(0xFF8A70), color(0xE8473F)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(coral, start: CGPoint(x: cx - pinR, y: pinCY - pinR), end: CGPoint(x: cx + pinR, y: pinTip), options: [])
        ctx.restoreGState()
    }
    // Pin hole.
    ctx.setFillColor(v == .tinted ? color(0x000000) : (v == .light ? color(0x123A5A) : color(0x0A1724)))
    ctx.fillEllipse(in: CGRect(x: cx - 36, y: pinCY - 36, width: 72, height: 72))

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(.light, to: "AppIcon.png")
render(.dark, to: "AppIcon-Dark.png")
render(.tinted, to: "AppIcon-Tinted.png")
