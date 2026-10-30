import AppKit
import Combine
import OSLog
import Sparkle

/// Sparkle owns scheduling, validation and installation. Settings retains the
/// restart action; prepared updates may also be installed on normal app quit.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUserDriver, SPUUpdaterDelegate {
    enum Mode: String, CaseIterable { case manual, automatic }
    enum Failure: String { case configuration, network, validation, installation }
    enum State: Equatable {
        case idle, checking, downloading, preparing, upToDate
        case ready(String), installing, available(String), failed(Failure)
    }

    static let releasesURL = URL(string: "https://github.com/frank-yf/auralim-mac/releases/latest")!
    static let feedURL = URL(string: "https://github.com/frank-yf/auralim-mac/releases/latest/download/appcast.xml")!
    @Published private(set) var state: State = .idle
    @Published private(set) var mode: Mode
    private var updater: SPUUpdater?
    private var installAction: (() -> Void)?
    private var installationRequested = false
    private var explicitCheck = false
    private var updateVersion = ""
    private let preferences: UserDefaults
    private let hostBundle: Bundle
    private let openURL: (URL) -> Bool
    private let logger = Logger(subsystem: "app.duskshift.mac", category: "updates")

    init(hostBundle: Bundle = .main, preferences: UserDefaults? = nil, openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.preferences = preferences ?? hostBundle.bundleIdentifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        let automatic = self.preferences.object(forKey: "SUEnableAutomaticChecks") as? Bool
            ?? hostBundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool ?? false
        mode = automatic ? .automatic : .manual
        self.hostBundle = hostBundle
        self.openURL = openURL
        super.init()
    }

    func start() {
        guard updater == nil else { return }
        let updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: self, delegate: self)
        self.updater = updater
        mode = updater.automaticallyChecksForUpdates ? .automatic : .manual
        do { try updater.start() }
        catch { report(error, fallback: .configuration) }
    }

    func selectMode(_ selection: Mode) {
        guard mode != selection else { return }
        mode = selection
        let automatic = selection == .automatic
        if let updater {
            // Sparkle persists these native preferences and resets its schedule itself.
            updater.automaticallyChecksForUpdates = automatic
            updater.automaticallyDownloadsUpdates = automatic
        } else {
            preferences.set(automatic, forKey: "SUEnableAutomaticChecks")
            preferences.set(automatic, forKey: "SUAutomaticallyUpdate")
        }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if mode == .manual && updateCheck != .updates {
            throw NSError(domain: "app.duskshift.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Automatic updates are disabled."])
        }
    }

    var canCheck: Bool {
        switch state {
        case .idle, .upToDate, .failed, .available: return true
        default: return false
        }
    }

    func checkForUpdates() {
        guard canCheck else { return }
        guard let updater, updater.canCheckForUpdates else { return }
        explicitCheck = true
        state = .checking
        updater.checkForUpdates()
    }

    func restartToUpdate() {
        guard case .ready = state, let action = installAction else { return }
        installAction = nil
        installationRequested = true
        state = .installing
        action()
    }

    func openReleases() { _ = openURL(Self.releasesURL) }

    private func ready(version: String, install: @escaping () -> Void) {
        updateVersion = version
        installAction = install
        state = .ready(version)
    }

    private func report(_ error: Error, fallback: Failure = .network) {
        let error = error as NSError
        logger.error("Update failed: domain=\(error.domain, privacy: .public) code=\(error.code)")
        installAction = nil
        installationRequested = false
        var failure = fallback
        // Feed/download errors may wrap the actual signature validation error.
        var cause: NSError? = error
        var depth = 0
        while let current = cause, depth < 8 {
            if current.domain == SUSparkleErrorDomain {
                switch current.code {
                case 3000..<4000: failure = .validation
                case 4000..<5000: if failure != .validation { failure = .installation }
                case 0..<1000: if failure == fallback { failure = .configuration }
                default: break
                }
            }
            cause = current.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        state = .failed(failure)
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        updateVersion = item.displayVersionString
        state = .downloading
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) { state = .preparing }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        ready(version: item.displayVersionString, install: immediateInstallHandler)
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain && nsError.code == Int(SUError.noUpdateError.rawValue) {
            if explicitCheck { state = .upToDate }
        } else { report(error) }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        explicitCheck = false
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }

    func show(_ request: SPUUpdatePermissionRequest,
                                     reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: mode == .automatic, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { explicitCheck = true; state = .checking }

    func showUpdateFound(with appcastItem: SUAppcastItem, state updateState: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        updateVersion = appcastItem.displayVersionString
        if appcastItem.signingValidationStatus == .failed {
            installAction = nil
            state = .failed(.validation)
            reply(.dismiss)
        } else if mode == .manual && !explicitCheck {
            state = .available(updateVersion)
            reply(.dismiss)
        } else if appcastItem.isInformationOnlyUpdate {
            state = .available(updateVersion)
            reply(.dismiss)
        } else if installationRequested {
            reply(.install)
        } else if updateState.stage == .downloaded || updateState.stage == .installing {
            ready(version: updateVersion) { reply(.install) }
        } else {
            state = .downloading
            reply(.install)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        state = .upToDate
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        report(error)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) { state = .downloading }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { state = .preparing }
    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if installationRequested { reply(.install) }
        else { ready(version: updateVersion) { reply(.install) } }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        if !applicationTerminated {
            ready(version: updateVersion, install: retryTerminatingApplication)
        }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        installAction = nil
        state = .idle
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        if case .failed = state { return }
        if case .upToDate = state { return }
        if case .available = state { return }
        if case .ready = state { return }
        installAction = nil
        installationRequested = false
        state = .idle
    }
}
