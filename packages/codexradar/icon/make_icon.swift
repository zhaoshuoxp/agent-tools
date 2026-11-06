// 生成 AppIcon.icns：swift icon/make_icon.swift <输出目录>
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let rgb = CGColorSpaceCreateDeviceRGB()

    // macOS 图标网格：824/1024 的圆角方形
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0.1, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let bg = CGGradient(colorsSpace: rgb, colors: [
        CGColor(red: 0.07, green: 0.11, blue: 0.18, alpha: 1),
        CGColor(red: 0.11, green: 0.20, blue: 0.29, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])

    let c = CGPoint(x: s / 2, y: s / 2)
    let R = body.width * 0.36
    let teal = CGColor(red: 0.42, green: 0.80, blue: 0.74, alpha: 1)

    // 扫描扇区（渐变尾迹）
    let sweepEnd = CGFloat.pi * 0.30
    let steps = 60
    for i in 0..<steps {
        let a0 = sweepEnd + CGFloat(i) * 0.022
        let a1 = a0 + 0.024
        ctx.move(to: c)
        ctx.addArc(center: c, radius: R, startAngle: a0, endAngle: a1, clockwise: false)
        ctx.closePath()
        ctx.setFillColor(teal.copy(alpha: 0.32 * (1 - CGFloat(i) / CGFloat(steps)))!)
        ctx.fillPath()
    }

    // 同心环 + 十字
    ctx.setStrokeColor(CGColor(red: 0.62, green: 0.78, blue: 0.86, alpha: 0.35))
    ctx.setLineWidth(s * 0.008)
    for f in [0.33, 0.66, 1.0] {
        ctx.addEllipse(in: CGRect(x: c.x - R * f, y: c.y - R * f, width: 2 * R * f, height: 2 * R * f))
    }
    ctx.strokePath()
    ctx.setStrokeColor(CGColor(red: 0.62, green: 0.78, blue: 0.86, alpha: 0.18))
    ctx.move(to: CGPoint(x: c.x - R, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + R, y: c.y))
    ctx.move(to: CGPoint(x: c.x, y: c.y - R)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + R))
    ctx.strokePath()

    // 扫描线
    ctx.setStrokeColor(teal)
    ctx.setLineWidth(s * 0.016)
    ctx.setLineCap(.round)
    ctx.move(to: c)
    ctx.addLine(to: CGPoint(x: c.x + R * cos(sweepEnd), y: c.y + R * sin(sweepEnd)))
    ctx.strokePath()

    // 目标点：四个分项配色
    let blips: [(CGFloat, CGFloat, CGColor)] = [
        (0.40, 0.72, CGColor(red: 0.56, green: 0.69, blue: 0.87, alpha: 1)),
        (1.35, 0.52, CGColor(red: 0.71, green: 0.63, blue: 0.85, alpha: 1)),
        (2.55, 0.80, CGColor(red: 0.50, green: 0.76, blue: 0.73, alpha: 1)),
        (4.20, 0.45, CGColor(red: 0.85, green: 0.67, blue: 0.47, alpha: 1)),
    ]
    for (a, r, col) in blips {
        let p = CGPoint(x: c.x + R * r * cos(a), y: c.y + R * r * sin(a))
        let d = s * 0.052
        ctx.setFillColor(col.copy(alpha: 0.25)!)
        ctx.fillEllipse(in: CGRect(x: p.x - d, y: p.y - d, width: 2 * d, height: 2 * d))
        ctx.setFillColor(col)
        ctx.fillEllipse(in: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
    }
    ctx.setFillColor(teal)
    ctx.fillEllipse(in: CGRect(x: c.x - s * 0.018, y: c.y - s * 0.018, width: s * 0.036, height: s * 0.036))

    // 顶部高光
    let gloss = CGGradient(colorsSpace: rgb, colors: [CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
    ctx.restoreGState()

    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12)); ctx.setLineWidth(s * 0.004); ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let set = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: out.appendingPathComponent("AppIcon-1024.png"))
