import AppKit
import SwiftUI
import Testing
import Vision
import AuralimCore
@testable import Auralim

private final class LayoutRefinementAppearance: AppearanceApplying {
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        completion(.success(.init(changed: false)))
    }
}

@MainActor
@Suite(.serialized)
struct SettingsLayoutRefinementTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_LAYOUT_UI"] == "1"))
    func alignedSwitchesConditionalDurationAndLocationTimes() throws {
        let app = NSApplication.shared; app.finishLaunching()
        let originalPolicy = app.activationPolicy()
        defer { _ = app.setActivationPolicy(originalPolicy) }
        _ = app.setActivationPolicy(.accessory)
        let suite = "Auralim.SettingsLayout.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.set("zh-Hans", forKey: "language"); store.set("Asia/Shanghai", forKey: "city")
        let model = AppModel(defaults: store, controller: LayoutRefinementAppearance(),
            clock: { ISO8601DateFormatter().date(from: "2026-10-30T04:00:00Z")! }, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(), systemSettings: { .init(mode: .light, appearance: .light) })
        let updates = UpdateController(preferences: store)
        let presenter = SettingsWindowController(); presenter.show(model: model, updater: updates)
        let window = try #require(presenter.window)
        defer { window.close(); model.shutdown(); store.removePersistentDomain(forName: suite) }
        let host = try #require(window.contentView)
        func settle(_ delay: TimeInterval = 0.18) { RunLoop.main.run(until: Date().addingTimeInterval(delay)) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func fields() -> [NSTextField] { descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable) }
        settle()
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first)
        let document = try #require(scroll.documentView)
        func scrollToBottom(_ bottom: Bool) {
            let end = max(0, document.bounds.height - scroll.contentView.bounds.height)
            let y = bottom == document.isFlipped ? end : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView); settle()
        }
        let switches = descendants(host).compactMap { $0 as? NSSwitch }
        #expect(switches.count == 3)
        let animation = try #require(switches.first), countdown = try #require(switches.dropFirst().first)
        func assertAlignment() {
            let a = animation.convert(animation.bounds, to: host), b = countdown.convert(countdown.bounds, to: host)
            #expect(abs(a.minX - b.minX) < 0.5)
        }
        assertAlignment(); #expect(fields().count == 2 && !model.countdownEnabled)
        _ = countdown.accessibilityPerformPress(); settle()
        #expect(model.countdownEnabled && fields().count == 3); assertAlignment()
        let duration = try #require(fields().first { $0.stringValue == "10" })
        let switchFrame = countdown.convert(countdown.bounds, to: host), inputFrame = duration.convert(duration.bounds, to: host)
        #expect(inputFrame.maxX <= switchFrame.minX && switchFrame.minX - inputFrame.maxX < 100)
        func type(_ value: String, into field: NSTextField) throws {
            window.makeFirstResponder(field)
            let editor = try #require(field.currentEditor() as? NSTextView)
            editor.selectAll(nil); editor.insertText(value, replacementRange: editor.selectedRange())
            let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            app.sendEvent(enter); settle()
        }
        try type("17", into: duration); #expect(model.countdownSeconds == 17)
        window.makeFirstResponder(nil)
        _ = countdown.accessibilityPerformPress(); settle()
        #expect(!model.countdownEnabled && fields().count == 2 && model.countdownSeconds == 17); assertAlignment()
        let offsets = fields()
        try type("+37", into: offsets[0]); try type("-42", into: offsets[1]); window.makeFirstResponder(nil)
        #expect(model.sunriseOffset == 37 && model.offset == -42)
        let schedule = try #require(model.schedule)
        #expect(schedule.todayLightTime == schedule.today.sunrise?.addingTimeInterval(37 * 60))
        #expect(schedule.todayDarkTime == schedule.today.sunset?.addingTimeInterval(-42 * 60))
        let updatePicker = try #require(descendants(host).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 2 && $0.label(forSegment: 0) == "手动更新" })
        #expect(updatePicker.isDescendant(of: scroll) && switches.last?.isDescendant(of: scroll) == true)
        #expect(document.bounds.height > scroll.contentView.bounds.height + 30)
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_LAYOUT_OUTPUT"]!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ name: String) throws -> String {
            settle()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let path = output.appendingPathComponent(name + ".png")
            let png = try #require(bitmap.representation(using: .png, properties: [:])); try png.write(to: path)
            let request = VNRecognizeTextRequest(); request.recognitionLanguages = ["zh-Hans", "en-US"]; request.recognitionLevel = .accurate
            try VNImageRequestHandler(url: path).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }
        for language in [AppLanguage.simplifiedChinese, .english] {
            model.language = language; settle()
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: theme); scrollToBottom(false)
                let suffix = "\(language.rawValue)-\(theme == .aqua ? "light" : "dark")"
                let text = try capture("top-off-" + suffix)
                print("Header and offset times:", text)
                let digits = text.filter(\.isNumber)
                #expect(digits.contains(model.clockTime(schedule.today.sunrise).filter(\.isNumber)))
                #expect(digits.contains(model.clockTime(schedule.today.sunset).filter(\.isNumber)))
                _ = countdown.accessibilityPerformPress(); settle(); assertAlignment()
                #expect(fields().count == 3 && model.countdownSeconds == 17)
                _ = try capture("top-on-" + suffix)
                _ = countdown.accessibilityPerformPress(); settle()
                scrollToBottom(true)
                #expect(updatePicker.visibleRect.width > 100 && updatePicker.isDescendant(of: scroll))
                _ = try capture("bottom-" + suffix)
            }
        }
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(try #require(window.standardWindowButton(.miniaturizeButton)).isEnabled)
        window.miniaturize(nil); settle(0.5)
        #expect(window.isMiniaturized && app.activationPolicy() == .regular)
        presenter.show(model: model, updater: updates); settle(0.5)
        #expect(!window.isMiniaturized && presenter.window === window && app.activationPolicy() == .regular)
        window.close(); settle(); #expect(app.activationPolicy() == .accessory)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_LAYOUT_UI"] == "1"))
    func locationShowsClockOnlySunriseAndSunset() throws {
        let app = NSApplication.shared; app.finishLaunching()
        let suite = "Auralim.OffsetClock.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.set("Asia/Shanghai", forKey: "city"); store.set(37, forKey: "sunriseOffset"); store.set(-42, forKey: "offset")
        let model = AppModel(defaults: store, controller: LayoutRefinementAppearance(),
            clock: { ISO8601DateFormatter().date(from: "2026-10-30T04:00:00Z")! }, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(), systemSettings: { .init(mode: .light, appearance: .light) })
        let presenter = SettingsWindowController(); presenter.show(model: model)
        let window = try #require(presenter.window), host = try #require(window.contentView)
        defer { window.close(); model.shutdown(); store.removePersistentDomain(forName: suite) }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_LAYOUT_OUTPUT"]!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in [AppLanguage.simplifiedChinese, .english] {
            model.language = language
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: theme)
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                let path = output.appendingPathComponent("clock-\(language.rawValue)-\(theme == .aqua ? "light" : "dark").png")
                try png.write(to: path)
                let request = VNRecognizeTextRequest(); request.recognitionLanguages = ["zh-Hans", "en-US"]
                try VNImageRequestHandler(url: path).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                let digits = text.filter(\.isNumber)
                print("Clock captions:", text)
                #expect(digits.contains("0607") && digits.contains("1707"))
                #expect(!text.contains("10月30") && !text.contains("Oct 30"))
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_LAYOUT_UI"] == "1"))
    func countdownKeepsGeometryStableAndBrandFooterStayPinned() throws {
        let app = NSApplication.shared; app.finishLaunching()
        let suite = "Auralim.PinnedSettings.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.set("Asia/Shanghai", forKey: "city"); store.set(37, forKey: "sunriseOffset"); store.set(-42, forKey: "offset")
        let model = AppModel(defaults: store, controller: LayoutRefinementAppearance(),
            clock: { ISO8601DateFormatter().date(from: "2026-10-30T04:00:00Z")! }, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(), systemSettings: { .init(mode: .light, appearance: .light) })
        let updater = UpdateController(preferences: store)
        let presenter = SettingsWindowController(); presenter.show(model: model, updater: updater)
        let window = try #require(presenter.window), host = try #require(window.contentView)
        defer { window.close(); model.shutdown(); store.removePersistentDomain(forName: suite) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
        settle()
        let scroll = try #require(views(host).compactMap { $0 as? NSScrollView }.first)
        let document = try #require(scroll.documentView)
        let switches = views(host).compactMap { $0 as? NSSwitch }
        let countdown = try #require(switches.dropFirst().first)
        let slider = try #require(views(host).compactMap { $0 as? NSSlider }.first)
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_LAYOUT_OUTPUT"]!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ name: String) throws -> NSBitmapImageRep {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent(name + ".png"))
            return bitmap
        }
        func strip(_ bitmap: NSBitmapImageRep, top: Bool) throws -> Data {
            let image = try #require(bitmap.cgImage)
            let crop = try #require(image.cropping(to: CGRect(x: 24, y: top ? 0 : bitmap.pixelsHigh - 30, width: bitmap.pixelsWide - 60, height: top ? 64 : 30)))
            let rep = NSBitmapImageRep(cgImage: crop)
            let bytes = try #require(rep.bitmapData)
            return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
        }
        func scrollTo(_ bottom: Bool) {
            let end = max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom == document.isFlipped ? end : 0))
            scroll.reflectScrolledClipView(scroll.contentView); settle()
        }
        for language in [AppLanguage.simplifiedChinese, .english] {
            model.language = language
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: theme); scrollTo(false)
                let suffix = "\(language.rawValue)-\(theme == .aqua ? "light" : "dark")"
                let animation = try #require(switches.first)
                #expect(abs(animation.convert(animation.bounds, to: host).maxX - countdown.convert(countdown.bounds, to: host).maxX) < 0.5)
                let initialY = slider.convert(slider.bounds, to: document).minY
                let initialHeight = document.bounds.height
                let initialScroll = scroll.contentView.bounds.origin
                #expect(!model.countdownEnabled)
                let off = try capture("off-" + suffix)
                for _ in 0..<3 {
                    _ = countdown.accessibilityPerformPress(); settle()
                    #expect(model.countdownEnabled)
                    #expect(views(host).compactMap { $0 as? NSTextField }.filter(\.isEditable).count == 3)
                    #expect(abs(document.bounds.height - initialHeight) < 0.5)
                    #expect(abs(slider.convert(slider.bounds, to: document).minY - initialY) < 0.5)
                    #expect(scroll.contentView.bounds.origin == initialScroll)
                    _ = countdown.accessibilityPerformPress(); settle()
                    #expect(!model.countdownEnabled)
                    #expect(views(host).compactMap { $0 as? NSTextField }.filter(\.isEditable).count == 2)
                    #expect(abs(document.bounds.height - initialHeight) < 0.5)
                }
                _ = countdown.accessibilityPerformPress(); settle()
                _ = try capture("on-" + suffix)
                _ = countdown.accessibilityPerformPress(); settle()
                scrollTo(true)
                #expect(scroll.contentView.bounds.origin != initialScroll)
                let bottom = try capture("bottom-" + suffix)
                #expect(try strip(off, top: true) == strip(bottom, top: true))
                #expect(try strip(off, top: false) == strip(bottom, top: false))
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_LAYOUT_UI"] == "1"))
    func blankClicksCommitAllThreeFieldsAndKeepReturnAndTab() async throws {
        let app = NSApplication.shared; app.finishLaunching()
        _ = app.setActivationPolicy(.accessory)
        let suite = "Auralim.SettingsFocus.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.set(true, forKey: "countdownEnabled")
        let model = AppModel(defaults: store, controller: LayoutRefinementAppearance(), enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(), systemSettings: { .init(mode: .light, appearance: .light) })
        let presenter = SettingsWindowController(); presenter.show(model: model)
        let window = try #require(presenter.window), host = try #require(window.contentView)
        defer {
            window.orderOut(nil)
            model.shutdown(); store.removePersistentDomain(forName: suite)
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.12)) }
        func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
        settle()
        let fields = views(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
        try #require(fields.count == 3)
        func key(_ characters: String, code: UInt16) throws {
            app.sendEvent(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)))
            settle()
        }
        func click(_ point: NSPoint) throws {
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 1, clickCount: 1, pressure: 1))
            }
            // Native text selection tracks until mouse-up inside mouseDown.
            app.postEvent(try event(.leftMouseUp), atStart: true)
            app.sendEvent(try event(.leftMouseDown))
            if let up = app.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                app.sendEvent(up)
            }
            settle()
        }
        func edit(_ field: NSTextField, _ value: String) throws {
            window.makeFirstResponder(field); settle()
            let editor = try #require(field.currentEditor() as? NSTextView)
            editor.selectAll(nil); editor.insertText(value, replacementRange: editor.selectedRange()); settle()
        }
        let readValues = [{ model.countdownSeconds }, { model.sunriseOffset }, { model.offset }]
        for (index, field) in fields.enumerated() {
            try edit(field, String(21 + index))
            // Clicking within the editor must retain focus and the draft.
            try click(field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil))
            try #require(field.currentEditor() != nil)
            // Cover both fixed header space and the scroll-view margin.
            try click(NSPoint(x: index == 1 ? 12 : 570, y: index == 1 ? 300 : host.bounds.height - 35))
            try #require(field.currentEditor() == nil)
            try #require(!(window.firstResponder is NSTextView))
            try #require(readValues[index]() == 21 + index)
            try edit(field, String(31 + index)); try key("\r", code: 36)
            try #require(readValues[index]() == 31 + index)
            try edit(field, String(41 + index)); try key("\t", code: 48)
            try #require(field.currentEditor() == nil)
            try #require(window.firstResponder != nil && window.firstResponder !== window)
            try #require(readValues[index]() == 41 + index)
            window.makeFirstResponder(nil); settle()
        }
        // Existing offset clamping still applies when a blank click commits.
        try edit(fields[1], "999")
        try click(NSPoint(x: 570, y: host.bounds.height - 35))
        try #require(model.sunriseOffset == 120 && fields[1].currentEditor() == nil)
        print("PASS: all three fields committed on blank click, Return and Tab; editing focus and offset limits verified.")
        fflush(stdout)
        await Task.yield()
    }

}
