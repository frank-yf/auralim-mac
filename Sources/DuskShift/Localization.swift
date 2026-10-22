import Foundation
import DuskShiftCore

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant", english = "en"
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .system: return ""
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        }
    }

    func resolved(preferredLanguages: [String]) -> AppLanguage {
        guard self == .system else { return self }
        for preference in preferredLanguages {
            let parts = preference.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
            if parts.first == "en" { return .english }
            if parts.first == "zh" {
                if parts.contains("hant") { return .traditionalChinese }
                if parts.contains("hans") { return .simplifiedChinese }
                return parts.contains(where: { ["hant", "tw", "hk", "mo"].contains(String($0)) })
                    ? .traditionalChinese : .simplifiedChinese
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
        if let url = Bundle.main.url(forResource: "DuskShift_DuskShift", withExtension: "bundle"),
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
