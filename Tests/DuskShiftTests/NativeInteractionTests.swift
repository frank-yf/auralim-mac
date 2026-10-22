import Testing
import AppKit
import SwiftUI
import Vision
@testable import DuskShift
import DuskShiftCore

private final class NativeAppearanceSpy: AppearanceApplying {
    var requests = 0
    var hold = false
    var pending: ((Result<AppearanceApplication, AppearanceFailure>) -> Void)?
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        requests += 1
        if hold { pending = completion } else { completion(.success(AppearanceApplication(changed: false))) }
    }
}

/// Opt-in window-hosted tests: same production SwiftUI controls, real AppKit events.
@Suite(.serialized)
struct NativeInteractionTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DUSK_SHIFT_UI_TESTS"] == "1"))
    func inspectNativeControls() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let suite = "DuskShift.UI.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("zh-Hans", forKey: "language")
        defer { defaults.removePersistentDomain(forName: suite) }
        let previousCursor = CGEvent(source: nil)?.location
        defer { if let point = previousCursor { CGWarpMouseCursorPosition(point) } }
        let appearance = NativeAppearanceSpy()
        let location = FakeLocation()
        let login = FakeLoginItem()
        let model = AppModel(defaults: defaults, controller: appearance, enableTimers: false, loginItemController: login, locationController: location)
        defer { model.shutdown() }
        let presenter = SettingsWindowController()
        presenter.show(model: model)
        let window = try #require(presenter.window)
        let hosting = try #require(window.contentViewController as? NSHostingController<SettingsContent>)
        let host = try #require(hosting.view as? NSHostingView<SettingsContent>)
        defer { window.close() }
        func settle() {
            let deadline = Date(timeIntervalSinceNow: 0.2)
            repeat {
                while Date() < deadline, let event = app.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                    app.sendEvent(event)
                }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            } while Date() < deadline
        }
        settle()
        window.makeKeyAndOrderFront(nil)
        settle()
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let sliders = descendants(host).compactMap { $0 as? NSSlider }
        let fields = descendants(host).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        print("Native controls:", sliders.count, fields.count, "active:", app.isActive, "key:", window.isKeyWindow)
        #expect(sliders.count == 2)
        #expect(fields.count == 2)
        guard sliders.count == 2, fields.count == 2 else { return }
        func type(_ text: String, into field: NSTextField, submit: Bool) throws {
            window.makeFirstResponder(field)
            let editor = try #require(field.currentEditor() as? NSTextView)
            editor.selectAll(nil)
            editor.insertText(text, replacementRange: editor.selectedRange())
            settle()
            if submit {
                let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
                app.sendEvent(enter)
                settle()
            }
        }
        try type("-37", into: fields[0], submit: false)
        #expect(abs(sliders[0].doubleValue - (37.0 + 120) / 240) < 0.0001)
        #expect(model.sunriseOffset == 0)
        try type("-37", into: fields[0], submit: true)
        #expect(model.sunriseOffset == -37)
        #expect(fields[0].stringValue == "-37")
        #expect(abs(sliders[0].doubleValue - (37.0 + 120) / 240) < 0.0001)
        try type("+42", into: fields[1], submit: true)
        #expect(model.offset == 42)
        #expect(abs(sliders[1].doubleValue - (-42.0 + 120) / 240) < 0.0001)
        print("Typed values:", model.sunriseOffset, model.offset)
        window.makeFirstResponder(nil)
        settle()
        try type("0", into: fields[0], submit: true)
        try type("0", into: fields[1], submit: true)
        window.makeFirstResponder(sliders[0])
        func arrow(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            app.sendEvent(event)
            settle()
        }
        try arrow(123)
        #expect(model.sunriseOffset == 1)
        try arrow(124)
        #expect(model.sunriseOffset == 0)
        try arrow(124, modifiers: .option)
        #expect(model.sunriseOffset == -10)
        try type("0", into: fields[0], submit: true)
        print("AX trust:", AXIsProcessTrusted())
        _ = sliders[0].accessibilityPerformDecrement()
        settle()
        print("Sunrise native decrement:", sliders[0].doubleValue, fields[0].stringValue, model.sunriseOffset)
        #expect(model.sunriseOffset > 0)
        #expect(Int(fields[0].stringValue) == model.sunriseOffset)
        _ = sliders[1].accessibilityPerformIncrement()
        settle()
        print("Sunset native increment:", sliders[1].doubleValue, fields[1].stringValue, model.offset)
        #expect(model.offset < 0)
        #expect(Int(fields[1].stringValue) == model.offset)
        func drag(_ slider: NSSlider, fraction: Double) throws {
            try #require(AXIsProcessTrusted(), "Native mouse tests require Accessibility permission")
            let start = slider.convert(NSPoint(x: 10 + (slider.bounds.width - 20) * slider.doubleValue, y: slider.bounds.midY), to: nil)
            let end = slider.convert(NSPoint(x: 10 + (slider.bounds.width - 20) * fraction, y: slider.bounds.midY), to: nil)
            func quartzPoint(_ point: NSPoint) -> CGPoint {
                let screen = window.convertPoint(toScreen: point)
                return CGPoint(x: screen.x, y: NSScreen.screens[0].frame.height - screen.y)
            }
            let from = quartzPoint(start), to = quartzPoint(end)
            DispatchQueue.global().async {
                for (kind, point) in [(CGEventType.leftMouseDown, from), (.leftMouseDragged, to), (.leftMouseUp, to)] {
                    CGEvent(mouseEventSource: nil, mouseType: kind, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }
            settle()
        }
        try drag(sliders[0], fraction: 0.2)
        settle()
        print("Real mouse sunrise:", sliders[0].doubleValue, fields[0].stringValue, model.sunriseOffset)
        #expect(model.sunriseOffset > 20)
        #expect(Int(fields[0].stringValue) == model.sunriseOffset)
        try drag(sliders[1], fraction: 0.8)
        settle()
        print("Real mouse sunset:", sliders[1].doubleValue, fields[1].stringValue, model.offset)
        #expect(model.offset < -20)
        #expect(Int(fields[1].stringValue) == model.offset)
        try drag(sliders[0], fraction: 0.8)
        settle()
        #expect(model.sunriseOffset < -20)
        #expect(Int(fields[0].stringValue) == model.sunriseOffset)
        try drag(sliders[1], fraction: 0.2)
        settle()
        #expect(model.offset > 20)
        #expect(Int(fields[1].stringValue) == model.offset)
        print("Opposite directions:", model.sunriseOffset, model.offset)
        try type("+25", into: fields[0], submit: false)
        let oldSunrise = model.sunriseOffset
        window.makeFirstResponder(fields[1])
        settle()
        #expect(oldSunrise != 25)
        #expect(model.sunriseOffset == 25)
        try type("999", into: fields[0], submit: true)
        #expect(model.sunriseOffset == 120)
        #expect(fields[0].stringValue == "+120")
        #expect(sliders[0].doubleValue == 0)
        try type("abc", into: fields[0], submit: true)
        #expect(model.sunriseOffset == 120)
        #expect(sliders[0].doubleValue == 0)
        try type("-37", into: fields[0], submit: true)
        try type("+42", into: fields[1], submit: true)
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let output = ProcessInfo.processInfo.environment["DUSK_SHIFT_UI_OUTPUT"] ?? "/private/tmp/dusk-shift-window.png"
        capture.arguments = ["-x", "-l", String(window.windowNumber), output]
        try capture.run(); capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        recognition.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(url: URL(fileURLWithPath: output)).perform([recognition])
        let visible = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        print("Visible window text:", visible)
        #expect(visible.contains("日出转亮"))
        #expect(visible.contains("日落转暗"))
        let digits = visible.filter(\.isNumber)
        #expect(digits.contains(model.time(model.schedule?.todayLightTime).filter(\.isNumber)))
        #expect(digits.contains(model.time(model.schedule?.todayDarkTime).filter(\.isNumber)))
        // Locate the right-aligned reset in each slider's header. Other controls
        // can also have native focus-ring hosts; their global ordering is not stable.
        for slider in sliders {
            let sliderPoint = slider.convert(NSPoint(x: 0, y: slider.bounds.midY), to: nil)
            let candidates = descendants(host).filter {
                guard String(describing: Swift.type(of: $0)) == "_FocusRingView" else { return false }
                let point = $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil)
                return point.x > host.bounds.midX && point.y > sliderPoint.y && point.y < sliderPoint.y + 60
            }
            let button = try #require(candidates.first)
            #expect(candidates.count == 1)
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            let screen = window.convertPoint(toScreen: point)
            let quartz = CGPoint(x: screen.x, y: NSScreen.screens[0].frame.height - screen.y)
            DispatchQueue.global().async {
                for kind in [CGEventType.leftMouseDown, .leftMouseUp] {
                    CGEvent(mouseEventSource: nil, mouseType: kind, mouseCursorPosition: quartz, mouseButton: .left)?.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }
            settle()
        }
        #expect(model.sunriseOffset == 0)
        #expect(model.offset == 0)
        #expect(fields.allSatisfy { $0.stringValue == "0" })
        #expect(sliders.allSatisfy { $0.doubleValue == 0.5 })
        // A focused entry point for slider-only changes. Avoid unrelated
        // location, language, window lifecycle and background-check scenarios.
        if ProcessInfo.processInfo.environment["DUSK_SHIFT_SLIDER_TESTS_ONLY"] == "1" {
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: theme)
                for (name, sunrise, sunset) in [("cool", "+72", "-72"), ("warm", "-72", "+72"), ("small", "+10", "-10"), ("neutral", "0", "0")] {
                    try type(sunrise, into: fields[0], submit: true)
                    try type(sunset, into: fields[1], submit: true)
                    window.makeFirstResponder(nil)
                    settle()
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    let file = "slider-\(name)-\(theme == .aqua ? "light" : "dark").png"
                    let destination = URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent(file)
                    process.arguments = ["-x", "-l", String(window.windowNumber), destination.path]
                    try process.run(); process.waitUntilExit()
                    #expect(process.terminationStatus == 0)
                }
            }
            print("Slider-only verification: four drag directions, input synchronization, keyboard/AX, blur, bounds, invalid input, reset, displayed times, light/dark gradient captures")
            return
        }
        window.close()
        model.sunriseOffset = -15
        presenter.show(model: model)
        settle()
        #expect(presenter.window === window)
        #expect(hosting.rootView.model === model)
        #expect(fields[0].stringValue == "-15")
        #expect(Int(fields[1].stringValue) == 0)
        let storedOffset = model.sunriseOffset
        model.enabled = true
        settle()
        let appearanceRequests = appearance.requests
        model.language = .english
        settle()
        #expect(window.title == "Dusk Shift Settings")
        #expect(fields[0].stringValue == "-15")
        #expect(model.sunriseOffset == storedOffset)
        #expect(appearance.requests == appearanceRequests)
        model.language = .traditionalChinese
        settle()
        #expect(window.title == "Dusk Shift 設定")
        #expect(model.t("tab.help") == "使用說明")
        #expect(appearance.requests == appearanceRequests)
        model.language = .simplifiedChinese
        settle()
        #expect(window.title == "Dusk Shift 设置")
        window.makeFirstResponder(fields[0])
        settle()
        let editorBeforeOffset = window.firstResponder
        let scrollView = try #require(sliders[0].enclosingScrollView)
        let scrollBeforeOffset = scrollView.contentView.bounds.origin
        let otherInputBeforeOffset = fields[1].stringValue
        appearance.hold = true
        try type("-5", into: fields[0], submit: true)
        #expect(model.isApplying)
        #expect(sliders.allSatisfy { $0.isEnabled })
        #expect(fields.allSatisfy { $0.isEnabled })
        #expect(window.firstResponder === editorBeforeOffset)
        #expect(scrollView.contentView.bounds.origin == scrollBeforeOffset)
        #expect(fields[1].stringValue == otherInputBeforeOffset)
        #expect(descendants(host).compactMap { $0 as? NSSlider }[1] === sliders[1])
        #expect(descendants(host).compactMap { $0 as? NSTextField }.filter { $0.isEditable }[1] === fields[1])
        appearance.hold = false
        appearance.pending?(.success(AppearanceApplication(changed: false)))
        settle()
        #expect(window.firstResponder === editorBeforeOffset)
        #expect(sliders.allSatisfy { $0.isEnabled })
        try type("\(storedOffset)", into: fields[0], submit: true)
        let mode = try #require(descendants(host).compactMap { $0 as? NSSegmentedControl }.first(where: { $0.segmentCount == 2 }))
        mode.selectedSegment = 1
        #expect(mode.sendAction(mode.action, to: mode.target))
        settle()
        #expect(model.locationMode == .automatic)
        #expect(location.starts == 1)
        location.onEvent?(.resolved(City(id: "current-location", name: "", latitude: 40.7128,
                                       longitude: -74.0060, timeZoneID: "America/New_York")))
        settle()
        #expect(model.cityName() == "当前位置")
        #expect(model.city.timeZoneID == "America/New_York")
        #expect(model.sunriseOffset == storedOffset)
        let locationCapture = Process()
        locationCapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        locationCapture.arguments = ["-x", "-l", String(window.windowNumber),
                                     URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent("settings-location.png").path]
        try locationCapture.run(); locationCapture.waitUntilExit()
        #expect(locationCapture.terminationStatus == 0)
        location.onEvent?(.failed(.denied))
        settle()
        #expect(model.city == model.manualCity)
        #expect(model.locationStatus.contains("上海"))
        mode.selectedSegment = 0
        #expect(mode.sendAction(mode.action, to: mode.target))
        settle()
        #expect(model.locationMode == .manual)
        #expect(location.stops == 1)
        func captureVariant(_ name: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            let destination = URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent(name)
            process.arguments = ["-x", "-l", String(window.windowNumber), destination.path]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        window.appearance = NSAppearance(named: .aqua)
        try type("+120", into: fields[0], submit: true)
        try type("-120", into: fields[1], submit: true)
        window.makeFirstResponder(nil)
        settle()
        try captureVariant("settings-gradient-deeper.png")
        try type("+10", into: fields[0], submit: true)
        try type("-10", into: fields[1], submit: true)
        window.makeFirstResponder(nil)
        settle()
        try captureVariant("settings-gradient-dark-offsets.png")
        window.appearance = NSAppearance(named: .darkAqua)
        settle()
        try captureVariant("settings-gradient-dark-offsets-dark-appearance.png")
        window.appearance = NSAppearance(named: .aqua)
        try type("+5", into: fields[0], submit: true)
        try type("-5", into: fields[1], submit: true)
        window.makeFirstResponder(nil)
        settle()
        try captureVariant("settings-gradient-five-minutes.png")
        try type("-10", into: fields[0], submit: true)
        try type("+10", into: fields[1], submit: true)
        window.makeFirstResponder(nil)
        settle()
        try captureVariant("settings-gradient-small-warm.png")
        window.appearance = NSAppearance(named: .darkAqua)
        settle()
        try captureVariant("settings-gradient-small-warm-dark-appearance.png")
        window.appearance = NSAppearance(named: .aqua)
        try type("-120", into: fields[0], submit: true)
        try type("+120", into: fields[1], submit: true)
        window.makeFirstResponder(nil)
        settle()
        try captureVariant("settings-gradient-lighter.png")
        window.appearance = NSAppearance(named: .darkAqua)
        settle()
        try captureVariant("settings-gradient-dark-appearance.png")
        window.appearance = nil
        print("Verified settings window reuse and shared model; four drag directions, input, blur, reset, and displayed switch times")
        print("Verified native location mode selection, New York time zone, failure fallback, and stopping location in manual mode")
        print("Verified 1-minute keyboard steps, Option 10-minute steps; captured darker/lighter limits and dark appearance without changing system appearance")
        print("Held background appearance check: controls stayed enabled, other slider/input identities and value stayed unchanged; focus and scroll position preserved")
    }
}
