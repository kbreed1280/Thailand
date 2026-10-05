import AppKit
import CoreGraphics

enum Variant { case light, dark, tinted }

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func pinPath(cx: CGFloat, top: CGFloat, r: CGFloat, tipY: CGFloat) -> CGPath {
    // Classic teardrop: round head, straight sides tangent to the head, softly rounded tip.
    let c = CGPoint(x: cx, y: top + r)
    let d = tipY - c.y
    let alpha = acos(r / d)                       // angle from straight-down to the tangent point
    let left = CGPoint(x: c.x - r * sin(alpha), y: c.y + r * cos(alpha))
    let right = CGPoint(x: c.x + r * sin(alpha), y: c.y + r * cos(alpha))
    let p = CGMutablePath()
    let tipRound: CGFloat = 0.10
    let nearTipL = CGPoint(x: cx + (left.x - cx) * tipRound, y: tipY + (left.y - tipY) * tipRound)
    let nearTipR = CGPoint(x: cx + (right.x - cx) * tipRound, y: tipY + (right.y - tipY) * tipRound)
    p.move(to: nearTipL)
    p.addLine(to: left)
    // Angles in CG's math sense (our space is y-down but drawn through a flip, so go the long way over the top).
    let startA = atan2(left.y - c.y, left.x - c.x)
    let endA = atan2(right.y - c.y, right.x - c.x)
    p.addArc(center: c, radius: r, startAngle: startA, endAngle: endA, clockwise: false)
    p.addLine(to: nearTipR)
    p.addQuadCurve(to: nearTipL, control: CGPoint(x: cx, y: tipY + 6))
    p.closeSubpath()
    return p
}

