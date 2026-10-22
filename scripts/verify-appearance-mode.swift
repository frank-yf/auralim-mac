import AppKit
import ApplicationServices

struct VerificationFailure: Error { let message: String }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw VerificationFailure(message: message) }
}
func read(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}
func children(_ element: AXUIElement) -> [AXUIElement] { read(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func descendants(_ element: AXUIElement) -> [AXUIElement] { [element] + children(element).flatMap(descendants) }
func role(_ element: AXUIElement) -> String { read(element, kAXRoleAttribute) as? String ?? "" }
func press(_ element: AXUIElement) throws {
    try require(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success, "AXPress failed")
    Thread.sleep(forTimeInterval: 0.35)
}
func width(_ element: AXUIElement) -> CGFloat {
    guard let raw = read(element, kAXSizeAttribute) else { return 0 }
    var size = CGSize.zero
    return AXValueGetValue(raw as! AXValue, .cgSize, &size) ? size.width : 0
}
func systemIsDark() throws -> Bool {
    let process = Process(), output = Pipe(), error = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["read", "-g", "AppleInterfaceStyle"]
    process.standardOutput = output; process.standardError = error
    try process.run(); process.waitUntilExit()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    try require(process.terminationStatus == 0 || detail.contains("does not exist"), "Could not read global appearance")
    return text.lowercased() == "dark"
}

func verify() throws {
    try require(AXIsProcessTrusted(), "Accessibility permission required")
    let running = try { () throws -> NSRunningApplication in
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "app.duskshift.mac").first else {
            throw VerificationFailure(message: "Dusk Shift is not running")
        }
        return app
    }()
    let app = AXUIElementCreateApplication(running.processIdentifier)
    func windows() -> [AXUIElement] { read(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    func menu() throws -> AXUIElement {
        for _ in 0..<3 {
            if let window = windows().first(where: { width($0) == 320 }) { return window }
            guard let raw = read(app, kAXExtrasMenuBarAttribute), let item = children(raw as! AXUIElement).first else {
                throw VerificationFailure(message: "No status item")
            }
            try press(item)
            let deadline = Date(timeIntervalSinceNow: 0.8)
            repeat {
                if let window = windows().first(where: { width($0) == 320 }) { return window }
                Thread.sleep(forTimeInterval: 0.1)
            } while Date() < deadline
        }
        throw VerificationFailure(message: "No menu panel")
    }
    let panel = try menu()
    guard let open = descendants(panel).first(where: { read($0, kAXIdentifierAttribute) as? String == "open-settings" }) else {
        throw VerificationFailure(message: "No settings entry")
    }
    try press(open)
    guard let settings = windows().first(where: { width($0) == 600 }) else { throw VerificationFailure(message: "No settings window") }
    func options(_ window: AXUIElement, _ id: String) throws -> [AXUIElement] {
        guard let group = descendants(window).first(where: { read($0, kAXIdentifierAttribute) as? String == id }) else {
            throw VerificationFailure(message: "No appearance mode picker: \(id)")
        }
        let buttons = descendants(group).filter { ["AXRadioButton", "AXButton"].contains(role($0)) }
        try require(buttons.count == 3, "Expected 3 mode options, got \(buttons.map(role))")
        return buttons
    }
    func selected(_ window: AXUIElement, _ id: String) throws -> Int {
        let buttons = try options(window, id)
        guard let index = buttons.firstIndex(where: { (read($0, kAXValueAttribute) as? NSNumber)?.boolValue == true }) else {
            throw VerificationFailure(message: "No selected mode")
        }
        return index
    }
    func confirmed() -> Bool {
        descendants(settings).contains {
            guard let value = read($0, kAXValueAttribute) as? String else { return false }
            return ["已确认系统为", "已確認系統為", "System appearance confirmed:"].contains { value.contains($0) }
        }
    }
    let original = try selected(settings, "settings-appearance-mode")
    try require(try selected(menu(), "menu-appearance-mode") == original, "Initial menu/settings mismatch")
    print("Both actual panels expose Light / Auto / Dark; initial selected index:", original)
    guard CommandLine.arguments.contains("--apply") else { return }
    let savedManual = UserDefaults(suiteName: "app.duskshift.mac")?.string(forKey: "manualAppearance")
    // Do not turn a legacy paused preference into an explicit manual preference.
    try require(original == 1 || savedManual != nil, "Legacy paused preference: use read-only verification")
    var restored = false
    func chooseSettings(_ index: Int) throws {
        _ = AXUIElementPerformAction(settings, kAXRaiseAction as CFString)
        try press(options(settings, "settings-appearance-mode")[index])
    }
    defer {
        if !restored {
            do { try chooseSettings(original); print("Restored original selected mode:", original) }
            catch { print("RESTORE FAILED:", error) }
        }
    }
    for (index, fromMenu) in [(2, true), (0, false), (1, true)] {
        if fromMenu { try press(options(menu(), "menu-appearance-mode")[index]) }
        else { try chooseSettings(index) }
        let deadline = Date(timeIntervalSinceNow: 12)
        var matched = false
        repeat {
            let settingsMatch = try selected(settings, "settings-appearance-mode") == index
            let appearanceMatches = try index == 1 || systemIsDark() == (index == 2)
            if settingsMatch && appearanceMatches && confirmed() { matched = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        try require(matched, "Mode or actual system appearance did not match index \(index)")
        try require(try selected(menu(), "menu-appearance-mode") == index, "Menu selection did not synchronize")
        print("Verified actual mode:", ["Light", "Auto", "Dark"][index], "from", fromMenu ? "menu" : "settings", "system dark:", try systemIsDark())
    }
    try chooseSettings(original)
    try require(try selected(settings, "settings-appearance-mode") == original, "Restore selection failed")
    let restoreDeadline = Date(timeIntervalSinceNow: 12)
    while !confirmed() && Date() < restoreDeadline { Thread.sleep(forTimeInterval: 0.2) }
    try require(confirmed(), "Original mode not yet confirmed")
    restored = true
    print("Restored original selected mode:", original)
}

do { try verify() }
catch { fputs("Appearance verification failed: \(error)\n", stderr); exit(1) }
