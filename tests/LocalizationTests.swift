// App launch code is excluded by check.sh; these tests only assign sample state.
final class MemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

var assertions = 0
func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    assertions += 1
    if !condition() { fputs("FAIL: \(description)\n", stderr); exit(1) }
}

func noChinese(_ text: String) -> Bool {
    !text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
}

func table(_ name: String, language: String, resources: URL) -> [String: String] {
    let path = resources.appendingPathComponent(language + ".lproj/" + name + ".strings")
    let data = try! Data(contentsOf: path)
    return try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
}

let resourcesURL = URL(fileURLWithPath: CommandLine.arguments[1])
let resourcesBundle = Bundle(url: resourcesURL)!
let localization = Localization.shared
localization.configure(resources: resourcesBundle, defaults: nil, preferredLanguages: ["en-US"])
expect(localization.preference == .system && localization.languageCode == "en", "fresh preference follows system")
for language in ["en-US", "ja-JP", "fr-FR", "de-DE"] {
    expect(Localization.resolve(.system, preferredLanguages: [language, "zh-Hans"]) == "en", "non-Chinese primary language uses English: \(language)")
}
for language in ["zh-Hans", "zh-Hant-TW", "zh-CN"] {
    expect(Localization.resolve(.system, preferredLanguages: [language]) == "zh-Hans", "Chinese primary language uses Chinese: \(language)")
}
expect(Localization.resolve(.english, preferredLanguages: ["zh-Hans"]) == "en", "English override")
expect(Localization.resolve(.zhHans, preferredLanguages: ["en-US"]) == "zh-Hans", "Chinese override")

let memory = MemoryDefaults()
localization.configure(resources: resourcesBundle, defaults: memory, preferredLanguages: ["ja-JP"])
localization.preference = .zhHans
expect(memory.string(forKey: Localization.preferenceKey) == "zh-Hans", "save language preference in app store")
localization.configure(resources: resourcesBundle, defaults: memory, preferredLanguages: ["ja-JP"])
expect(localization.preference == .zhHans && localization.languageCode == "zh-Hans", "restore saved language preference")
localization.preference = .system
expect(localization.languageCode == "en", "return to system language")
expect(memory.values.keys.allSatisfy { $0 == Localization.preferenceKey }, "preference changes only app language key")
localization.configure(resources: resourcesBundle, defaults: nil, preferredLanguages: ["en-US"])

for name in ["Localizable", "GuardMessages", "InfoPlist"] {
    let english = table(name, language: "en", resources: resourcesURL)
    let chinese = table(name, language: "zh-Hans", resources: resourcesURL)
    expect(!english.isEmpty && english.keys.sorted() == chinese.keys.sorted(), "\(name): matching, nonempty language tables")
    for (key, value) in english {
        expect(!value.isEmpty && chinese[key]?.isEmpty == false, "\(name): translated value for \(key)")
    }
}
expect(L10n.text("开启日常保护") == "Turn on daily protection", "English UI label")
expect(L10n.text("第 %d / 4 步 · %@", 2, L10n.text("需要你操作")).hasPrefix("Step 2 / 4"), "formatted step heading")

let messages = [
    "正在读取本机防火墙规则。",
    "请点菜单栏的 FlClash 图标，选「退出」。图标消失后回到这里点「继续」。公网已锁住。",
    "请打开 FlClash，确认「虚拟网卡（TUN）」开关已开启，再回到这里点「继续」。",
    "日常保护 · 切换前锁住公网 通过",
    "日常保护 · Google 可访问 通过",
    "日常保护 · 抖音 可访问 不通过",
    "Google、抖音 没有返回网页。请检查 FlClash 里选用的节点，再点「重试」。",
    "核心的 TUN 未启用。请检查 FlClash 节点，再点「重试」。",
    "本机控制器未能启动。请点「重试」。",
    "pfctl 操作失败（退出码 1）。",
    "FlClashCore    PID 4242    有效 UID 0    有效 GID 39999",
    "保护已装载，核心使用 utun4。",
    "限时试用剩余 120 秒。",
    "锁定原因  核心或虚拟网卡状态改变",
    "系统助手设置未完成，可在面板重试。",
    "系统助手未能启动防火墙控制器。",
    "已解除出网限制并取消开机保护。等你下次手动退出 FlClash 后，可再次点「解除全部保护」清理专用组。",
    "2026-11-17T09:41:00-08:00\t日常保护 · Google · 收到网站 HTTP 回应\t通过\n2026-11-17T09:41:02-08:00\t日常保护 · 抖音 · 解析网站名称\t不通过\n"
]
for message in messages {
    localization.preference = .english
    expect(noChinese(L10n.message(message)), "English progress/error/log translation: \(message)")
    localization.preference = .zhHans
    expect(L10n.message(message) == message, "Chinese display preserves raw message")
}
localization.preference = .english
expect(L10n.message("保护已装载，核心使用 utun4。").contains("utun4"), "keep TUN identifier")
expect(L10n.message(messages.last!).contains("2026-11-17T09:41:00-08:00"), "keep log timestamp")

// Localize existing messages immediately, without re-reading system state.
let model = Controls()
model.snapshot = Snapshot(boot: "on", login: true, mode: "dedicated", core: 4242, identity: "4242/1")
let report = "系统 pf 已启用\nFlClashCore    PID 4242    有效 UID 0    有效 GID 39999\n保护已装载，核心使用 utun4。"
model.setConfirmed(report)
expect(model.state == .connected, "raw Chinese protocol still confirms connected state in English")
expect(noChinese(L10n.message(model.coreDetail)) && L10n.message(model.coreDetail).contains("utun4"), "English verified core detail")
model.progress = DailyProgress(step: 2, detail: messages[1], phase: .waiting)
let rawDetail = model.progress!.detail
expect(model.progress!.heading.hasPrefix("Step 2 / 4"), "English waiting heading")
localization.preference = .zhHans
expect(model.progress!.heading.hasPrefix("第 2 / 4 步"), "existing heading switches to Chinese")
expect(model.progress!.detail == rawDetail && model.state == .connected, "language switch leaves progress data and protection state intact")
localization.preference = .english
model.setConfirmed("系统 pf 已启用\n公网出口已锁定；局域网和回环例外仍有效。")
expect(model.state == .locked && L10n.text(model.stateTitle) == "Internet locked", "locked state protocol")
model.setConfirmed("本工具已停用。")
expect(model.state == .off && L10n.text(model.stateTitle) == "Off", "off state protocol")
model.setConfirmed("系统 pf 已启用\n保护异常，内核中缺少有效阻断。")
expect(model.state == .unknown && L10n.text(model.stateTitle) == "Re-check", "unverified state protocol")
expect(noChinese(L10n.message(model.coreDetail)), "unverified detail translation")
print("PASS: \(assertions) localization, persistence, progress, error, log and state-protocol assertions (no services started)")
