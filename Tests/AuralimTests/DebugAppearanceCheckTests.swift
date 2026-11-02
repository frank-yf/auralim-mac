import AppKit
import SwiftUI
import AuralimCore
import Testing
@testable import Auralim

private final class DiagnosticReader: AppearanceReadinessChecking {
    var callbacks: [(Result<Appearance, AppearanceFailure>) -> Void] = []
    var cancellations = 0
    func readAppearance(completion: @escaping (Result<Appearance, AppearanceFailure>) -> Void) { callbacks.append(completion) }
    func cancel() { cancellations += 1 }
}
private final class DiagnosticWriter: AppearanceApplying {
    var writes: [Appearance] = []
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        writes.append(appearance); completion(.success(.init(changed: true)))
    }
}

@MainActor
@Suite(.serialized)
struct DebugAppearanceCheckTests {
    @Test func buildAndUserOptInGateTheReader() {
        let reader = DiagnosticReader(), check = DebugAppearanceCheckController(checker: DiagnosticReader())
        check.run(enabled: false)
        #expect(!check.isChecking)
        let subject = DebugAppearanceCheckController(checker: reader)
        subject.run(enabled: true)
        #expect(reader.callbacks.count == (BuildFeatures.debugToolsEnabled ? 1 : 0))
        subject.cancel()
    }

    @Test(.enabled(if: BuildFeatures.debugToolsEnabled))
    func successFailureAndRetryOnlyRead() {
        let reader = DiagnosticReader(), localizer = Localizer(language: .simplifiedChinese)
        let check = DebugAppearanceCheckController(checker: reader)
        check.run(enabled: true); check.run(enabled: true)
        #expect(reader.callbacks.count == 1 && check.isChecking)
        reader.callbacks[0](.success(.dark))
        #expect(!check.isChecking && check.status(localizer: localizer) == "当前系统外观：深色")
        check.run(enabled: true)
        reader.callbacks[1](.failure(.init(message: "", permissionDenied: true, reason: .authorization)))
        #expect(check.failed && check.status(localizer: localizer) == localizer.text("error.permission"))
        check.run(enabled: true)
        reader.callbacks[2](.failure(.init(message: "Timed out", permissionDenied: false, reason: .script(-1712))))
        #expect(check.failed && check.status(localizer: localizer) == localizer.text("debug.check.failure", -1712, "Timed out"))
        check.run(enabled: true); reader.callbacks[3](.success(.light))
        #expect(!check.failed && check.status(localizer: localizer) == "当前系统外观：浅色")
    }

    @Test(.enabled(if: BuildFeatures.debugToolsEnabled))
    func cancellationAndReplacementIgnoreStaleResults() {
        let reader = DiagnosticReader(), check = DebugAppearanceCheckController(checker: DiagnosticReader())
        check.cancel(); #expect(!check.isChecking)
        let subject = DebugAppearanceCheckController(checker: reader)
        subject.run(enabled: true); subject.cancel(); subject.cancel()
        #expect(reader.cancellations == 1)
        subject.run(enabled: true); reader.callbacks[0](.success(.light))
        #expect(subject.isChecking)
        reader.callbacks[1](.success(.dark))
        #expect(subject.status(localizer: Localizer(language: .english)) == "System appearance: Dark")
        subject.cancel(clearResult: true)
        if case .idle = subject.state {} else { Issue.record("Expected cleared diagnostic result") }
    }

    @Test(.enabled(if: BuildFeatures.debugToolsEnabled))
    func nativeCheckCancelRetryAndDisableNeverApplyAppearance() throws {
        guard ProcessInfo.processInfo.environment["AURALIM_DEBUG_UI_TESTS"] == "1" else { return }
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.finishLaunching()
        let suite = "Auralim.ReadOnly.\(UUID().uuidString)", reader = DiagnosticReader(), writer = DiagnosticWriter()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("zh-Hans", forKey: "language"); defaults.set("Asia/Shanghai", forKey: "city")
        let check = DebugAppearanceCheckController(checker: reader)
        let preview = DebugPreviewController(defaults: defaults)
        preview.enabled = true; preview.applyAppearanceAfterPreview = true
        let model = AppModel(defaults: defaults, controller: writer, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { .init(mode: .light, appearance: .light) }, desktopReady: { true },
            debugPreview: preview, debugAppearanceCheck: check)
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        let window = NSWindow(contentViewController: NSHostingController(rootView: DebugSettingsView(model: model, preview: preview)
            .padding(16).frame(width: 580, height: 460, alignment: .topLeading)))
        window.isReleasedWhenClosed = false; window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { window.close() }
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15)) }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func clickCheck() throws {
            settle()
            let content = try #require(window.contentView)
            // The read-only action is the bottom bordered focus host, after the preview grid.
            let button = try #require(views(content).filter { String(describing: Swift.type(of: $0)) == "_FocusRingView" }
                .min { $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil).y < $1.convert(NSPoint(x: $1.bounds.midX, y: $1.bounds.midY), to: nil).y })
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                app.sendEvent(event)
            }
            settle()
        }
        let original = model.currentSystemAppearance
        try clickCheck(); try #require(check.isChecking && reader.callbacks.count == 1)
        try clickCheck(); #expect(!check.isChecking && reader.cancellations == 1)
        reader.callbacks[0](.success(.dark)); #expect(!check.isChecking)
        try clickCheck(); try #require(reader.callbacks.count == 2); reader.callbacks[1](.failure(.init(message: "Timed out", permissionDenied: false, reason: .script(-1712))))
        settle(); #expect(check.failed)
        try clickCheck(); try #require(reader.callbacks.count == 3); reader.callbacks[2](.success(.dark)); settle()
        #expect(check.status(localizer: model.localizer) == "当前系统外观：深色")
        #expect(writer.writes.isEmpty && model.currentSystemAppearance == original && preview.phase == .idle)
        let output = URL(fileURLWithPath: "artifacts/debug-read-only")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent("check-success.png").path]
        try capture.run(); capture.waitUntilExit(); #expect(capture.terminationStatus == 0)
        try clickCheck()
        let content = try #require(window.contentView)
        let toggle = try #require(views(content).compactMap { $0 as? NSSwitch }.first)
        _ = toggle.accessibilityPerformPress(); settle()
        #expect(!preview.enabled && !check.isChecking && reader.cancellations == 2)
        try #require(reader.callbacks.count == 4)
        reader.callbacks[3](.success(.dark)); #expect(!check.isChecking && writer.writes.isEmpty)
        preview.enabled = true; check.run(enabled: true); model.shutdown()
        #expect(!check.isChecking && reader.cancellations == 3 && writer.writes.isEmpty)
    }
}
