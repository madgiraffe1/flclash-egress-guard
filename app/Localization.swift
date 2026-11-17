import Combine
import Foundation

// The stored choice is app-specific. Never change AppleLanguages or the system locale.
enum LanguagePreference: String, CaseIterable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"
}

final class Localization: ObservableObject {
    static let shared = Localization()
    static let preferenceKey = "interfaceLanguage"

    @Published var preference: LanguagePreference {
        didSet {
            defaults?.set(preference.rawValue, forKey: Self.preferenceKey)
            refreshSystemLanguage()
        }
    }
    @Published private(set) var languageCode: String
    private(set) var resources: Bundle = .main
    private var defaults: UserDefaults?
    private var preferredLanguages: [String]?
    private var localeObserver: NSObjectProtocol?

    var locale: Locale { Locale(identifier: languageCode == "zh-Hans" ? "zh_CN" : "en_US") }
    var panelWidth: CGFloat { languageCode == "en" ? 600 : 540 }
    var menuWidth: CGFloat { languageCode == "en" ? 340 : 288 }

    private init() {
        defaults = .standard
        let saved = UserDefaults.standard.string(forKey: Self.preferenceKey)
        let choice = saved.flatMap(LanguagePreference.init(rawValue:)) ?? .system
        preference = choice
        languageCode = Self.resolve(choice, preferredLanguages: Locale.preferredLanguages)
        localeObserver = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.refreshSystemLanguage()
        }
    }

    static func resolve(_ preference: LanguagePreference, preferredLanguages: [String]) -> String {
        switch preference {
        case .english: return "en"
        case .zhHans: return "zh-Hans"
        case .system: return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
        }
    }

    // Offline renderer and tests supply their own resources and an optional isolated
    // preference store. With nil defaults, changing language never writes preferences.
    func configure(resources: Bundle, defaults: UserDefaults? = nil, preferredLanguages: [String]? = nil) {
        self.resources = resources
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        preference = defaults?.string(forKey: Self.preferenceKey).flatMap(LanguagePreference.init(rawValue:)) ?? .system
        refreshSystemLanguage()
    }

    func refreshSystemLanguage() {
        let resolved = Self.resolve(preference, preferredLanguages: preferredLanguages ?? Locale.preferredLanguages)
        if languageCode != resolved { languageCode = resolved }
    }

    func string(_ key: String) -> String {
        guard let path = resources.path(forResource: languageCode, ofType: "lproj"), let bundle = Bundle(path: path)
        else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let value = Localization.shared.string(key)
        return arguments.isEmpty ? value : String(format: value, locale: Localization.shared.locale, arguments: arguments)
    }

    static func time(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Localization.shared.locale
        format.timeStyle = .medium
        format.dateStyle = .none
        return format.string(from: date)
    }

    // Keep the controller's Chinese wire protocol untouched. Translate only the
    // displayed value, so a live progress/error message also follows language changes.
    static func message(_ raw: String) -> String {
        let localization = Localization.shared
        guard localization.languageCode == "en", !raw.isEmpty else { return raw }
        let exact = localization.string(raw)
        if exact != raw { return exact }
        let prefix = "防火墙已确认专用核心、监视器和虚拟网卡（"
        if raw.hasPrefix(prefix), raw.hasSuffix("）。") {
            return text("防火墙已确认专用核心、监视器和虚拟网卡（%@）。", String(raw.dropFirst(prefix.count).dropLast(2)))
        }
        return GuardMessages.localize(raw, language: localization.languageCode, resources: localization.resources,
                                      additionalLookup: { key in
            let value = localization.string(key)
            return value == key ? nil : value
        })
    }
}
