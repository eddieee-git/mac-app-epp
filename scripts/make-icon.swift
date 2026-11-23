// Epp 앱 아이콘을 그려 Resources/AppIcon.icns와 docs/images/icon.png를 만든다.
// 실행: swift scripts/make-icon.swift
// 모양: 둥근 사각형 위에 작은 타일 네 개(기능 모음). 메뉴바 아이콘(square.grid.2x2)과 맞춘다.
import AppKit

func draw(in size: CGFloat) {
    let scale = size / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)

    // 배경: macOS 아이콘 격자에 맞춘 둥근 사각형
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.22, blue: 0.30, alpha: 1),
               ending: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.14, alpha: 1))!.draw(in: tile, angle: -90)

    let shadow = NSColor.black.withAlphaComponent(0.35).cgColor
    // 기능 타일 네 개: 색마다 다른 기능
    let colors = [
        NSColor(srgbRed: 0.16, green: 0.78, blue: 0.70, alpha: 1), // 왼쪽 위
        NSColor(srgbRed: 0.98, green: 0.73, blue: 0.20, alpha: 1), // 오른쪽 위
        NSColor(srgbRed: 0.35, green: 0.55, blue: 0.98, alpha: 1), // 왼쪽 아래
        NSColor(srgbRed: 0.96, green: 0.40, blue: 0.45, alpha: 1), // 오른쪽 아래
    ]
    let side: CGFloat = 270, gap: CGFloat = 54
    let origin = (1024 - side * 2 - gap) / 2
    for (index, color) in colors.enumerated() {
        let col = CGFloat(index % 2), row = CGFloat(1 - index / 2)
        let rect = NSRect(x: origin + col * (side + gap), y: origin + row * (side + gap), width: side, height: side)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 34 * scale, color: shadow)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 72, yRadius: 72).fill()
        context.restoreGState()
    }
}

func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(in: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("EppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()

// README 머리에 쓰는 아이콘
try FileManager.default.createDirectory(atPath: "docs/images", withIntermediateDirectories: true)
try png(256).write(to: URL(fileURLWithPath: "docs/images/icon.png"))
