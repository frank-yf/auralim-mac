import Foundation
import Testing
import DuskShiftCore
@testable import DuskShift

struct SystemAppearanceSettingsTests {
    @Test func absentAutoPreferenceMeansFixedSystemDefault() {
        #expect(SystemAppearanceSettings(automatic: nil, style: nil, fallback: .dark) == .init(mode: .light, appearance: .light))
        #expect(SystemAppearanceSettings(automatic: nil, style: "Dark", fallback: .light) == .init(mode: .dark, appearance: .dark))
        #expect(SystemAppearanceSettings(automatic: false, style: "Dark", fallback: .light).mode == .dark)
        #expect(SystemAppearanceSettings(automatic: 0, style: nil, fallback: .dark).mode == .light)
    }

    @Test func automaticIsIndependentOfCurrentEffectiveTheme() {
        #expect(SystemAppearanceSettings(automatic: true, style: nil, fallback: .dark) == .init(mode: .automatic, appearance: .light))
        #expect(SystemAppearanceSettings(automatic: 1, style: "Dark", fallback: .light) == .init(mode: .automatic, appearance: .dark))
    }

    @Test func unrecognizedPreferencesNeverGuessASelection() {
        for invalid in ["true" as Any, 2, ["unexpected"]] {
            #expect(SystemAppearanceSettings(automatic: invalid, style: "Dark", fallback: .light).mode == .unknown)
        }
        #expect(SystemAppearanceSettings(automatic: false, style: "future-value", fallback: .dark) == .init(mode: .unknown, appearance: .dark))
    }

    @MainActor
    @Test func actualReadOnlySnapshotMatchesGlobalDefaults() throws {
        func read(_ key: String) throws -> String? {
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["read", "-g", key]
            process.standardOutput = output; process.standardError = errors
            try process.run(); process.waitUntilExit()
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if process.terminationStatus != 0 {
                try #require(detail.contains("does not exist"), "Global preference read failed")
                return nil
            }
            return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let automatic = try read("AppleInterfaceStyleSwitchesAutomatically")
        let style = try read("AppleInterfaceStyle")
        let actual = SystemAppearanceSettings.current()
        let expectedAppearance: Appearance = style == "Dark" ? .dark : .light
        let expectedMode: SystemAppearanceSettings.Mode = automatic == "1" ? .automatic : expectedAppearance == .dark ? .dark : .light
        #expect(actual.mode == expectedMode)
        #expect(actual.appearance == expectedAppearance)
        print("Read-only system preference comparison:", actual.mode, actual.appearance)
    }

}
