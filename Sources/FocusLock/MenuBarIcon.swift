import AppKit

/// 菜单栏图标：单色的「番茄锁」——番茄形锁身（顶部微凹）、镂空的五瓣叶蒂和小茎、锁孔、锁梁。
/// 模板图片，自动适配深浅色菜单栏。未计时显示开锁（锁梁抬起、右腿离开锁身），专注中显示上锁。
/// 可在图标右边带上文字（分钟数）。
enum MenuBarIcon {
    private static let iconSize = NSSize(width: 16, height: 18)

    /// 同样的状态和文字只画一次（菜单栏图标每秒都会被询问，文字一分钟才变一次）
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(locked: Bool, text: String? = nil) -> NSImage {
        let key = "\(locked)|\(text ?? "")"
        if let cached = cache[key] { return cached }
        if cache.count > 200 { cache.removeAll() }
        let image = makeImage(locked: locked, text: text)
        cache[key] = image
        return image
    }

    private static func makeImage(locked: Bool, text: String?) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = text.map { ($0 as NSString).size(withAttributes: attrs) } ?? .zero
        let gap: CGFloat = text == nil ? 0 : 4
        let size = NSSize(width: iconSize.width + gap + ceil(textSize.width), height: iconSize.height)

        let image = NSImage(size: size, flipped: false) { _ in
            drawIcon(in: NSRect(origin: .zero, size: iconSize), locked: locked)
            if let text {
                let y = (size.height - textSize.height) / 2
                (text as NSString).draw(at: NSPoint(x: iconSize.width + gap, y: y), withAttributes: attrs)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = locked ? "FocusLock (locked)" : "FocusLock"
        return image
    }

    /// 坐标原点在左下角，图标 16×18pt
    static func drawIcon(in r: NSRect, locked: Bool) {
        NSColor.black.set()
        let cx = r.midX
        let x0 = r.minX + 1, x1 = r.maxX - 1
        let y0 = r.minY + 1, y1 = r.minY + 10.6
        let mid = (y0 + y1) / 2

        // 锁梁（先画，腿的末端藏进锁身）
        let radius: CGFloat = 3.4
        let lift: CGFloat = locked ? 0 : 1.6
        let arcY = r.minY + 12 + lift
        let legEnd = y1
        let shackle = NSBezierPath()
        shackle.lineWidth = 1.6
        shackle.lineCapStyle = .round
        shackle.move(to: NSPoint(x: cx - radius, y: legEnd))
        shackle.line(to: NSPoint(x: cx - radius, y: arcY))
        shackle.appendArc(withCenter: NSPoint(x: cx, y: arcY), radius: radius, startAngle: 180, endAngle: 0, clockwise: true)
        // 开锁时右腿变短，和锁身之间留出空隙
        shackle.line(to: NSPoint(x: cx + radius, y: locked ? legEnd : arcY - 0.5))
        shackle.stroke()

        // 锁身：番茄轮廓，顶部中间微微凹下去
        let body = NSBezierPath()
        body.move(to: NSPoint(x: cx, y: y0))
        body.curve(to: NSPoint(x: x1, y: mid + 0.3),
                   controlPoint1: NSPoint(x: cx + 5.2, y: y0), controlPoint2: NSPoint(x: x1, y: y0 + 2.2))
        body.curve(to: NSPoint(x: cx, y: y1 - 0.9),
                   controlPoint1: NSPoint(x: x1, y: y1 + 0.3), controlPoint2: NSPoint(x: cx + 3, y: y1 + 0.6))
        body.curve(to: NSPoint(x: x0, y: mid + 0.3),
                   controlPoint1: NSPoint(x: cx - 3, y: y1 + 0.6), controlPoint2: NSPoint(x: x0, y: y1 + 0.3))
        body.curve(to: NSPoint(x: cx, y: y0),
                   controlPoint1: NSPoint(x: x0, y: y0 + 2.2), controlPoint2: NSPoint(x: cx - 5.2, y: y0))
        body.close()

        // 镂空：五片向下垂的叶蒂（像正面看番茄顶部）
        let calyxCenter = NSPoint(x: cx, y: r.minY + 9.3)
        func polar(_ deg: Double, _ rr: CGFloat) -> NSPoint {
            let a = deg * .pi / 180
            return NSPoint(x: calyxCenter.x + rr * CGFloat(cos(a)), y: calyxCenter.y + rr * CGFloat(sin(a)) * 0.75)
        }
        let calyx = NSBezierPath()
        let tips: [Double] = [-12, -50, -90, -130, -168]
        calyx.move(to: polar(tips[0], 3.4))
        for i in 1..<tips.count {
            calyx.line(to: polar((tips[i - 1] + tips[i]) / 2, 1.1))
            calyx.line(to: polar(tips[i], 3.4))
        }
        calyx.line(to: NSPoint(x: cx - 1.1, y: calyxCenter.y + 0.35))
        calyx.line(to: NSPoint(x: cx + 1.1, y: calyxCenter.y + 0.35))
        calyx.close()
        body.append(calyx)

        // 镂空：锁孔
        let kc = NSPoint(x: cx, y: r.minY + 4.4)
        let kr: CGFloat = 1.1
        body.append(NSBezierPath(ovalIn: NSRect(x: kc.x - kr, y: kc.y - kr, width: kr * 2, height: kr * 2)))
        body.append(NSBezierPath(rect: NSRect(x: kc.x - 0.5, y: kc.y - 2.0, width: 1.0, height: 2.0)))

        body.windingRule = .evenOdd
        body.fill()

        // 小茎：从叶蒂中心往上
        NSBezierPath(roundedRect: NSRect(x: cx - 0.55, y: calyxCenter.y - 0.2, width: 1.1, height: 2.6),
                     xRadius: 0.55, yRadius: 0.55).fill()
    }
}
