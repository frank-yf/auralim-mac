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
        return buttons.firstIndex(where: { (read($0, kAXValueAttribute) as? NSNumber)?.boolValue == true }) ?? -1
    }
    func confirmed() -> Bool {
        descendants(settings).contains {
            guard let value = read($0, kAXValueAttribute) as? String else { return false }
            return ["应用自动 ·", "应用手动 ·", "應用自動 ·", "應用手動 ·", "App Auto ·", "App manual ·"].contains { value.contains($0) }
        }
    }
    let original = try selected(settings, "settings-appearance-mode")
    try require(try selected(menu(), "menu-appearance-mode") == original, "Initial menu/settings mismatch")
    let statusTexts = descendants(settings).compactMap { read($0, kAXValueAttribute) as? String }
    let modeStatus = statusTexts.first { text in
        ["系统自动 ·", "系统管理 ·", "应用自动 ·", "应用手动 ·", "系統自動 ·", "系統管理 ·", "應用自動 ·", "應用手動 ·", "System Auto ·", "System managed ·", "App Auto ·", "App manual ·"].contains { text.contains($0) }
    }
    try require(modeStatus != nil, "No explicit system/app ownership status")
    print("Both actual panels expose Light / Auto / Dark; initial selected index:", original, "(-1 = system-managed empty selection)")
    print("Verified ownership status:", modeStatus!)
    guard CommandLine.arguments.contains("--apply") else { return }
    // A stored manual value may be stale after startup. Only mutate when the
    // displayed status confirms an explicit app-owned mode we can restore.
    try require(original >= 0 && confirmed(), "System-managed state: use read-only verification")
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
    let verifyAnimations = CommandLine.arguments.contains("--animations")
    // Nonactivating, click-through panels are not consistently included in
    // AXWindows. Inspect only this process's visible Core Graphics windows.
    func transition() -> [String: Any]? {
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.first { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == running.processIdentifier,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return false }
            return (bounds["Width"] as? NSNumber)?.intValue == 280 && (bounds["Height"] as? NSNumber)?.intValue == 184
        }
    }
    for (index, fromMenu) in [(2, true), (0, false), (1, true)] {
        let wasDark = try systemIsDark()
        if fromMenu { try press(options(menu(), "menu-appearance-mode")[index]) }
        else { try chooseSettings(index) }
        var observedAnimation = verifyAnimations ? transition() : nil
        let deadline = Date(timeIntervalSinceNow: 12)
        var matched = false
        repeat {
            if verifyAnimations, observedAnimation == nil { observedAnimation = transition() }
            let settingsMatch = try selected(settings, "settings-appearance-mode") == index
            let appearanceMatches = try index == 1 || systemIsDark() == (index == 2)
            if settingsMatch && appearanceMatches && confirmed() { matched = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        try require(matched, "Mode or actual system appearance did not match index \(index)")
        if verifyAnimations {
            let dark = try systemIsDark()
            if wasDark != dark {
                guard let panel = observedAnimation ?? transition() else { throw VerificationFailure(message: "Missing actual appearance animation") }
                let title = panel[kCGWindowName as String] as? String ?? ""
                let expected = dark ? ["日落", "Sunset"] : ["日出", "Sunrise"]
                try require(expected.contains { title.contains($0) }, "Wrong animation direction: \(title)")
                if let focused = read(app, kAXFocusedWindowAttribute) {
                    try require(width(focused as! AXUIElement) != 280, "Animation took keyboard focus")
                }
                print("Verified actual animation:", title)
            } else {
                try require(observedAnimation == nil && transition() == nil, "Unchanged appearance replayed an animation")
            }
            let end = Date(timeIntervalSinceNow: 2)
            while transition() != nil && Date() < end { Thread.sleep(forTimeInterval: 0.1) }
            try require(transition() == nil, "Animation window did not close")
        }
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
