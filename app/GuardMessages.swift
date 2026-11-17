import Foundation

/// The controller's Chinese output is also its state protocol. Keep those bytes
/// intact for parsing and translate only the copy shown in the interface or log.
enum GuardMessages {
    private static let templates: [(pattern: String, key: String)] = [
        (#"^(.+) 操作失败（退出码 (-?\d+)）。$"#, "%@ 操作失败（退出码 %@）。"),
        (#"^(\S+)    PID (\d+)    有效 UID (\d+)    有效 GID (\d+)$"#,
         "%@    PID %@    有效 UID %@    有效 GID %@"),
        (#"^保护已装载，核心使用 (utun\d+)。$"#, "保护已装载，核心使用 %@。"),
        (#"^限时试用剩余 (\d+) 秒。$"#, "限时试用剩余 %@ 秒。"),
        (#"^通过：当前核心持有 (utun\d+)；联网和锁定两套规则均通过 pfctl -n。$"#,
         "通过：当前核心持有 %@；联网和锁定两套规则均通过 pfctl -n。"),
        (#"^锁定原因  (.+)$"#, "锁定原因  %@"),
        (#"^用法：egress-guard (.+)$"#, "用法：egress-guard %@"),
        (#"^(.+) 没有返回网页。请检查 FlClash 里选用的节点，再点「重试」。$"#,
         "%@ 没有返回网页。请检查 FlClash 里选用的节点，再点「重试」。")
    ]

    static func localize(_ raw: String, language: String, resources: Bundle,
                         additionalLookup: ((String) -> String?)? = nil) -> String {
        guard !language.hasPrefix("zh"),
              let folder = resources.url(forResource: language, withExtension: "lproj"),
              let bundle = Bundle(url: folder) else { return raw }

        func lookup(_ key: String) -> String? {
            let value = bundle.localizedString(forKey: key, value: key, table: "GuardMessages")
            return value == key ? additionalLookup?(key) : value
        }

        func translate(_ text: String) -> String {
            if let exact = lookup(text) { return exact }
            if text.contains("\n") {
                return text.components(separatedBy: "\n").map(translate).joined(separator: "\n")
            }
            if text.contains("\t") {
                // Existing on-disk logs retain their original language. Only the
                // read-only log window localizes labels, never the timestamp.
                return text.components(separatedBy: "\t").map(translate).joined(separator: "\t")
            }
            for template in templates {
                guard let expression = try? NSRegularExpression(pattern: template.pattern),
                      let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let format = lookup(template.key) else { continue }
                let values = (1..<match.numberOfRanges).map { index -> CVarArg in
                    guard let range = Range(match.range(at: index), in: text) else { return "" as NSString }
                    return translate(String(text[range])) as NSString
                }
                return String(format: format, locale: Locale(identifier: "en"), arguments: values)
            }
            // Guide results are a fixed label followed by a verdict; website
            // labels additionally contain a name and expected reachability.
            for suffix in [" 不通过", " 通过", " 连不上", " 可访问"] where text.hasSuffix(suffix) {
                let label = translate(String(text.dropLast(suffix.count)))
                return label + " " + (lookup(String(suffix.dropFirst())) ?? String(suffix.dropFirst()))
            }
            // Split at the final separator to retain complete, translated
            // labels such as “Daily protection · Lock internet before switching”.
            if let separator = text.range(of: " · ", options: .backwards) {
                return translate(String(text[..<separator.lowerBound])) + " · " +
                    translate(String(text[separator.upperBound...]))
            }
            if text.contains("、") {
                return text.components(separatedBy: "、").map(translate).joined(separator: " and ")
            }
            // Recovery can append a second complete sentence to its result.
            // Translate those sentences without changing the underlying log.
            let sentences = text.components(separatedBy: "。")
            if sentences.count > 2 || (sentences.count == 2 && !sentences[1].isEmpty) {
                return sentences.enumerated().compactMap { index, sentence -> String? in
                    guard !sentence.isEmpty else { return nil }
                    return translate(sentence + (index < sentences.count - 1 ? "。" : ""))
                }.joined(separator: " ")
            }
            return text
        }

        return translate(raw)
    }
}
