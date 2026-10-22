import Testing
import AppKit
import SwiftUI
import Vision
@testable import DuskShift
import DuskShiftCore

private final class NativeAppearanceSpy: AppearanceApplying {
    var requests = 0
    func apply(_ appearance: Appearance, completion: @escaping (Result<Void, AppearanceFailure>) -> Void) {
        requests += 1
        completion(.success(()))
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
        let model = AppModel(defaults: defaults, controller: appearance, enableTimers: false)
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
        // SwiftUI's native focus-ring hosts are observed in this platform's view
        // hierarchy. The first two right-aligned hosts are the two reset buttons.
        let resets = Array(descendants(host).filter {
            String(describing: Swift.type(of: $0)) == "_FocusRingView" && $0.frame.minX > 300
        }.prefix(2))
        try #require(resets.count == 2)
        for (index, button) in resets.enumerated() {
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            let sliderPoint = sliders[index].convert(NSPoint(x: 0, y: sliders[index].bounds.midY), to: nil)
            try #require(point.y > sliderPoint.y && point.y < sliderPoint.y + 80)
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
        print("Verified settings window reuse and shared model; four drag directions, input, blur, reset, and displayed switch times")
    }
}
