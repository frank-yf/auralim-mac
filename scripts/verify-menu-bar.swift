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
if verify {
    if !appWindows().isEmpty { pressStatusItem() }
    for cycle in 1...3 {
        pressStatusItem()
        guard let panel = appWindows().first else { fatalError("Panel did not open") }
        let measured = size(panel)
        precondition((380...410).contains(measured.width) && (280...760).contains(measured.height), "Collapsed panel: \(measured)")
        let elements = descendants(panel)
        let sliders = elements.filter { read($0, kAXRoleAttribute as CFString) as? String == "AXSlider" }
        let inputs = elements.filter { read($0, kAXRoleAttribute as CFString) as? String == "AXTextField" }
        let text = elements.compactMap { read($0, kAXValueAttribute as CFString) as? String }.joined(separator: " ")
        precondition(sliders.count == 2 && inputs.count == 2)
        precondition(text.contains("日出转亮") && text.contains("日落转暗"))
        print("Open cycle \(cycle): \(measured.width) × \(measured.height); two sliders, two inputs, both switch-time labels present")
        if cycle < 3 { pressStatusItem() }
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
       let bounds = window[kCGWindowBounds as String] as? [String: Double], bounds["Width", default: 0] >= 380,
       bounds["Height", default: 0] >= 280 {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(number), CommandLine.arguments[index + 1]]
        try capture.run(); capture.waitUntilExit()
        precondition(capture.terminationStatus == 0)
        print("Actual menu-bar panel screenshot:", CommandLine.arguments[index + 1])
    }
}
