import AppKit
import AuralimCore
import CoreGraphics

/// Holds only the latest verified wake result. Appearance correction never
/// waits for the desktop; only the optional visual effect is deferred.
@MainActor
final class WakeAppearanceTransition {
    private let desktopReady: @MainActor () -> Bool
    private let play: @MainActor (Appearance) -> Void
    private let delay: TimeInterval
    private var timer: Timer?
    private var beforeSleep: Appearance?
    private var verifiedTarget: Appearance?
    private var sleeping = false
    private var waking = false
    private var suppressed = false
    private var desktopBlocked = false

    init(desktopReady: @escaping @MainActor () -> Bool, delay: TimeInterval,
         play: @escaping @MainActor (Appearance) -> Void) {
        self.desktopReady = desktopReady
        self.delay = delay
        self.play = play
    }

    static func desktopIsReady() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session["CGSSessionScreenIsLocked"] as? Bool != true else { return false }
        return NSScreen.screens.contains { screen in
            guard let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsAsleep(display.uint32Value) == 0
        }
    }

    func willSleep(appearance: Appearance) {
        cancelWake()
        beforeSleep = appearance
        sleeping = true
    }

    func didWake(fallback: Appearance) {
        guard !waking else { desktopChanged(); return }
        beforeSleep = beforeSleep ?? fallback
        sleeping = false
        waking = true
        verifiedTarget = nil
        desktopChanged()
    }

    func desktopUnavailable() {
        desktopBlocked = true
        timer?.invalidate(); timer = nil
    }

    func desktopChanged() {
        desktopBlocked = false
        schedulePlaybackCheck()
    }

    func invalidateVerification() {
        guard waking else { return }
        verifiedTarget = nil
        timer?.invalidate(); timer = nil
    }

    /// Returns true only for ordinary (non-wake) transitions. Wake playback
    /// also covers macOS having already switched before our AppleScript runs.
    func verified(_ target: Appearance, changed: Bool) -> Bool {
        guard !sleeping else { return false }
        guard waking else { return changed }
        verifiedTarget = target
        schedulePlaybackCheck()
        return false
    }

    func suppressAnimation() { suppressed = true }

    func cancelWake() {
        timer?.invalidate(); timer = nil
        desktopBlocked = false
        beforeSleep = nil
        verifiedTarget = nil
        sleeping = false
        waking = false
        suppressed = false
    }

    private func schedulePlaybackCheck() {
        timer?.invalidate(); timer = nil
        guard waking, !sleeping, !desktopBlocked, verifiedTarget != nil else { return }
        // A one-shot settle delay allows WindowServer to reveal the desktop.
        // No polling while locked: unlock/display/session events retry this.
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.desktopSettled() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func desktopSettled() {
        timer = nil
        guard waking, !sleeping, !desktopBlocked, desktopReady(), let target = verifiedTarget else { return }
        let shouldPlay = !suppressed && beforeSleep != target
        cancelWake() // Consume before calling out, so repeated events cannot replay.
        if shouldPlay { play(target) }
    }
}
