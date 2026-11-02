import AppKit
import AuralimCore
import OSLog

/// Reads System Events without changing appearance. Completions arrive on main.
protocol AppearanceReadinessChecking: AnyObject {
    func readAppearance(completion: @escaping (Result<Appearance, AppearanceFailure>) -> Void)
    func cancel()
}

/// One launch, a short settle, and at most three read-only service requests.
/// Desktop notifications resume a paused check; no repeating polling timer.
@MainActor
final class StartupAppearanceReadiness {
    typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Timer
    private let checker: AppearanceReadinessChecking
    private let desktopReady: @MainActor () -> Bool
    private let delays: [TimeInterval]
    private let schedule: Scheduler
    private let completion: @MainActor (Result<Appearance, AppearanceFailure>) -> Void
    private let logger = Logger(subsystem: "app.duskshift.mac", category: "StartupAppearance")
    private var timer: Timer?
    private var operation: UUID?
    private var probing = false
    private var suspended = false
    private var lastFailure: AppearanceFailure?
    private(set) var isPending = true
    private(set) var attempts = 0

    init(checker: AppearanceReadinessChecking, desktopReady: @escaping @MainActor () -> Bool,
         delays: [TimeInterval] = [1, 2, 5],
         schedule: Scheduler? = nil,
         completion: @escaping @MainActor (Result<Appearance, AppearanceFailure>) -> Void) {
        precondition(!delays.isEmpty && delays.allSatisfy { $0 >= 0 && $0.isFinite })
        self.checker = checker; self.desktopReady = desktopReady
        self.delays = delays
        self.schedule = schedule ?? { delay, action in
            let timer = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { action() } }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        }
        self.completion = completion
    }

    func startIfReady() {
        guard isPending, !suspended, operation == nil, desktopReady() else { return }
        guard attempts < delays.count else {
            finish(.failure(lastFailure ?? .init(message: "", permissionDenied: false, reason: .script(-1712))))
            return
        }
        let id = UUID()
        operation = id
        timer = schedule(delays[attempts]) { [weak self] in
            guard let self, self.isPending, self.operation == id else { return }
            self.timer = nil; self.operation = nil
            guard !self.suspended, self.desktopReady() else { return }
            self.probe()
        }
    }

    private func probe() {
        let id = UUID()
        attempts += 1; operation = id; probing = true
        logger.info("Startup appearance probe \(self.attempts) of \(self.delays.count)")
        checker.readAppearance { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, self.isPending, self.operation == id else { return }
                self.operation = nil; self.probing = false
                switch result {
                case .success:
                    self.finish(result)
                case .failure(let error):
                    self.lastFailure = error
                    if error.permissionDenied || self.attempts >= self.delays.count { self.finish(result) }
                    else { self.startIfReady() }
                }
            }
        }
    }

    func desktopUnavailable() {
        guard isPending else { return }
        suspended = true
        stopPending()
    }

    func desktopChanged() {
        suspended = false
        startIfReady()
    }

    func cancel() {
        guard isPending else { return }
        isPending = false
        stopPending()
    }

    private func stopPending() {
        operation = nil // A cancellation may synchronously deliver its old callback.
        timer?.invalidate(); timer = nil
        let wasProbing = probing
        probing = false
        if wasProbing { checker.cancel() }
    }

    private func finish(_ result: Result<Appearance, AppearanceFailure>) {
        guard isPending else { return }
        isPending = false
        stopPending()
        completion(result)
    }
}
