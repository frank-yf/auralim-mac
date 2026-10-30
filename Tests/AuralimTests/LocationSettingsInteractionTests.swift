import AppKit
import SwiftUI
import Testing
import AuralimCore
@testable import Auralim

private final class LocationUIAppearance: AppearanceApplying {
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        completion(.success(AppearanceApplication(changed: false)))
    }
}

@Suite(.serialized)
struct LocationSettingsInteractionTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_LOCATION_UI_TESTS"] == "1"))
    func modeSwitchHasNoIntervalPickerAndFailedRefreshDisplaysCachedLocation() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let suite = "Auralim.LocationUI.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.set("zh-Hans", forKey: "language")
        store.set("30d", forKey: "locationRefreshInterval")
        let location = FakeLocation()
        let model = AppModel(defaults: store, controller: LocationUIAppearance(), enableTimers: false,
            systemTimeZone: { TimeZone(identifier: "Asia/Tokyo")! },
            loginItemController: FakeLoginItem(), locationController: location)
        defer { model.shutdown(); store.removePersistentDomain(forName: suite) }
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsContent(model: model)))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 640))
        window.center()
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func popups() -> [NSPopUpButton] { descendants(window.contentView!).compactMap { $0 as? NSPopUpButton } }
        func selectMode(_ segment: Int) throws {
            let mode = try #require(descendants(window.contentView!).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 2 })
            mode.selectedSegment = segment
            #expect(mode.sendAction(mode.action, to: mode.target))
            settle()
        }
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_LOCATION_UI_OUTPUT"]
            ?? "/private/tmp/auralim-location-ui")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func capture(_ stage: String) throws {
            for language in [AppLanguage.simplifiedChinese, .english] {
                model.language = language
                for theme in [NSAppearance.Name.aqua, .darkAqua] {
                    window.appearance = NSAppearance(named: theme); settle()
                    let host = try #require(window.contentView)
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try #require(bitmap.representation(using: .png, properties: [:])).write(to:
                        folder.appendingPathComponent("\(stage)-\(language.rawValue)-\(theme == .aqua ? "light" : "dark").png"))
                }
            }
            model.language = .simplifiedChinese; settle()
        }
        settle()
        let manualPickerCount = popups().count
        #expect(location.starts == 0 && store.object(forKey: "locationRefreshInterval") == nil)
        let cityPicker = try #require(popups().first { !$0.itemTitles.contains("English") })
        for cityID in ["Asia/Shanghai", "Asia/Tokyo"] {
            let city = try #require(City.all.first { $0.id == cityID })
            let index = cityPicker.indexOfItem(withTitle: model.cityName(city))
            try #require(index >= 0)
            try #require(cityPicker.menu).performActionForItem(at: index); settle()
            #expect(model.cityID == cityID && model.city.id == cityID)
        }
        #expect(model.t("location.manual") == "选择城市")
        try capture("manual")
        try selectMode(1)
        #expect(model.locationMode == .automatic && location.starts == 1)
        #expect(model.city.id == "Asia/Tokyo")
        // Only language and city dropdowns remain, in both modes.
        #expect(popups().count == manualPickerCount && manualPickerCount == 2)
        let cached = City(id: "current-location", name: "", latitude: 40.7128,
            longitude: -74.0060, timeZoneID: "America/New_York")
        location.onEvent?(.resolved(cached))
        model.refreshLocation()
        #expect(location.refreshes == 1 && model.city == cached && model.isLocating)
        #expect(model.locationStatus.contains("沿用缓存位置"))
        try capture("refreshing-cached")
        location.onEvent?(.failed(.timeout, cachedCity: cached))
        settle()
        #expect(model.city == cached && !model.isLocating)
        #expect(model.locationStatus.contains("缓存位置") && !model.locationStatus.contains("东京"))
        try capture("automatic-cached")
        try selectMode(0)
        #expect(model.locationMode == .manual && model.city.id == "Asia/Tokyo" && location.stops == 1)
        #expect(popups().count == manualPickerCount)
        print("Verified location UI only: native mode switch, no interval selector, cached fallback, light/dark panels")
    }
}