func render(_ v: Variant, to path: String) {
    let S: CGFloat = 1024
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // y-down coordinates
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

    // Background
    let bg: [CGColor]
    switch v {
    case .light: bg = [color(0x19C3B1), color(0x0E8C8A), color(0x0A5E6B)]
    case .dark: bg = [color(0x12302F), color(0x0B1E22), color(0x070F12)]
    case .tinted: bg = [color(0x000000), color(0x000000)]
    }
    let g = CGGradient(colorsSpace: cs, colors: bg as CFArray, locations: bg.count == 3 ? [0, 0.55, 1] : [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: S * 0.2, y: 0), end: CGPoint(x: S * 0.8, y: S), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    if v == .light {
        // Soft warm glow top-right, like late-afternoon light.
        let glow = CGGradient(colorsSpace: cs, colors: [color(0xFFD27A, 0.35), color(0xFFD27A, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.82, y: S * 0.12), startRadius: 0,
                               endCenter: CGPoint(x: S * 0.82, y: S * 0.12), endRadius: S * 0.6, options: [])
    }

    let cx = S / 2, r: CGFloat = 268, top: CGFloat = 150, tip: CGFloat = 878
    let pin = pinPath(cx: cx, top: top, r: r, tipY: tip)

    // Ground shadow
    if v != .tinted {
        ctx.saveGState()
        ctx.setFillColor(color(0x000000, v == .dark ? 0.35 : 0.18))
        ctx.fillEllipse(in: CGRect(x: cx - 120, y: tip - 14, width: 240, height: 40))
        ctx.restoreGState()
    }

    // Pin body with soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: color(0x00262B, v == .tinted ? 0 : 0.35))
    ctx.addPath(pin)
    ctx.setFillColor(v == .tinted ? color(0xF2F2F2) : color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Subtle vertical shading on the pin
    if v != .tinted {
        ctx.saveGState()
        ctx.addPath(pin); ctx.clip()
        let shade = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0), color(0xD9EEEC, v == .dark ? 0.25 : 0.55)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(shade, start: CGPoint(x: cx, y: top), end: CGPoint(x: cx, y: tip), options: [])
        ctx.restoreGState()
    }

    // Window: sunset disc with a temple (chedi) silhouette and a wave
    let wr: CGFloat = 172
    let wc = CGPoint(x: cx, y: top + r)
    let window = CGPath(ellipseIn: CGRect(x: wc.x - wr, y: wc.y - wr, width: wr * 2, height: wr * 2), transform: nil)
    ctx.saveGState()
    ctx.addPath(window); ctx.clip()
    let sky: [CGColor] = v == .tinted ? [color(0x9A9A9A), color(0x6E6E6E)] : [color(0xFFC94D), color(0xF4821C), color(0xE8505B)]
    let skyG = CGGradient(colorsSpace: cs, colors: sky as CFArray, locations: sky.count == 3 ? [0, 0.6, 1] : [0, 1])!
    ctx.drawLinearGradient(skyG, start: CGPoint(x: wc.x, y: wc.y - wr), end: CGPoint(x: wc.x, y: wc.y + wr), options: [])
    // Sun
    ctx.setFillColor(v == .tinted ? color(0xD8D8D8) : color(0xFFF1C9))
    ctx.fillEllipse(in: CGRect(x: wc.x - 104, y: wc.y - 70, width: 208, height: 208))
    // Chedi silhouette
    let ink = v == .tinted ? color(0x3A3A3A) : (v == .dark ? color(0x0B1E22) : color(0x0A5E6B))
    ctx.setFillColor(ink)
    let base = wc.y + 70
    let chedi = CGMutablePath()
    chedi.move(to: CGPoint(x: wc.x, y: wc.y - 118))              // spire tip
    chedi.addLine(to: CGPoint(x: wc.x + 9, y: wc.y - 40))
    chedi.addLine(to: CGPoint(x: wc.x + 16, y: wc.y - 40))
    chedi.addQuadCurve(to: CGPoint(x: wc.x + 54, y: wc.y + 22), control: CGPoint(x: wc.x + 50, y: wc.y - 20)) // bell
    chedi.addLine(to: CGPoint(x: wc.x + 72, y: wc.y + 22))
    chedi.addLine(to: CGPoint(x: wc.x + 72, y: wc.y + 44))
    chedi.addLine(to: CGPoint(x: wc.x + 96, y: wc.y + 44))
    chedi.addLine(to: CGPoint(x: wc.x + 96, y: base))
    chedi.addLine(to: CGPoint(x: wc.x - 96, y: base))
    chedi.addLine(to: CGPoint(x: wc.x - 96, y: wc.y + 44))
    chedi.addLine(to: CGPoint(x: wc.x - 72, y: wc.y + 44))
    chedi.addLine(to: CGPoint(x: wc.x - 72, y: wc.y + 22))
    chedi.addLine(to: CGPoint(x: wc.x - 54, y: wc.y + 22))
    chedi.addQuadCurve(to: CGPoint(x: wc.x - 16, y: wc.y - 40), control: CGPoint(x: wc.x - 50, y: wc.y - 20))
    chedi.addLine(to: CGPoint(x: wc.x - 9, y: wc.y - 40))
    chedi.closeSubpath()
    ctx.addPath(chedi); ctx.fillPath()
    // Water
    let water = CGMutablePath()
    water.move(to: CGPoint(x: wc.x - wr, y: base - 6))
    water.addCurve(to: CGPoint(x: wc.x + wr, y: base - 2), control1: CGPoint(x: wc.x - 60, y: base - 34), control2: CGPoint(x: wc.x + 60, y: base + 26))
    water.addLine(to: CGPoint(x: wc.x + wr, y: wc.y + wr))
    water.addLine(to: CGPoint(x: wc.x - wr, y: wc.y + wr))
    water.closeSubpath()
    ctx.setFillColor(v == .tinted ? color(0x5A5A5A) : (v == .dark ? color(0x14A394) : color(0x19C3B1)))
    ctx.addPath(water); ctx.fillPath()
    ctx.restoreGState()

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    // App Store icon must be opaque: drop alpha for the light icon.
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

render(.light, to: "AppIcon.png")
render(.dark, to: "AppIcon-Dark.png")
render(.tinted, to: "AppIcon-Tinted.png")
print("done")
