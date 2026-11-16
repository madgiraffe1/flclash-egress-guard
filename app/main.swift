import AppKit
import Carbon
import Combine
import SwiftUI

struct Snapshot: Decodable, Equatable {
    let boot: String
    let login: Bool
    let mode: String
    let core: Int
    let identity: String
}

enum DailyState: String {
    case connected = "已开启"
    case locked = "公网已锁住"
    case off = "未开启"
    case unknown = "尚未核对"
}

struct Confirmation {
    let state: DailyState
    let time: Date
    let snapshot: Snapshot?
    let detail: String
}

struct DailyProgress {
    enum Phase { case working, waiting, failed, cancelled }
    static let titles = ["核对状态", "接通 FlClash", "启用规则", "验证联网"]
    var step = 1
    var detail = "正在准备读取防火墙规则。"
    var phase = Phase.working
    var issue: String?
    var heading: String {
        let suffix: String
        switch phase {
        case .working: suffix = Self.titles[step - 1]
        case .waiting: suffix = "需要你操作"
        case .failed: suffix = "未完成"
        case .cancelled: suffix = "已取消"
        }
        return "第 \(step) / 4 步 · " + suffix
    }
}

final class Controls: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var confirmed: Confirmation?
    @Published var busy = false
    @Published var message = ""
    @Published var progress: DailyProgress?
    @Published var approved = GuardService.approved
    weak var window: NSWindow?

    private let resources = Bundle.main.resourceURL!
    private var child: Process?
    private var input: FileHandle?
    private var operation = ""
    private var reading = false
    private var generation = 0
    private var lastVerifiedText: String?
    private lazy var authorization: NSAppleScript? = {
        guard let text = try? String(contentsOf: resources.appendingPathComponent("Authorize.applescript"), encoding: .utf8) else { return nil }
        return NSAppleScript(source: text)
    }()

    var state: DailyState { confirmed?.state ?? .unknown }
    var checking: Bool { busy && operation == "status" }
    var stateTitle: String { state == .unknown && confirmed != nil ? "需要复核" : state.rawValue }
    var dailyAction: String {
        if let p = progress {
            switch p.phase {
            case .failed: return "重试"
            case .cancelled: return "重新开始"
            case .working: return "正在处理…"
            case .waiting: return "继续"
            }
        }
        switch state {
        case .connected: return "日常保护已开启"
        case .locked: return "重新接通 FlClash"
        case .off: return "开启日常保护"
        case .unknown: return "开启日常保护"
        }
    }
    var nextBoot: Bool? {
        switch snapshot?.boot {
        case "on": return true
        case "off": return false
        default: return nil
        }
    }
    var bootLabel: String {
        guard let on = nextBoot else { return "待核对" }
        if !on { return "未开启" }
        return snapshot?.login == true ? "已开启" : "登录启动待补全"
    }
    var coreDetail: String {
        if let check = confirmed, !check.detail.isEmpty { return check.detail }
        guard let s = snapshot else { return "正在读取本机状态…" }
        switch s.mode {
        case "closed": return "FlClash 核心已退出。"
        case "ordinary": return "FlClash 正以普通身份运行。"
        case "dedicated": return "FlClash 核心已用专用身份运行。"
        default: return "核心状态暂时无法读取。"
        }
    }

    private func worker(_ action: String) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-I", "-B", "-u", resources.appendingPathComponent("guard-guide").path, "--app", action]
        p.standardError = FileHandle.nullDevice
        return p
    }

    func refresh() {
        guard !reading, !busy else { return }
        reading = true
        let requestGeneration = generation
        let p = worker("snapshot")
        let pipe = Pipe()
        p.standardOutput = pipe
        DispatchQueue.global(qos: .utility).async {
            var observed: Snapshot?
            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus == 0 { observed = try? JSONDecoder().decode(Snapshot.self, from: data) }
            } catch {}
            let current = observed
            DispatchQueue.main.async {
                self.reading = false
                guard !self.busy, requestGeneration == self.generation else { return }
                self.update(current)
            }
        }
    }

    private func update(_ current: Snapshot?) {
        snapshot = current
        if let check = confirmed, check.snapshot != current { confirmed = nil }
    }

    func invalidateObservation() {
        confirmed = nil
        refresh()
    }

    private func setConfirmed(_ text: String) {
        let enabled = text.contains("系统 pf 已启用")
        let lines = text.split(whereSeparator: \.isNewline)
        let prefix = "保护已装载，核心使用 "
        let healthy = lines.first { $0.hasPrefix(prefix) && $0.hasSuffix("。") }
        let tunnel = healthy.map { String($0.dropFirst(prefix.count).dropLast()) } ?? ""
        let process = lines.first { $0.hasPrefix("FlClashCore ") }?.split(whereSeparator: \.isWhitespace)
        let verifiedPID = process.flatMap { $0.count > 2 ? Int($0[2]) : nil }
        let changed = snapshot.map { $0.mode == "closed" || $0.mode == "ordinary" ||
            ($0.core > 0 && verifiedPID != $0.core) } ?? false
        var detail = ""
        let state: DailyState
        if enabled, tunnel.hasPrefix("utun"), Int(tunnel.dropFirst(4)) != nil, verifiedPID != nil,
           !changed, !text.contains("限时试用剩余") {
            state = .connected
            detail = "防火墙已确认专用核心、监视器和虚拟网卡（" + tunnel + "）。"
        }
        else if enabled && text.contains("公网出口已锁定") { state = .locked }
        else if text.contains("本工具已停用") || text.contains("本工具尚未安装") { state = .off }
        else {
            state = .unknown
            if text.contains("缺少有效阻断") { detail = "系统未读到有效的公网阻断规则。" }
            else if text.contains("限时试用剩余") { detail = "目前是限时试用。点「开启日常保护」可切换为持续保护。" }
            else if text.contains("需要复核") || changed { detail = "核心、虚拟网卡或监视器与保护记录不一致。请打开 FlClash 确认 TUN，再点「开启日常保护」。" }
            else { detail = "系统尚未确认保护已生效。点「开启日常保护」按步骤处理。" }
        }
        confirmed = Confirmation(state: state, time: Date(), snapshot: snapshot, detail: detail)
    }

    func start(_ action: String) {
        guard !busy else { return }
        generation += 1
        operation = action
        busy = true
        progress = action == "daily" ? DailyProgress() : nil
        lastVerifiedText = nil
        message = action == "status" ? "正在读取防火墙规则…" : "正在处理…"
        let p = worker(action)
        let replies = Pipe(), lines = Pipe()
        p.standardInput = replies
        p.standardOutput = lines
        do { try p.run() }
        catch {
            busy = false
            message = "本机控制器未能启动。"
            if progress != nil { progress?.phase = .failed; progress?.detail = message + "请点「重试」。" }
            return
        }
        input = replies.fileHandleForWriting
        child = p
        DispatchQueue.global(qos: .userInitiated).async {
            var pending = Data()
            while true {
                let part = lines.fileHandleForReading.availableData
                if part.isEmpty { break }
                pending.append(part)
                while let newline = pending.firstIndex(of: 10) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    DispatchQueue.main.async { self.line(line) }
                }
            }
            p.waitUntilExit()
            let code = p.terminationStatus
            DispatchQueue.main.async { self.finished(code) }
        }
    }

    private func reply(_ value: [String: Any]) {
        guard var bytes = try? JSONSerialization.data(withJSONObject: value) else { return }
        bytes.append(10)
        try? input?.write(contentsOf: bytes)
    }

    private func line(_ line: String) {
        guard let child = child, child.isRunning || !line.hasPrefix("@ui ") else { return }
        guard line.hasPrefix("@ui ") else {
            if !line.isEmpty { message = line }
            return
        }
        let data = Data(line.dropFirst(4).utf8)
        guard let request = try? JSONDecoder().decode([String: String].self, from: data),
              let value = request["value"] else { reply(["cancelled": true]); return }
        switch request["kind"] {
        case "step":
            if let n = Int(request["number"] ?? ""), (1...DailyProgress.titles.count).contains(n) {
                progress = DailyProgress(step: n, detail: value)
            }
            reply(["ok": true])
        case "issue":
            progress?.issue = value
            reply(["ok": true])
        case "admin": administrator(value)
        case "prompt":
            progress?.phase = .waiting
            progress?.detail = value
            window?.makeKeyAndOrderFront(nil)
        case "report":
            setConfirmed(value)
            reply(["ok": true])
        default:
            reply(["cancelled": true])
        }
    }

    func answerStep(_ proceed: Bool) {
        guard progress?.phase == .waiting else { return }
        progress?.phase = .working
        progress?.detail = proceed ? "已收到，正在继续检查。" : "正在结束本次操作。"
        reply(proceed ? ["ok": true] : ["cancelled": true])
    }

    private func administrator(_ action: String) {
        let allowed: [String: Set<String>] = [
            "status": ["status"], "daily": ["status","preview","lock","start","enable"],
            "boot-on": ["boot-on","status"], "boot-off": ["boot-off","status"], "recover": ["disable","rollback","status"]
        ]
        guard allowed[operation]?.contains(action) == true else {
            reply(["ok": false, "text": "此操作不可用。"]); return
        }
        if action != "status" && action != "preview" { lastVerifiedText = nil; confirmed = nil }
        if !approved {
            if operation == "recover" {
                let (outcome, detail) = systemDialog("egress-guard", action)
                controlResult(action, outcome, detail)
                return
            }
            if operation == "daily" { progress?.detail = "首次使用，请在 macOS 窗口输入管理员密码。授权完成后会继续。" }
            let (outcome, detail) = systemDialog("guard-authorize", "install")
            approved = outcome == "ok" && GuardService.approved
            guard approved else { controlResult(action, outcome == "cancel" ? "cancel" : "error", detail); return }
            if operation == "daily" { progress?.detail = "已授权，正在读取防火墙规则。" }
        }
        let connection = NSXPCConnection(machServiceName: GuardService.name, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: GuardServiceProtocol.self)
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            connection.invalidate()
            DispatchQueue.main.async {
                self.approved = false
                self.controlResult(action, "error", "未能连接系统助手。请点「一次授权」重新登记。")
            }
        } as! GuardServiceProtocol
        proxy.perform(action) { code, details in
            connection.invalidate()
            DispatchQueue.main.async { self.controlResult(action, code == 0 ? "ok" : "error", details) }
        }
    }

    private func systemDialog(_ tool: String, _ action: String) -> (String, String) {
        guard let script = authorization else { return ("error", "系统授权窗口不可用。") }
        window?.displayIfNeeded()
        let args = NSAppleEventDescriptor.list()
        for (i, item) in [resources.appendingPathComponent(tool).path, action, String(getuid())].enumerated() {
            args.insert(NSAppleEventDescriptor(string: item), at: i + 1)
        }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "runcontrol"), forKeyword: AEKeyword(keyASSubroutineName))
        event.setParam(args, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let response = script.executeAppleEvent(event, error: &error)
        let outcome = response.atIndex(1)?.stringValue
        let detail = (response.atIndex(2)?.stringValue ?? "").replacingOccurrences(of: "\r", with: "\n")
        if (error?[NSAppleScript.errorNumber] as? Int) == -128 { return ("cancel", "") }
        return (outcome ?? "error", outcome == nil ? "系统授权未完成。" : detail)
    }

    private func controlResult(_ action: String, _ outcome: String, _ detail: String) {
        if outcome == "cancel" { reply(["cancelled": true]); return }
        if outcome == "ok" && action == "status" { lastVerifiedText = detail; setConfirmed(detail) }
        if outcome == "error" && action != "preview" { progress?.issue = detail; message = detail }
        reply(["ok": outcome == "ok", "text": detail])
    }

    func removeAccess() {
        guard !busy, let window = window else { return }
        let alert = NSAlert()
        alert.messageText = "撤销盾牌的一次授权？"
        alert.informativeText = "当前出网保护继续运行。下次用盾牌管理防火墙时，需要重新授权。"
        alert.addButton(withTitle: "保留授权")
        alert.addButton(withTitle: "撤销授权")
        alert.beginSheetModal(for: window) { answer in
            guard answer == .alertSecondButtonReturn, !self.busy else { return }
            self.busy = true
            let (outcome, detail) = self.systemDialog("guard-authorize", "remove")
            self.busy = false
            self.approved = GuardService.approved
            if outcome == "ok" { self.message = "已撤销一次授权。"; self.confirmed = nil }
            else if outcome != "cancel" { self.message = detail }
        }
    }

    func openStatus() {
        if approved { start("status") } else { refresh() }
    }

    private func finished(_ code: Int32) {
        try? input?.close()
        input = nil
        child = nil
        busy = false
        if code == 2 { message = "操作已中止。可点「刷新状态」查看当前设置。" }
        else if code != 0 && (message.isEmpty || message == "正在处理…") { message = "操作未完成，请刷新状态。"}
        else if operation == "status" && code == 0 { message = "已读取系统防火墙规则。" }
        if var p = progress {
            if code == 0 { progress = nil }
            else {
                p.phase = code == 2 ? .cancelled : .failed
                let next = ["再点「重试」核对防火墙。", "请检查 FlClash 的窗口和虚拟网卡（TUN），再点「重试」。",
                            "请确认 FlClash 已开启虚拟网卡（TUN），再点「重试」。", "请检查 FlClash 节点，再点「重试」。"]
                p.detail = code == 2 ? "本次操作已停止。点「重新开始」可从当前设置继续。" :
                    (p.issue.map { $0.hasSuffix("。") ? $0 : $0 + "。" } ?? "") + (p.issue?.contains("重试") == true ? "" : next[p.step - 1])
                progress = p
            }
        }
        let finalText = lastVerifiedText
        operation = ""
        // A reconnect can change the PID/TUN. Associate the final readback with
        // the new observation, then invalidate it on any subsequent change.
        if let finalText = finalText {
            let p = worker("snapshot"), pipe = Pipe()
            p.standardOutput = pipe
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus == 0, let now = try? JSONDecoder().decode(Snapshot.self, from: data) {
                    update(now); setConfirmed(finalText); return
                }
            }
        }
        refresh()
    }

    func recover() {
        guard let window = window, !busy else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "解除日常保护和开机保护？"
        alert.informativeText = "应用将能直接访问公网。如果只是 FlClash 掉线，请返回后点「重新接通」。"
        alert.addButton(withTitle: "返回")
        alert.addButton(withTitle: "解除全部保护")
        alert.beginSheetModal(for: window) { answer in
            if answer == .alertSecondButtonReturn { self.start("recover") }
        }
    }

    func changeBoot() {
        if nextBoot == true && snapshot?.login == false { start("boot-on"); return }
        guard nextBoot == true else { start("boot-on"); return }
        guard let window = window, !busy else { return }
        let alert = NSAlert()
        alert.messageText = "取消以后开机自动保护？"
        alert.informativeText = "下次登录也会停止自动打开菜单栏 App。本次日常保护继续运行。"
        alert.addButton(withTitle: "返回")
        alert.addButton(withTitle: "取消开机保护")
        alert.beginSheetModal(for: window) { choice in
            if choice == .alertSecondButtonReturn { self.start("boot-off") }
        }
    }

    func openLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/FlClashEgressGuard/保护日志.txt")
        if !FileManager.default.fileExists(atPath: url.path) { message = "还没有保护日志。"; return }
        NSWorkspace.shared.open(url)
    }

    func close() { try? input?.close() }
}

