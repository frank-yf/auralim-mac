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
    fatalError("Dusk Shift is not running")
}
let app = AXUIElementCreateApplication(running.processIdentifier)
print("Dusk Shift pid:", running.processIdentifier)
let verify = CommandLine.arguments.contains("--verify")
let settingsMode = CommandLine.arguments.contains("--settings")
func appWindows() -> [AXUIElement] {
    read(app, kAXWindowsAttribute as CFString) as? [AXUIElement] ?? []
}
func pressStatusItem() {
    guard let extra = read(app, kAXExtrasMenuBarAttribute as CFString),
          let item = children(extra as! AXUIElement).first else { fatalError("No Dusk Shift status item") }
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
          let button = descendants(panel).first(where: { ["设置…", "設定…", "Settings…"].contains(label($0)) }) else {
        fatalError("No settings entry in menu panel")
    }
    press(button)
    guard let settings = appWindows().first(where: { ["Dusk Shift 设置", "Dusk Shift 設定", "Dusk Shift Settings"].contains(label($0)) }) else {
        fatalError("Settings window did not open")
    }
    precondition(panelWindows().isEmpty, "Menu panel should dismiss when opening settings")
    return settings
}
if settingsMode {
    let settings = openSettings()
    let measured = size(settings)
    precondition((550...600).contains(measured.width) && measured.height >= 400)
    let elements = descendants(settings)
    precondition(elements.filter { read($0, kAXRoleAttribute as CFString) as? String == "AXSlider" }.count == 2)
    precondition(elements.filter { read($0, kAXRoleAttribute as CFString) as? String == "AXTextField" }.count == 2)
    let labels = elements.map(label).joined(separator: " ")
    precondition((["日出转亮", "日出轉亮", "Switch to light"].contains { labels.contains($0) }) && (["日落转暗", "日落轉暗", "Switch to dark"].contains { labels.contains($0) }))
    print("Settings opened from real status item:", measured, "with city, offsets, and switch times")
    guard let help = elements.first(where: { ["使用说明", "使用說明", "Help"].contains(label($0)) }) else { fatalError("No instructions tab") }
    press(help)
    let helpText = descendants(settings).map(label).joined(separator: " ")
    precondition((["开始使用", "開始使用", "Getting started"].contains { helpText.contains($0) }) && (["权限与隐私", "權限與隱私", "Permissions and privacy"].contains { helpText.contains($0) }))
    print("Instructions tab includes setup, offsets, offline/time-zone behavior, sleep recovery, precision, and privacy")
    guard let close = read(settings, kAXCloseButtonAttribute as CFString) else { fatalError("No close button") }
    press(close as! AXUIElement)
    let reopened = openSettings()
    let matches = appWindows().filter { ["Dusk Shift 设置", "Dusk Shift 設定", "Dusk Shift Settings"].contains(label($0)) }
    precondition(matches.count == 1)
    if let general = descendants(reopened).first(where: { ["自动切换", "自動切換", "Automatic switching"].contains(label($0)) }) { press(general) }
    print("Settings close/reopen: one reusable window; compact menu dismissed")
} else if verify {
    if !panelWindows().isEmpty { pressStatusItem() }
    for cycle in 1...3 {
        pressStatusItem()
        guard let panel = panelWindows().first else { fatalError("Panel did not open") }
        let measured = size(panel)
        precondition((310...330).contains(measured.width) && (230...250).contains(measured.height), "Unexpected panel: \(measured)")
        let elements = descendants(panel)
        let sliders = elements.filter { read($0, kAXRoleAttribute as CFString) as? String == "AXSlider" }
        let inputs = elements.filter { read($0, kAXRoleAttribute as CFString) as? String == "AXTextField" }
        precondition(sliders.isEmpty && inputs.isEmpty)
        precondition(elements.contains { ["设置…", "設定…", "Settings…"].contains(label($0)) })
        print("Open cycle \(cycle): \(measured.width) × \(measured.height); compact status, toggle, settings, quit; no offset editors")
        if cycle < 3 { pressStatusItem(); precondition(panelWindows().isEmpty) }
    }
} else {
    if CommandLine.arguments.contains("--press") { pressStatusItem() }
    if let extra = read(app, kAXExtrasMenuBarAttribute as CFString) { describe(extra as! AXUIElement) }
    for window in appWindows() { print("Panel size:", size(window)); describe(window) }
}
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerPID as String] as? Int32 == running.processIdentifier {
    print("Owned visible window:", window[kCGWindowNumber as String] as Any, window[kCGWindowBounds as String] as Any)
    if let index = CommandLine.arguments.firstIndex(of: "--capture"), index + 1 < CommandLine.arguments.count,
       let number = window[kCGWindowNumber as String] as? Int,
       let bounds = window[kCGWindowBounds as String] as? [String: Double], (settingsMode ? bounds["Width", default: 0] >= 550 : (310...330).contains(bounds["Width", default: 0])),
       bounds["Height", default: 0] >= 230 {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(number), CommandLine.arguments[index + 1]]
        try capture.run(); capture.waitUntilExit()
        precondition(capture.terminationStatus == 0)
        print("Actual application window screenshot:", CommandLine.arguments[index + 1])
    }
}
