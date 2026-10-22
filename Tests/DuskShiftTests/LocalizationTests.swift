import Foundation
import Testing
import DuskShiftCore
@testable import DuskShift

struct LocalizationTests {
    @Test
    func systemLanguageMatchingAndFallback() {
        let cases: [([String], AppLanguage)] = [
            (["zh-CN"], .simplifiedChinese), (["zh-SG"], .simplifiedChinese),
            (["zh-Hans-HK"], .simplifiedChinese), (["zh-Hant"], .traditionalChinese),
            (["zh-TW"], .traditionalChinese), (["zh-HK"], .traditionalChinese),
            (["en-GB"], .english), (["fr-FR", "zh-TW"], .traditionalChinese),
            (["de-DE"], .english), ([], .english)
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
        #expect(en.text("app.name") == "DuskShift")
        #expect(hans.text("app.name") == "日暮")
        #expect(hant.text("app.name") == "日暮")
        #expect(Localizer(language: .system, preferredLanguages: ["fr-FR"]).text("app.name") == "DuskShift")
        #expect(en.text("settings.title") == "DuskShift Settings")
        #expect(hant.text("settings.title") == "日暮設定")
        #expect(en.text("missing.key") == "missing.key")
        for city in City.all {
            for localizer in [en, hans, hant] { #expect(localizer.cityName(city) != "city." + city.id) }
        }
        #expect(en.cityName(City.all[0]) == "Shanghai")
    }
}
