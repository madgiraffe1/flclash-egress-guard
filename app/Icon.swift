import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 1024, height: 1024)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let tile = NSBezierPath(roundedRect: NSRect(x: 87, y: 87, width: 850, height: 850), xRadius: 194, yRadius: 194)
        NSGradient(starting: NSColor(srgbRed: 0.03, green: 0.20, blue: 0.36, alpha: 1),
                   ending: NSColor(srgbRed: 0.08, green: 0.55, blue: 0.67, alpha: 1))!.draw(in: tile, angle: 48)
        let shield = NSBezierPath()
        shield.move(to: NSPoint(x: 512, y: 780))
        shield.curve(to: NSPoint(x: 727, y: 702), controlPoint1: NSPoint(x: 590, y: 744), controlPoint2: NSPoint(x: 654, y: 718))
        shield.line(to: NSPoint(x: 727, y: 518))
        shield.curve(to: NSPoint(x: 512, y: 244), controlPoint1: NSPoint(x: 727, y: 387), controlPoint2: NSPoint(x: 634, y: 292))
        shield.curve(to: NSPoint(x: 297, y: 518), controlPoint1: NSPoint(x: 390, y: 292), controlPoint2: NSPoint(x: 297, y: 387))
        shield.line(to: NSPoint(x: 297, y: 702))
        shield.curve(to: NSPoint(x: 512, y: 780), controlPoint1: NSPoint(x: 370, y: 718), controlPoint2: NSPoint(x: 434, y: 744))
        shield.close()
        shield.lineJoinStyle = .round; shield.lineWidth = 36
        NSColor.white.setStroke(); shield.stroke()
        let route = NSBezierPath()
        route.move(to: NSPoint(x: 393, y: 522)); route.line(to: NSPoint(x: 478, y: 437)); route.line(to: NSPoint(x: 632, y: 609))
        route.lineWidth = 45; route.lineCapStyle = .round; route.lineJoinStyle = .round
        NSColor(srgbRed: 0.68, green: 0.98, blue: 0.88, alpha: 1).setStroke(); route.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
