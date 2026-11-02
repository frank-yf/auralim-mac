import AppKit
import AuralimCore

/// Independent diagnostic reader: never touches the model's setter, scheduler,
/// animation or countdown. Cancelling it cannot cancel a real appearance switch.
@MainActor
final class DebugAppearanceCheckController: ObservableObject {
    enum State {
        case idle, checking, success(Appearance), failure(AppearanceFailure)
    }
    @Published private(set) var state: State = .idle
    private let checker: AppearanceReadinessChecking
    private var request: UUID?

    init(checker: AppearanceReadinessChecking = AppearanceController()) { self.checker = checker }

    var isChecking: Bool { if case .checking = state { return true }; return false }
    var failed: Bool { if case .failure = state { return true }; return false }

    func run(enabled: Bool) {
        guard BuildFeatures.debugToolsEnabled, enabled, !isChecking else { return }
        let id = UUID()
        request = id; state = .checking
        checker.readAppearance { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, self.request == id else { return }
                self.request = nil
                switch result {
                case .success(let appearance): self.state = .success(appearance)
                case .failure(let error): self.state = .failure(error)
                }
            }
        }
    }

    func cancel(clearResult: Bool = false) {
        let wasChecking = isChecking
        request = nil
        if wasChecking || clearResult { state = .idle }
        if wasChecking { checker.cancel() }
    }

    func status(localizer: Localizer) -> String {
        switch state {
        case .idle: return localizer.text("debug.check.idle")
        case .checking: return localizer.text("debug.check.running")
        case .success(let appearance):
            return localizer.text("debug.check.success", localizer.text(appearance == .light ? "light" : "dark"))
        case .failure(let error):
            switch error.reason {
            case .custom: return error.message
            case .authorization: return localizer.text("error.permission")
            case .verification: return localizer.text("error.verification")
            case .script(let code):
                return localizer.text("debug.check.failure", code, error.message.isEmpty ? localizer.text("error.unknown") : error.message)
            }
        }
    }
}
