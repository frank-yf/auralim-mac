import AppKit
import ApplicationServices
setbuf(stdout, nil)

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
    guard let settings = appWindows().first(where: { ["晦明设置", "晦明設定", "Auralim Settings"].contains(label($0)) }) else {
        fatalError("Settings window did not open")
    }
    precondition(panelWindows().isEmpty, "Menu panel should dismiss when opening settings")
    return settings
}
var settings = openSettings()
if let general = descendants(settings).first(where: { ["自动切换", "自動切換", "Automatic switching"].contains(label($0)) }) { press(general) }
func identified(_ identifier: String) -> AXUIElement? {
    descendants(settings).first { read($0, kAXIdentifierAttribute as CFString) as? String == identifier }
}
guard let toggle = identified("launch-at-login") else {
    describe(settings)
    fatalError("No login item toggle")
}
func isOn() -> Bool { (read(toggle, kAXValueAttribute as CFString) as? NSNumber)?.boolValue ?? false }
func statusText() -> String { identified("login-item-status").map(label) ?? (isOn() ? "Switch is enabled" : "Switch is off") }
let original = isOn()
print("Original launch-at-login:", original, "status:", statusText())
// Always restore the original system registration, including if verification throws.
defer {
    if isOn() != original { press(toggle) }
    print("Restored launch-at-login:", isOn(), "status:", statusText())
}
func verify(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "Auralim.LoginVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
let before = descendants(settings).filter { ["AXSlider", "AXTextField"].contains(read($0, kAXRoleAttribute as CFString) as? String ?? "") }.map { String(describing: read($0, kAXValueAttribute as CFString)) }
press(toggle)
print("After first press:", isOn(), "status:", statusText())
try verify(isOn() != original, "Actual login item status did not follow the switch")
if isOn() {
    try verify(["已启用", "已啟用", "is enabled", "等待", "awaiting"].contains { statusText().contains($0) }, "Expected enabled or pending system status")
} else {
    try verify(["已关闭", "已關閉", "is off"].contains { statusText().contains($0) }, "Expected not registered status")
}
// Reopening settings refreshes SMAppService's status rather than a saved Boolean.
if let close = read(settings, kAXCloseButtonAttribute as CFString) { press(close as! AXUIElement) }
settings = openSettings()
print("After reopening:", isOn(), "status:", statusText())
try verify(isOn() != original, "Registration did not survive closing settings")
press(toggle)
print("After second press:", isOn(), "status:", statusText())
try verify(isOn() == original, "Could not restore original registration")
let after = descendants(settings).filter { ["AXSlider", "AXTextField"].contains(read($0, kAXRoleAttribute as CFString) as? String ?? "") }.map { String(describing: read($0, kAXValueAttribute as CFString)) }
print("Editor AX values before:", before, "after:", after)
try verify(before == after, "Offsets changed with login item switch")
if let scroll = descendants(settings).first(where: { read($0, kAXRoleAttribute as CFString) as? String == "AXScrollBar" }) {
    _ = AXUIElementSetAttributeValue(scroll, kAXValueAttribute as CFString, NSNumber(value: 1))
    Thread.sleep(forTimeInterval: 0.5)
}
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
if let index = CommandLine.arguments.firstIndex(of: "--capture"), index + 1 < CommandLine.arguments.count,
   let ownWindow = windows.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == running.processIdentifier && (($0[kCGWindowBounds as String] as? [String: Double])?["Width"] ?? 0) >= 550 }),
   let number = ownWindow[kCGWindowNumber as String] as? Int {
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-l", String(number), CommandLine.arguments[index + 1]]
    try capture.run(); capture.waitUntilExit()
    try verify(capture.terminationStatus == 0, "Screenshot failed")
}
print("PASS: actual system registration/removal, settings reopen, original state restored, offsets preserved")
