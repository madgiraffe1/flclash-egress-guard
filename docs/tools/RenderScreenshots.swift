// Renders the README screenshots from the app's real SwiftUI views.
//
// render-screenshots.sh appends this file to a copy of app/main.swift with its
// final launch lines removed, so the views below are the shipping GuardPanel and
// MenuPanel. Nothing here starts guard-guide, the system helper, pfctl or any
// network request: each scene only assigns sample values to the view model and
// draws offscreen. Sample data contains no real addresses or user names.

struct Palette: Decodable {
    let annotation: String
    let ink: String

    static func color(_ hex: String) -> NSColor {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                       blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}

/// Window that draws as the active window (coloured traffic lights) without
/// activating this process or taking focus from the user's apps.
final class ActiveLookingWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

enum Target { case refresh, primary, secondary, boot, recover, authLink, logLink }

@MainActor
final class ScreenshotRenderer {
    let out: URL
    let annotation: NSColor
    let scale: CGFloat = 2
    // A fixed, obviously illustrative time: 09:41.
    let sampleTime: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 17; c.hour = 9; c.minute = 41; c.second = 0
        return Calendar.current.date(from: c)!
    }()

    init(out: URL, palette: Palette) {
        self.out = out
        annotation = Palette.color(palette.annotation)
    }

    func bitmap(size: NSSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                   pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        return rep
    }