struct GuardPanel: View {
    @ObservedObject var model: Controls
    private let accent = Color(red: 0.08, green: 0.42, blue: 0.68)

    private var stateColor: Color {
        switch model.state {
        case .connected: return .green
        case .locked: return .orange
        case .off, .unknown: return .secondary
        }
    }
    private var stateExplanation: String {
        switch model.state {
        case .connected: return "FlClash 掉线后，公网会锁住。"
        case .locked: return "本机和局域网仍可用。点「重新接通 FlClash」可恢复受保护的上网。"
        case .off: return "应用可以按原来的方式访问公网。"
        case .unknown: return model.confirmed == nil ? "点「开启日常保护」开始，也可先点「刷新状态」查看现状。" : ""
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(accent).font(.title2)
                Text("出网保护").font(.system(size: 23, weight: .semibold))
                Spacer()
                Button { model.start("status") } label: {
                    Label("刷新状态", systemImage: "arrow.clockwise")
                }.disabled(model.busy)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("日常保护").font(.headline)
                    Spacer()
                    if let time = model.confirmed?.time, model.progress == nil, !model.checking {
                        Text("上次核对 " + time.formatted(date: .omitted, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 9) {
                    if model.progress?.phase == .working || model.checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle().fill(model.progress == nil ? stateColor : .orange).frame(width: 10, height: 10)
                    }
                    Text(model.progress?.heading ?? (model.checking ? "正在核对…" : model.stateTitle))
                        .font(.system(size: 22, weight: .medium))
                }
                if model.progress != nil || model.state != .connected {
                    HStack(spacing: 12) {
                        ForEach(DailyProgress.titles.indices, id: \.self) { index in
                            HStack(spacing: 4) {
                                Image(systemName: "\(index + 1).circle" + (model.progress?.step == index + 1 ? ".fill" : ""))
                                Text(DailyProgress.titles[index])
                            }
                            .foregroundStyle(model.progress?.step == index + 1 ? accent : Color.secondary)
                            .accessibilityElement(children: .combine)
                        }
                    }.font(.callout)
                }
                if let p = model.progress {
                    Text(p.detail).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if p.phase == .failed || p.phase == .cancelled {
                        Text("防火墙状态：" + model.stateTitle).font(.callout).foregroundStyle(.secondary)
                    }
                } else if model.checking {
                    Text(model.approved ? "正在从系统读取保护状态。" : "请在 macOS 授权窗口输入管理员密码。")
                        .font(.callout)
                } else {
                    Text(model.coreDetail).font(.callout).foregroundStyle(.secondary)
                    if !stateExplanation.isEmpty { Text(stateExplanation).font(.callout) }
                }
                HStack {
                    if model.progress?.phase == .waiting {
                        Button("继续") { model.answerStep(true) }.buttonStyle(.borderedProminent).tint(accent)
                        Button("取消本次操作") { model.answerStep(false) }
                    } else {
                        Button(model.dailyAction) { model.start("daily") }
                            .buttonStyle(.borderedProminent).tint(accent)
                            .disabled(model.busy || (model.state == .connected && model.progress == nil))
                    }
                    Spacer()
                }.padding(.top, 3)
            }.padding(16).background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text("开机保护").font(.headline)
                        Text(model.bootLabel)
                            .foregroundStyle(model.nextBoot == true && model.snapshot?.login == true ? .green : .secondary)
                    }
                    Text(model.nextBoot == true && model.snapshot?.login == false ? "防火墙已登记，菜单栏 App 的登录启动需要补全。" : "开机先锁住公网，登录桌面后自动显示盾牌。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.nextBoot == true ? (model.snapshot?.login == true ? "取消开机保护…" : "补全登录启动") : "开启开机保护") {
                    model.changeBoot()
                }.disabled(model.busy || model.snapshot == nil || model.snapshot?.boot == "partial")
            }.padding(16).background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("恢复原来的上网方式").font(.headline)
                    Text("解除当前限制，同时取消开机保护。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("解除全部保护…") { model.recover() }.disabled(model.busy)
            }.padding(.horizontal, 4)
            Divider()
            HStack {
                Text(model.approved ? "系统助手已授权" : "首次授权后，日常操作免输密码。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.approved ? "撤销授权…" : "一次授权") {
                    if model.approved { model.removeAccess() } else { model.start("status") }
                }.buttonStyle(.link).disabled(model.busy)
            }
            HStack(alignment: .center, spacing: 8) {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.message.isEmpty ? "关闭这个窗口后，已启用的防火墙会继续运行。" : model.message)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("查看日志") { model.openLog() }.buttonStyle(.link)
            }.frame(minHeight: 32)
        }.padding(22).frame(width: 540).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MenuPanel: View {
    @ObservedObject var model: Controls
    let refresh: () -> Void
    let openPanel: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("FlClash 出网保护", systemImage: "shield.lefthalf.filled").font(.headline)
            Divider()
            HStack {
                Text("日常保护")
                Spacer()
                Text(model.progress?.heading ?? (model.checking ? "正在核对…" : model.stateTitle)).bold().foregroundStyle(
                    model.state == .connected ? Color.green : model.state == .locked ? Color.orange : Color.primary)
            }
            HStack {
                Text("开机保护")
                Spacer()
                Text(model.bootLabel)
                    .foregroundStyle(model.nextBoot == true && model.snapshot?.login == true ? Color.green : Color.secondary)
            }
            if let p = model.progress {
                Text(p.phase == .waiting ? "点「打开面板」，按当前步骤继续。" : p.detail)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if let check = model.confirmed {
                Text("最近核对 " + check.time.formatted(date: .omitted, time: .standard))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(model.busy ? "正在读取防火墙规则…" : model.approved ? "点「刷新状态」核对当前规则。" : "首次点「刷新状态」可授权，以后免输密码。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 10) {
                Button(action: refresh) { Label("刷新状态", systemImage: "arrow.clockwise") }
                    .disabled(model.busy)
                Button("打开面板", action: openPanel)
                Spacer()
                Button(action: quit) { Image(systemName: "power") }
                    .buttonStyle(.plain).help("退出状态栏 App，防火墙继续运行")
                    .accessibilityLabel("退出状态栏 App")
            }
        }.padding(16).frame(width: 288)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let controls = Controls()
    var window: NSWindow!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var observer: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
        main.addItem(item); item.submenu = appMenu
        let quit = NSMenuItem(title: "退出出网保护面板", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit)
        NSApp.mainMenu = main
        let host = NSHostingController(rootView: GuardPanel(model: controls))
        window = NSWindow(contentViewController: host)
        window.title = "FlClash 出网保护"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 540, height: 450)
        window.setContentSize(NSSize(width: 540, height: max(450, host.view.fittingSize.height)))
        window.setFrameAutosaveName("FlClashEgressGuardPanel")
        window.delegate = self
        controls.window = window
        window.center()
        installStatusItem()
        let notifications = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            notifications.addObserver(self, selector: #selector(flclashChanged(_:)), name: name, object: nil)
        }
        if ProcessInfo.processInfo.arguments.contains("--menu-bar") {
            controls.refresh()
        } else {
            window.makeKeyAndOrderFront(nil)
            controls.openStatus()
        }
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "FlClashEgressGuard"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("FlClash 出网保护")
        }
        let panel = MenuPanel(model: controls, refresh: { [weak self] in
            guard let self = self else { return }
            self.popover.behavior = .applicationDefined
            self.controls.start("status")
        }, openPanel: { [weak self] in self?.openPanel(verify: false) }, quit: { NSApp.terminate(nil) })
        popover.contentViewController = NSHostingController(rootView: panel)
        popover.behavior = .transient
        popover.animates = false
        observer = controls.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateIcon()
        }
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch controls.state {
        case .connected: symbol = "checkmark.shield.fill"
        case .locked: symbol = "lock.shield.fill"
        case .off: symbol = "xmark.shield"
        case .unknown: symbol = "exclamationmark.shield"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FlClash 出网保护")
        image?.isTemplate = true
        button.image = image
        let value = "日常保护" + (controls.progress?.heading ?? controls.stateTitle) + "，开机保护" + controls.bootLabel
        button.toolTip = "FlClash 出网保护\n" + value
        button.setAccessibilityValue(value)
        if !controls.busy && popover.isShown { popover.behavior = .transient }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button, let content = popover.contentViewController?.view else { return }
        if popover.isShown { popover.performClose(nil); return }
        // Keep the result on screen if macOS brings its password dialog forward.
        popover.behavior = .applicationDefined
        // Measure the SwiftUI content before AppKit positions the arrow against the button.
        popover.contentSize = content.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        controls.openStatus()
    }

    @objc private func flclashChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleURL?.standardizedFileURL.path == "/Applications/FlClash.app" else { return }
        // Discard stale confirmation on an OS event. There is no UI polling timer.
        controls.invalidateObservation()
    }

    private func openPanel(verify: Bool = true) {
        if popover.isShown { popover.performClose(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if verify { controls.openStatus() } else { controls.refresh() }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if window?.isVisible == true { controls.refresh() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPanel()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { controls.close() }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
