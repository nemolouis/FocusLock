// 生成 App 图标 iconset：番茄做锁身的挂锁（锁梁 + 番茄 + 叶蒂 + 锁孔），整体居中
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(px)
    let c = s / 2

    // ── 背景：macOS 图标网格（824/1024），暖白渐变圆角方块
    let inset = s * 0.0977
    let bgRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: bgRect.width * 0.225, yRadius: bgRect.width * 0.225)
    NSGraphicsContext.saveGraphicsState()
    let outer = NSShadow()
    outer.shadowColor = rgb(0x000000, 0.18)
    outer.shadowBlurRadius = s * 0.012
    outer.shadowOffset = NSSize(width: 0, height: -s * 0.006)
    outer.set()
    rgb(0xFFF4E8).setFill()
    bg.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: rgb(0xFFF8EF), ending: rgb(0xFFE2CC))!.draw(in: bg, angle: -90)

    // ── 几何：番茄 + 锁梁作为一个整体，在画布上几何居中
    let tw = s * 0.54, th = s * 0.45          // 番茄宽高
    let r = s * 0.112                         // 锁梁中线半径
    let lw = s * 0.068                        // 锁梁粗细
    let shackleRise = s * 0.055               // 锁梁圆心高出番茄顶部的距离
    let groupH = th + shackleRise + r + lw / 2
    let tomatoBottom = c - groupH / 2
    let tomatoTop = tomatoBottom + th
    let tomatoRect = NSRect(x: c - tw / 2, y: tomatoBottom, width: tw, height: th)
    let arcCY = tomatoTop + shackleRise

    // ── 锁梁（画在番茄后面，腿伸进番茄里）
    let shackle = NSBezierPath()
    shackle.move(to: NSPoint(x: c - r, y: tomatoTop - th * 0.3))
    shackle.line(to: NSPoint(x: c - r, y: arcCY))
    shackle.appendArc(withCenter: NSPoint(x: c, y: arcCY), radius: r, startAngle: 180, endAngle: 0, clockwise: true)
    shackle.line(to: NSPoint(x: c + r, y: tomatoTop - th * 0.3))
    shackle.lineWidth = lw
    shackle.lineCapStyle = .round
    shackle.lineJoinStyle = .round
    rgb(0x7D8894).setStroke()
    shackle.stroke()
    // 锁梁高光
    let shine = NSBezierPath()
    shine.appendArc(withCenter: NSPoint(x: c, y: arcCY), radius: r + lw * 0.18, startAngle: 160, endAngle: 95, clockwise: true)
    shine.lineWidth = lw * 0.22
    shine.lineCapStyle = .round
    rgb(0xFFFFFF, 0.55).setStroke()
    shine.stroke()

    // ── 番茄（锁身）：略带棱的椭圆 + 径向渐变 + 投影
    let body = NSBezierPath(ovalIn: tomatoRect)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = rgb(0x8A1A12, 0.35)
    sh.shadowBlurRadius = s * 0.03
    sh.shadowOffset = NSSize(width: 0, height: -s * 0.015)
    sh.set()
    rgb(0xE5382E).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0xFF7A5C), rgb(0xF04434), rgb(0xC9241F)])!
        .draw(in: body, relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))

    // 番茄的纵向棱线，增加立体感
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    for dx in [-0.22, 0.22] as [CGFloat] {
        let ridge = NSBezierPath()
        ridge.move(to: NSPoint(x: c + tw * dx * 0.5, y: tomatoTop - th * 0.08))
        ridge.curve(to: NSPoint(x: c + tw * dx * 0.5, y: tomatoBottom + th * 0.08),
                    controlPoint1: NSPoint(x: c + tw * dx * 1.25, y: tomatoTop - th * 0.3),
                    controlPoint2: NSPoint(x: c + tw * dx * 1.25, y: tomatoBottom + th * 0.3))
        ridge.lineWidth = s * 0.012
        rgb(0x9E1A16, 0.18).setStroke()
        ridge.stroke()
    }
    // 高光
    let hl = NSBezierPath(ovalIn: NSRect(x: -tw * 0.11, y: -th * 0.06, width: tw * 0.22, height: th * 0.12))
    var t = AffineTransform(translationByX: c - tw * 0.26, byY: tomatoTop - th * 0.24)
    t.rotate(byDegrees: 35)
    hl.transform(using: t)
    rgb(0xFFFFFF, 0.42).setFill()
    hl.fill()
    NSGraphicsContext.restoreGraphicsState()

    // ── 叶蒂：5 片叶子透视压扁 + 小茎
    let calyxCenter = NSPoint(x: c, y: tomatoTop - th * 0.04)
    let leaves = NSBezierPath()
    let leafL = s * 0.115, leafW = s * 0.05
    for i in 0..<5 {
        let leaf = NSBezierPath()
        leaf.move(to: .zero)
        leaf.curve(to: NSPoint(x: leafL, y: 0),
                   controlPoint1: NSPoint(x: leafL * 0.3, y: leafW),
                   controlPoint2: NSPoint(x: leafL * 0.75, y: leafW * 0.5))
        leaf.curve(to: .zero,
                   controlPoint1: NSPoint(x: leafL * 0.75, y: -leafW * 0.5),
                   controlPoint2: NSPoint(x: leafL * 0.3, y: -leafW))
        var lt = AffineTransform(rotationByDegrees: -90 + CGFloat(i) * 72)
        leaf.transform(using: lt)
        lt = AffineTransform(scaleByX: 1, byY: 0.5)
        leaf.transform(using: lt)
        leaves.append(leaf)
    }
    leaves.transform(using: AffineTransform(translationByX: calyxCenter.x, byY: calyxCenter.y))
    NSGraphicsContext.saveGraphicsState()
    let ls = NSShadow()
    ls.shadowColor = rgb(0x5A1410, 0.3)
    ls.shadowBlurRadius = s * 0.008
    ls.shadowOffset = NSSize(width: 0, height: -s * 0.004)
    ls.set()
    rgb(0x2E9E4A).setFill()
    leaves.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: rgb(0x52C46A), ending: rgb(0x23863C))!.draw(in: leaves, angle: -90)

    let stem = NSBezierPath(roundedRect: NSRect(x: calyxCenter.x - s * 0.014, y: calyxCenter.y,
                                                width: s * 0.028, height: s * 0.05),
                            xRadius: s * 0.014, yRadius: s * 0.014)
    rgb(0x23863C).setFill()
    stem.fill()

    // ── 锁孔（番茄中心略偏下）
    let kc = NSPoint(x: c, y: tomatoBottom + th * 0.44)
    let kr = s * 0.042
    let keyhole = NSBezierPath(ovalIn: NSRect(x: kc.x - kr, y: kc.y - kr, width: kr * 2, height: kr * 2))
    let slot = NSBezierPath()
    slot.move(to: NSPoint(x: kc.x - kr * 0.38, y: kc.y))
    slot.line(to: NSPoint(x: kc.x - kr * 0.62, y: kc.y - kr * 2.3))
    slot.line(to: NSPoint(x: kc.x + kr * 0.62, y: kc.y - kr * 2.3))
    slot.line(to: NSPoint(x: kc.x + kr * 0.38, y: kc.y))
    slot.close()
    keyhole.append(slot)
    rgb(0xFFF4E8, 0.95).setFill()
    keyhole.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
    }
}
print("icons written to \(outDir)")
