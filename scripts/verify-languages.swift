import AppKit
import ApplicationServices

func read(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}
func children(_ element: AXUIElement) -> [AXUIElement] {
    read(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}
func describe(_ element: AXUIElement, depth: Int = 0) {
    guard depth < 6 else { return }
    let role = read(element, kAXRoleAttribute as CFString) as? String ?? ""
    let title = read(element, kAXTitleAttribute as CFString) as? String ?? ""
    let description = read(element, kAXDescriptionAttribute as CFString) as? String ?? ""
    print(String(repeating: " ", count: depth), role, title, description)
    for child in children(element) { describe(child, depth: depth + 1) }
}
guard AXIsProcessTrusted() else { fatalError("Menu-bar verification requires Accessibility permission") }
guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: "app.duskshift.mac").first else {
    fatalError("Auralim is not running")
}
let app = AXUIElementCreateApplication(running.processIdentifier)
print("Auralim pid:", running.processIdentifier)
let verify = CommandLine.arguments.contains("--verify")
let settingsMode = CommandLine.arguments.contains("--settings")
let brandOnly = CommandLine.arguments.contains("--brand-only")
func appWindows() -> [AXUIElement] {
    read(app, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
}
func pressStatusItem() {
    guard let extra = read(app, kAXExtrasMenuBarAttribute as CFString),
          let item = children(extra as! AXUIElement).first else { fatalError("No Auralim status item") }
    precondition(AXUIElementPerformAction(item, kAXPressAction as CFString) == .success)
    Thread.sleep(forTimeInterval: 0.5)
}
func size(_ element: AXUIElement) -> CGSize {
    guard let raw = read(element, kAXSizeAttribute as CFString) else { fatalError("No AXSize") }
    var result = CGSize.zero
    precondition(AXValueGetValue(raw as! AXValue, .cgSize, &result))
    return result
}
func descendants(_ element: AXUIElement) -> [AXUIElement] {
    [element] + children(element).flatMap(descendants)
}
func panelWindows() -> [AXUIElement] {
    appWindows().filter { (300...340).contains(size($0).width) }
}
func label(_ element: AXUIElement) -> String {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap {
        read(element, $0 as CFString) as? String
    }.first { !$0.isEmpty } ?? ""
}
func press(_ element: AXUIElement) {
    precondition(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success)
    Thread.sleep(forTimeInterval: 0.5)
}
func openSettings() -> AXUIElement {
    if panelWindows().isEmpty { pressStatusItem() }
    guard let panel = panelWindows().first,
          let button = descendants(panel).first(where: { ["设置", "設定", "Settings"].contains(label($0)) }) else {
        fatalError("No settings entry in menu panel")
    }
    press(button)
    guard let settings = appWindows().first(where: { ["晨昏设置", "晨昏設定", "Auralim Settings"].contains(label($0)) }) else {
        fatalError("Settings window did not open")
    }
    precondition(panelWindows().isEmpty, "Menu panel should dismiss when opening settings")
    return settings
}

struct VerificationError: Error { let message: String }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw VerificationError(message: message) }
}
func role(_ element: AXUIElement) -> String { read(element, kAXRoleAttribute as CFString) as? String ?? "" }
let settings = openSettings()
func languagePicker() throws -> AXUIElement {
    let pickers = descendants(settings).filter { role($0) == "AXPopUpButton" }
    try require(pickers.count == 2, "Expected language and city pickers")
    guard let language = pickers.first(where: { read($0, kAXIdentifierAttribute as CFString) as? String == "language-picker" }) else {
        throw VerificationError(message: "Missing language picker identifier")
    }
    return language
}
func choose(_ title: String) throws {
    _ = AXUIElementPerformAction(settings, kAXRaiseAction as CFString)
    let picker = try languagePicker()
    press(picker)
    let items = descendants(picker).filter { role($0) == "AXMenuItem" }
    guard let item = items.first(where: { label($0) == title }) else {
        throw VerificationError(message: "No language option \(title); options: \(items.map(label))")
    }
    press(item)
}
func screenshot(_ path: String, width: Double) throws {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let info = windows.first(where: {
        guard $0[kCGWindowOwnerPID as String] as? Int32 == running.processIdentifier,
              let bounds = $0[kCGWindowBounds as String] as? [String: Double] else { return false }
        return abs(bounds["Width", default: 0] - width) < 2
    }), let number = info[kCGWindowNumber as String] as? Int else {
        throw VerificationError(message: "No matching window for screenshot")
    }
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-l", String(number), path]
    try capture.run(); capture.waitUntilExit()
    try require(capture.terminationStatus == 0, "Screenshot failed")
}
do {
    if brandOnly {
        guard let url = running.bundleURL, let bundle = Bundle(url: url) else { throw VerificationError(message: "No running app bundle") }
        try require(url.lastPathComponent == "Auralim.app", "Unexpected app package name")
        try require(bundle.infoDictionary?["CFBundleShortVersionString"] as? String == "0.3.1", "Wrong app version")
        try require(bundle.infoDictionary?["CFBundleVersion"] as? String == "26", "Wrong build number")
        try require(bundle.infoDictionary?["CFBundleName"] as? String == "Auralim", "Wrong fallback name")
        for (language, expected) in [("en", "Auralim"), ("zh-Hans", "晨昏"), ("zh-Hant", "晨昏")] {
            let file = url.appendingPathComponent("Contents/Resources/\(language).lproj/InfoPlist.strings")
            let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: String]
            try require(values?["CFBundleName"] == expected && values?["CFBundleDisplayName"] == expected, "Wrong localized bundle name: \(language)")
            print("Verified packaged names:", language, expected)
        }
        try require(bundle.executableURL?.lastPathComponent == "Auralim", "Wrong executable name")
        for name in ["Auralim_Auralim", "Auralim_AuralimCore"] {
            try require(bundle.url(forResource: name, withExtension: "bundle") != nil, "Missing renamed resources: \(name)")
        }
        try require(!FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/MacOS/DuskShift").path), "Obsolete executable remains")
        print("System process name:", running.localizedName ?? "", "; file display name:", FileManager.default.displayName(atPath: url.path))
    }
    let original = read(try languagePicker(), kAXValueAttribute as CFString) as? String ?? ""
    print("Original language choice:", original)
    defer {
        let systemOptions = ["跟随系统", "跟隨系統", "Follow System", ""]
        let restore = systemOptions.contains(original) ? "跟随系统" : original
        do { try choose("简体中文"); try choose(restore); print("Restored original language choice:", original) }
        catch { print("Could not restore language:", error) }
    }
    for (option, expectedTitle, nextLabel) in [
        ("English", "Auralim Settings", "Schedule preview"),
        ("繁體中文", "晨昏設定", "計畫預覽"),
        ("简体中文", "晨昏设置", "计划预览")
    ] {
        try choose(option)
        try require(label(settings) == expectedTitle, "Window title did not update: \(label(settings))")
        if brandOnly {
            let name = option == "English" ? "Auralim" : "晨昏"
            func identifiedText(_ window: AXUIElement, _ id: String) -> String? {
                descendants(window).first { read($0, kAXIdentifierAttribute as CFString) as? String == id }.map(label)
            }
            try require(identifiedText(settings, "settings-app-name") == name, "Settings app name did not update")
            try require(identifiedText(settings, "app-version") == name + " 0.3.1", "Settings version did not update")
            let slogan = option == "English" ? "Between light and dark." : "日升而明，日落而暗"
            try require(identifiedText(settings, "app-slogan") == slogan, "Settings slogan did not update")
            let filename = option == "English" ? "en" : option == "繁體中文" ? "zh-Hant" : "zh-Hans"
            try FileManager.default.createDirectory(atPath: "artifacts/branding-0.3.1", withIntermediateDirectories: true)
            try screenshot("artifacts/branding-0.3.1/settings-\(filename).png", width: 600)
            pressStatusItem()
            guard let panel = panelWindows().first else { throw VerificationError(message: "No compact menu") }
            try require(identifiedText(panel, "menu-app-name") == name, "Menu app name did not update")
            try screenshot("artifacts/branding-0.3.1/menu-\(filename).png", width: 320)
            pressStatusItem()
            print("Verified app name and 0.3.1 version:", option, name, expectedTitle)
            continue
        }
        let generalElements = descendants(settings)
        let values = generalElements.map(label).joined(separator: " ")
        let expectedSwitch = option == "English" ? "Switch to light" : option == "繁體中文" ? "日出轉亮" : "日出转亮"
        try require(values.contains(expectedSwitch), "Settings labels did not update")
        let filename = option == "English" ? "en" : option == "繁體中文" ? "zh-Hant" : "zh-Hans"
        try screenshot("artifacts/settings-\(filename).png", width: 600)
        pressStatusItem()
        let panel = try { () throws -> AXUIElement in
            guard let panel = panelWindows().first else { throw VerificationError(message: "No compact menu") }
            return panel
        }()
        let menuText = descendants(panel).map(label).joined(separator: " ")
        try require(menuText.contains(nextLabel) || menuText.contains(option == "English" ? "Next switch" : option == "繁體中文" ? "下次切換" : "下次切换"), "Menu did not update")
        if option == "English" { try screenshot("artifacts/menu-bar-en.png", width: 320) }
        pressStatusItem()
        try require(!descendants(settings).contains { ["Help", "使用说明", "使用說明"].contains(label($0)) }, "Unexpected instructions tab")
        print("Verified live language choice:", option, "title, streamlined settings, menu, and city/date presentation")
    }
} catch {
    fputs("Language verification failed: \(error)\n", stderr)
    exit(1)
}
