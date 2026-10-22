import Foundation
import AuralimCore

enum AppLanguage: String, CaseIterable, Identifiable {
    // English is the development baseline; this order also drives the picker.
    case system, english = "en", simplifiedChinese = "zh-Hans", japanese = "ja"
    case traditionalChinese = "zh-Hant", german = "de", french = "fr"
    case spanish = "es", brazilianPortuguese = "pt-BR", korean = "ko"
    case italian = "it", russian = "ru", dutch = "nl"

    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .system: return ""
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .japanese: return "日本語"
        case .traditionalChinese: return "繁體中文"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .brazilianPortuguese: return "Português (Brasil)"
        case .korean: return "한국어"
        case .italian: return "Italiano"
        case .russian: return "Русский"
        case .dutch: return "Nederlands"
        }
    }

    func resolved(preferredLanguages: [String]) -> AppLanguage {
        guard self == .system else { return self }
        for preference in preferredLanguages {
            let parts = preference.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
            switch parts.first {
            case "en": return .english
            case "zh":
                // An explicit script takes precedence over a regional default.
                if parts.contains("hant") { return .traditionalChinese }
                if parts.contains("hans") { return .simplifiedChinese }
                return parts.contains(where: { ["tw", "hk", "mo"].contains(String($0)) })
                    ? .traditionalChinese : .simplifiedChinese
            case "ja": return .japanese
            case "de": return .german
            case "fr": return .french
            case "es": return .spanish
            case "pt": return .brazilianPortuguese
            case "ko": return .korean
            case "it": return .italian
            case "ru": return .russian
            case "nl": return .dutch
            default: continue
            }
        }
        return .english
    }
}

struct Localizer {
    let language: AppLanguage
    let locale: Locale
    let bundle: Bundle

    static let resourceBundle: Bundle = {
        // The installed .app must work independently of the original build path.
        if let url = Bundle.main.url(forResource: "Auralim_Auralim", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()

    private static let bundles: [AppLanguage: Bundle] = {
        var result: [AppLanguage: Bundle] = [:]
        for language in AppLanguage.allCases where language != .system {
            // SwiftPM normalizes localization folder names to lowercase. Use a
            // direct path; Bundle resource lookup may choose the system fallback.
            let url = resourceBundle.bundleURL.appendingPathComponent(language.rawValue.lowercased() + ".lproj")
            if let bundle = Bundle(url: url) { result[language] = bundle }
        }
        return result
    }()

    init(language: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.language = language.resolved(preferredLanguages: preferredLanguages)
        locale = Locale(identifier: self.language.rawValue)
        bundle = Self.bundles[self.language] ?? Self.resourceBundle
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String { text(key, arguments: arguments) }
    func text(_ key: String, arguments: [CVarArg]) -> String {
        let fallback = Self.bundles[.english]?.localizedString(forKey: key, value: key, table: nil) ?? key
        let format = bundle.localizedString(forKey: key, value: fallback, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }

    func cityName(_ city: City) -> String { text("city." + city.id) }
}