    func write(_ rep: NSBitmapImageRep, _ name: String) {
        let url = out.appendingPathComponent(name)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        print("wrote \(name) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
    }

    // MARK: Sample states

    func model(_ configure: (Controls) -> Void) -> Controls {
        let m = Controls()
        configure(m)
        return m
    }

    func snapshot(boot: String, mode: String) -> Snapshot {
        Snapshot(boot: boot, login: boot == "on", mode: mode, core: mode == "dedicated" ? 4242 : 0,
                 identity: mode == "dedicated" ? "4242/1" : "0/0")
    }

    func connected(boot: String) -> Controls {
        model { m in
            m.approved = true
            m.snapshot = snapshot(boot: boot, mode: "dedicated")
            m.confirmed = Confirmation(state: .connected, time: sampleTime, snapshot: m.snapshot,
                                       detail: "防火墙已确认专用核心、监视器和虚拟网卡（utun4）。")
            m.message = "日常保护已开启，Google 和抖音均可访问。"
        }
    }

    // MARK: Window capture

    /// Builds the panel window exactly like AppDelegate does and captures the
    /// whole frame view, so the title bar is drawn by AppKit itself.
    func capturePanel(_ model: Controls) -> (NSBitmapImageRep, NSSize, [Target: NSRect]) {
        let host = NSHostingController(rootView: GuardPanel(model: model).environment(\.controlActiveState, .key))
        let window = ActiveLookingWindow(contentViewController: host)
        window.title = "FlClash 出网保护"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.appearance = NSAppearance(named: .aqua)
        window.contentMinSize = NSSize(width: 540, height: 450)
        window.setContentSize(NSSize(width: 540, height: max(450, host.view.fittingSize.height)))
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let frameView = window.contentView!.superview!
        let size = frameView.bounds.size
        let rep = bitmap(size: size)
        frameView.cacheDisplay(in: frameView.bounds, to: rep)

        // Bordered buttons expose a focus-ring view and link buttons an AppKit
        // button; both carry the real on-screen frame. Order them top to bottom.
        var rings: [NSRect] = [], links: [NSRect] = []
        func walk(_ v: NSView) {
            let kind = String(describing: type(of: v))
            if kind == "_FocusRingView" { rings.append(frameView.convert(v.bounds, from: v)) }
            if kind == "SwiftUIAppKitButton" { links.append(frameView.convert(v.bounds, from: v)) }
            v.subviews.forEach(walk)
        }
        walk(host.view)
        let order: (NSRect, NSRect) -> Bool = { $0.maxY != $1.maxY ? $0.maxY > $1.maxY : $0.minX < $1.minX }
        rings.sort(by: order); links.sort(by: order)
        var targets: [Target: NSRect] = [:]
        if rings.count >= 4 {
            targets[.refresh] = rings[0]
            targets[.primary] = rings[1]
            if rings.count >= 5 { targets[.secondary] = rings[2] }
            targets[.boot] = rings[rings.count - 2]
            targets[.recover] = rings[rings.count - 1]
        }
        if links.count >= 2 { targets[.authLink] = links[0]; targets[.logLink] = links[links.count - 1] }
        window.close()
        return (rep, size, targets)
    }

    func captureMenu(_ model: Controls) -> (NSBitmapImageRep, NSSize) {
        let host = NSHostingView(rootView: MenuPanel(model: model, refresh: {}, openPanel: {}, quit: {})
            .environment(\.controlActiveState, .key))
        let size = host.fittingSize
        let window = ActiveLookingWindow(contentRect: NSRect(origin: NSPoint(x: -30000, y: -30000), size: size),
                                         styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = bitmap(size: size)
        host.cacheDisplay(in: host.bounds, to: rep)
        window.close()
        return (rep, size)
    }

    // MARK: Composition

    /// Rounded window with a soft shadow on a transparent canvas, plus
    /// optional numbered highlight rings around real control frames.
    func compose(_ rep: NSBitmapImageRep, size: NSSize, radius: CGFloat,
                 highlights: [(NSRect, Int?)] = [], pad: CGFloat = 30) -> NSBitmapImageRep {
        let canvas = NSSize(width: size.width + pad * 2, height: size.height + pad * 2)
        let outRep = bitmap(size: canvas)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outRep)
        let frame = NSRect(x: pad, y: pad, width: size.width, height: size.height)
        let shape = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.shadowBlurRadius = 20
        shadow.shadowOffset = NSSize(width: 0, height: -7)
        shadow.set()
        NSColor.white.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        rep.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        border.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.16).setStroke()
        border.stroke()

        for (rect, number) in highlights {
            let ring = rect.offsetBy(dx: pad, dy: pad).insetBy(dx: -5, dy: -5)
            let r = min(ring.height / 2, 11)
            let path = NSBezierPath(roundedRect: ring, xRadius: r, yRadius: r)
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = annotation.withAlphaComponent(0.55)
            glow.shadowBlurRadius = 9
            glow.shadowOffset = .zero
            glow.set()
            path.lineWidth = 2.75
            annotation.setStroke()
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
            if let number {
                // Numbered badge just left of the ring, so it never covers the label.
                let d: CGFloat = 22
                let badge = NSRect(x: ring.minX - d - 7, y: ring.midY - d / 2, width: d, height: d)
                let circle = NSBezierPath(ovalIn: badge)
                NSColor.white.setFill(); NSBezierPath(ovalIn: badge.insetBy(dx: -2, dy: -2)).fill()
                annotation.setFill(); circle.fill()
                let text = NSAttributedString(string: "\(number)", attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.white])
                let t = text.size()
                text.draw(at: NSPoint(x: badge.midX - t.width / 2, y: badge.midY - t.height / 2))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return outRep
    }

    func panel(_ name: String, _ model: Controls, highlight: [(Target, Int?)] = []) {
        let (rep, size, targets) = capturePanel(model)
        let marks = highlight.compactMap { item -> (NSRect, Int?)? in
            guard let rect = targets[item.0] else { print("warning: \(name): target \(item.0) not found"); return nil }
            return (rect, item.1)
        }
        write(compose(rep, size: size, radius: 12, highlights: marks), name)
    }

    func menuIcons() {
        let states = [("connected", "checkmark.shield.fill"), ("locked", "lock.shield.fill"),
                      ("off", "xmark.shield"), ("unknown", "exclamationmark.shield")]
        for (name, symbol) in states {
            let chip = NSSize(width: 44, height: 30)
            let rep = bitmap(size: chip)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let shape = NSBezierPath(roundedRect: NSRect(origin: .zero, size: chip).insetBy(dx: 0.5, dy: 0.5),
                                     xRadius: 8, yRadius: 8)
            NSColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1).setFill(); shape.fill()
            NSColor.black.withAlphaComponent(0.12).setStroke(); shape.lineWidth = 1; shape.stroke()
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
            let s = image.size
            let tinted = NSImage(size: s, flipped: false) { rect in
                image.draw(in: rect)
                NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: (chip.width - s.width) / 2, y: (chip.height - s.height) / 2, width: s.width, height: s.height))
            NSGraphicsContext.restoreGraphicsState()
            write(rep, "menubar-\(name).png")
        }
    }

    func run() {
        // 1. First launch: not yet authorised, FlClash running the ordinary way.
        let firstRun = model { m in
            m.approved = false
            m.snapshot = snapshot(boot: "off", mode: "ordinary")
        }
        panel("ui-first-run.png", firstRun, highlight: [(.authLink, 1), (.primary, 2)])

        // 2. Daily protection, step 2 waiting for the user to quit FlClash once.
        let waiting = model { m in
            m.approved = true
            m.snapshot = snapshot(boot: "off", mode: "ordinary")
            m.busy = true
            m.message = "日常保护 · 切换前锁住公网 通过"
            m.progress = DailyProgress(step: 2, detail: "请点菜单栏的 FlClash 图标，选「退出」。图标消失后回到这里点「继续」。公网已锁住。",
                                       phase: .waiting)
        }
        panel("ui-step-waiting.png", waiting, highlight: [(.primary, nil)])

        // 3. Daily protection on.
        panel("ui-connected.png", connected(boot: "off"))
        // 4. Optional boot protection.
        panel("ui-boot.png", connected(boot: "off"), highlight: [(.boot, nil)])

        // 5. FlClash quit: public internet locked, LAN still fine.
        let locked = model { m in
            m.approved = true
            m.snapshot = snapshot(boot: "on", mode: "closed")
            m.confirmed = Confirmation(state: .locked, time: sampleTime, snapshot: m.snapshot, detail: "")
            m.message = "已读取系统防火墙规则。"
        }
        panel("ui-locked.png", locked, highlight: [(.primary, nil)])

        // 6. Restoring the original network setup.
        panel("ui-restore.png", connected(boot: "on"), highlight: [(.recover, nil)])

        // 7. Menu-bar popover.
        let (menu, menuSize) = captureMenu(connected(boot: "on"))
        write(compose(menu, size: menuSize, radius: 12), "ui-menubar.png")

        menuIcons()
    }
}

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    guard args.count >= 3 else { print("usage: render <out-dir> <palette.json>"); exit(2) }
    NSApplication.shared.setActivationPolicy(.prohibited)
    NSApp.appearance = NSAppearance(named: .aqua)
    let palette = try! JSONDecoder().decode(Palette.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
    ScreenshotRenderer(out: URL(fileURLWithPath: args[1]), palette: palette).run()
}
