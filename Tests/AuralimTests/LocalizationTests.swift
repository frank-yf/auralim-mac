import Foundation
import Testing
import AuralimCore
@testable import Auralim

struct LocalizationTests {
    @Test
    func systemLanguageMatchingAndFallback() {
        let cases: [([String], AppLanguage)] = [
            (["zh-CN"], .simplifiedChinese), (["zh-SG"], .simplifiedChinese),
            (["zh-Hans-HK"], .simplifiedChinese), (["zh-Hant"], .traditionalChinese),
            (["zh-TW"], .traditionalChinese), (["zh-HK"], .traditionalChinese),
            (["en-GB"], .english), (["fr-FR", "zh-TW"], .french),
            (["de-CH"], .german), (["ja-JP"], .japanese), (["fr-CA"], .french),
            (["es-MX"], .spanish), (["pt_BR"], .brazilianPortuguese),
            (["pt-PT"], .brazilianPortuguese), (["ko-KR"], .korean),
            (["it-IT"], .italian), (["ru-RU"], .russian), (["nl-BE"], .dutch),
            (["zh-Hant-CN"], .traditionalChinese), (["zh-MO"], .traditionalChinese),
            (["sv-SE", "ja-JP"], .japanese), (["sv-SE"], .english), ([], .english)
        ]
        for (preferences, expected) in cases {
            #expect(AppLanguage.system.resolved(preferredLanguages: preferences) == expected)
        }
        #expect(AppLanguage.english.resolved(preferredLanguages: ["zh-CN"]) == .english)
    }

    @Test
    func catalogsAreCompleteAndFormatsMatch() throws {
        var catalogs: [[String: String]] = []
        for language in AppLanguage.allCases where language != .system {
            let localizer = Localizer(language: language)
            #expect(localizer.bundle.bundleURL.lastPathComponent == language.rawValue.lowercased() + ".lproj")
            let url = try #require(localizer.bundle.url(forResource: "Localizable", withExtension: "strings"))
            let catalog = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
            #expect(catalog.values.allSatisfy { !$0.isEmpty })
            for (key, value) in catalog { #expect(localizer.text(key) == value) }
            catalogs.append(catalog)
        }
        let baseline = try #require(catalogs.first)
        let pattern = try NSRegularExpression(pattern: "%[@d]")
        func placeholders(_ text: String) -> [String] {
            pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                String(text[Range($0.range, in: text)!])
            }
        }
        for catalog in catalogs.dropFirst() {
            #expect(Set(catalog.keys) == Set(baseline.keys))
            for key in baseline.keys { #expect(placeholders(catalog[key]!) == placeholders(baseline[key]!)) }
        }
    }

    @Test
    func translationsFormatNumbersCitiesAndFallback() {
        let en = Localizer(language: .english)
        let hans = Localizer(language: .simplifiedChinese)
        let hant = Localizer(language: .traditionalChinese)
        #expect(en.text("offset.earlier", 37) == "37 min earlier")
        #expect(hans.text("offset.earlier", 37) == "提前 37 分钟")
        #expect(hant.text("offset.later", 42) == "延後 42 分鐘")
        #expect(en.text("app.name") == "Auralim")
        #expect(en.text("slogan") == "Between light and dark.")
        #expect(hans.text("slogan") == "日升而明，日落而暗")
        #expect(hant.text("slogan") == "日升而明，日落而暗")
        #expect(hans.text("app.name") == "晨昏")
        #expect(hant.text("app.name") == "晨昏")
        #expect(Localizer(language: .system, preferredLanguages: ["fr-FR"]).text("app.name") == "Auralim")
        #expect(en.text("settings.title") == "Auralim Settings")
        #expect(hant.text("settings.title") == "晨昏設定")
        #expect(en.text("missing.key") == "missing.key")
        for city in City.all {
            for localizer in AppLanguage.allCases.filter({ $0 != .system }).map({ Localizer(language: $0) }) { #expect(localizer.cityName(city) != "city." + city.id) }
        }
        #expect(en.cityName(City.all[0]) == "Shanghai")
    }
    @Test
    func supportedLanguagesAndPermissionCatalogs() throws {
        let languages = AppLanguage.allCases.filter { $0 != .system }
        let expected = ["en", "zh-Hans", "ja", "zh-Hant", "de", "fr", "es", "pt-BR", "ko", "it", "ru", "nl"]
        #expect(languages.map(\.rawValue) == expected)
        #expect(Set(languages.map(\.nativeName)).count == 12)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let info = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Resources/Info.plist")), format: nil) as? [String: Any])
        #expect(info["CFBundleDevelopmentRegion"] as? String == "en")
        #expect(info["CFBundleLocalizations"] as? [String] == expected)
        for language in languages {
            #expect(AppLanguage(rawValue: language.rawValue) == language)
            #expect(language.resolved(preferredLanguages: ["en", "zh-CN"]) == language)
            let catalog = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Resources/\(language.rawValue).lproj/InfoPlist.strings")), format: nil) as? [String: String])
            #expect(Set(catalog.keys) == ["CFBundleName", "CFBundleDisplayName", "NSAppleEventsUsageDescription", "NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"])
            #expect(catalog.values.allSatisfy { !$0.isEmpty })
            #expect(catalog["NSLocationUsageDescription"] == catalog["NSLocationWhenInUseUsageDescription"])
            #expect(catalog["CFBundleDisplayName"] == Localizer(language: language).text("app.name"))
            #expect(Localizer(language: language).text("offset.earlier", 37).contains("37"))
        }
    }

}
