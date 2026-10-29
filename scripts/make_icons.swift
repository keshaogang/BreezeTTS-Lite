// swiftc -O make_icons.swift -o make_icons
// 生成符合 macOS 规范几何的浅色 / 深色应用图标。
// 画布 1024，内容圆角矩形 824（四边留 100 透明边距，圆角 185），
// 这样在 Dock / 启动台里与系统图标视觉尺寸一致。
//
// 用法: make_icons <浅色源 1024.png> <输出浅色.png> <输出深色.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvasSize = 1024
let contentSize: CGFloat = 824
let margin = (CGFloat(canvasSize) - contentSize) / 2
let radius: CGFloat = 185
let contentRect = CGRect(x: margin, y: margin, width: contentSize, height: contentSize)

func loadCG(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func savePNG(_ image: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

/// 圆角矩形路径（贝塞尔近似连续曲率）。
func roundedPath(_ rect: CGRect, _ r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
    let k: CGFloat = 0.5523
    p.move(to: CGPoint(x: x0 + r, y: y0))
    p.addLine(to: CGPoint(x: x1 - r, y: y0))
    p.addCurve(to: CGPoint(x: x1, y: y0 + r),
               control1: CGPoint(x: x1 - r + r * k, y: y0),
               control2: CGPoint(x: x1, y: y0 + r - r * k))
    p.addLine(to: CGPoint(x: x1, y: y1 - r))
    p.addCurve(to: CGPoint(x: x1 - r, y: y1),
               control1: CGPoint(x: x1, y: y1 - r + r * k),
               control2: CGPoint(x: x1 - r + r * k, y: y1))
    p.addLine(to: CGPoint(x: x0 + r, y: y1))
    p.addCurve(to: CGPoint(x: x0, y: y1 - r),
               control1: CGPoint(x: x0 + r - r * k, y: y1),
               control2: CGPoint(x: x0, y: y1 - r + r * k))
    p.addLine(to: CGPoint(x: x0, y: y0 + r))
    p.addCurve(to: CGPoint(x: x0 + r, y: y0),
               control1: CGPoint(x: x0, y: y0 + r - r * k),
               control2: CGPoint(x: x0 + r - r * k, y: y0))
    p.closeSubpath()
    return p
}

let srcPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_light.png"
let outLight = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light.png"
let outDark = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "dark.png"

guard let src = loadCG(srcPath) else { fatalError("cannot load \(srcPath)") }

// MARK: - 浅色版

func lightIcon() -> CGImage {
    let ctx = makeContext(canvasSize, canvasSize)
    ctx.saveGState()
    ctx.addPath(roundedPath(contentRect, radius))
    ctx.clip()
    ctx.draw(src, in: contentRect)
    // 顶部一层很淡的高光，让平面色块有点玻璃感
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.16),
                                   CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(glow,
                           start: CGPoint(x: 0, y: contentRect.maxY),
                           end: CGPoint(x: 0, y: contentRect.midY),
                           options: [])
    ctx.restoreGState()
    // 细内描边，避免浅色背景糊在浅色 Dock 上
    ctx.saveGState()
    ctx.addPath(roundedPath(contentRect.insetBy(dx: 1.5, dy: 1.5), radius - 1.5))
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.06))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()
    return ctx.makeImage()!
}

// MARK: - 深色版（复用浅色版的白色字形）

/// 在内容区尺寸下渲染浅色图，取出白色字形作为 alpha 蒙版。
func glyphImage() -> CGImage {
    let n = Int(contentSize)
    let ctx = makeContext(n, n)
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: n, height: n))
    let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var rgba = [UInt8](repeating: 0, count: n * n * 4)
    for i in 0..<(n * n) {
        let r = buf[i * 4], g = buf[i * 4 + 1], b = buf[i * 4 + 2], a = buf[i * 4 + 3]
        let whiteness = min(r, min(g, b))
        let m = max(0.0, min(1.0, (Float(whiteness) - 228) / 27)) * (Float(a) / 255)
        rgba[i * 4] = 255
        rgba[i * 4 + 1] = 255
        rgba[i * 4 + 2] = 255
        rgba[i * 4 + 3] = UInt8(m * 255)
    }
    let provider = CGDataProvider(data: Data(rgba) as CFData)!
    return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

func darkIcon(_ glyph: CGImage) -> CGImage {
    let ctx = makeContext(canvasSize, canvasSize)
    ctx.saveGState()
    ctx.addPath(roundedPath(contentRect, radius))
    ctx.clip()
    // 底：深空蓝黑渐变
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.13, green: 0.14, blue: 0.20, alpha: 1),
                                   CGColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: contentRect.minX, y: contentRect.maxY),
                           end: CGPoint(x: contentRect.maxX, y: contentRect.minY),
                           options: [])
    // 右下角品牌紫光晕
    let purple = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: [CGColor(red: 0.45, green: 0.40, blue: 0.92, alpha: 0.28),
                                     CGColor(red: 0.45, green: 0.40, blue: 0.92, alpha: 0)] as CFArray,
                            locations: [0, 1])!
    let pc = CGPoint(x: contentRect.maxX - 60, y: contentRect.minY + 60)
    ctx.drawRadialGradient(purple, startCenter: pc, startRadius: 0, endCenter: pc, endRadius: 620, options: [])
    // 顶部淡淡反光
    let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.06),
                                    CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gloss,
                           start: CGPoint(x: 0, y: contentRect.maxY),
                           end: CGPoint(x: 0, y: contentRect.maxY - 300),
                           options: [])
    // 白色字形 + 外发光
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: CGColor(red: 0.55, green: 0.62, blue: 1, alpha: 0.35))
    ctx.draw(glyph, in: contentRect)
    ctx.restoreGState()
    ctx.draw(glyph, in: contentRect)
    ctx.restoreGState()
    // 内描边：深色图标在深色 Dock 上靠这条线分界
    ctx.saveGState()
    ctx.addPath(roundedPath(contentRect.insetBy(dx: 1.5, dy: 1.5), radius - 1.5))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()
    return ctx.makeImage()!
}

savePNG(lightIcon(), outLight)
print("light -> \(outLight)  (content \(Int(contentSize)) in \(canvasSize), r=\(Int(radius)))")

savePNG(darkIcon(glyphImage()), outDark)
print("dark  -> \(outDark)")
