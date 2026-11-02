import AppKit
import Darwin
import OSLog
import AuralimCore

struct AppearanceFailure: Error {
    let message: String
    let permissionDenied: Bool
    enum Reason { case custom, authorization, script(Int), verification }
    var reason: Reason = .custom
}

struct AppearanceApplication {
    let changed: Bool

    static func verified(_ result: NSAppleEventDescriptor?, target: Appearance) -> Result<Self, AppearanceFailure> {
        guard let result, result.numberOfItems == 2,
              let actual = result.atIndex(1), let changed = result.atIndex(2),
              [typeBoolean, typeTrue, typeFalse].contains(actual.descriptorType),
              [typeBoolean, typeTrue, typeFalse].contains(changed.descriptorType),
              actual.booleanValue == (target == .dark) else {
            return .failure(AppearanceFailure(message: "", permissionDenied: false, reason: .verification))
        }
        return .success(Self(changed: changed.booleanValue))
    }
}

protocol AppearanceApplying {
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void)
    func cancel()
}

extension AppearanceApplying {
    func cancel() {}
}

/// Keep the AppleScript runtime outside the UI process. NSAppleScript is a
/// main-thread-only API; executing it on a worker can deadlock during startup.
/// A bounded child also lets a stalled System Events request fail and release
/// AppModel.isApplying instead of blocking every subsequent manual selection.
final class AppearanceController: AppearanceApplying, AppearanceReadinessChecking {
    private let queue = DispatchQueue(label: "app.duskshift.appearance", qos: .utility)
    private let processLock = NSLock()
    private var activeProcess: Process?
    private var cancellationGeneration = 0
    private let executableURL: URL
    private let arguments: (Appearance) -> [String]
    private let readinessArguments: () -> [String]
    private let readinessTimeout: TimeInterval
    private let timeout: TimeInterval
    private let terminationGrace: TimeInterval
    private let logger = Logger(subsystem: "app.duskshift.mac", category: "Appearance")

    init(executableURL: URL = URL(fileURLWithPath: "/usr/bin/osascript"),
         timeout: TimeInterval = 12, terminationGrace: TimeInterval = 0.5,
         arguments: @escaping (Appearance) -> [String] = { ["-s", "s", "-e", AppearanceController.script(for: $0)] },
         readinessTimeout: TimeInterval = 4,
         readinessArguments: @escaping () -> [String] = { ["-s", "s", "-e", AppearanceController.readinessScript] }) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.readinessArguments = readinessArguments
        self.readinessTimeout = readinessTimeout
        self.timeout = timeout
        self.terminationGrace = terminationGrace
    }

    static let readinessScript = """
    with timeout of 3 seconds
        tell application "System Events"
            return dark mode of appearance preferences
        end tell
    end timeout
    """

    static func script(for appearance: Appearance) -> String {
        let value = appearance == .dark ? "true" : "false"
        return """
        with timeout of 10 seconds
            tell application "System Events"
                tell appearance preferences
                    set didChange to (dark mode is not \(value))
                    if didChange then set dark mode to \(value)
                    return {dark mode, didChange}
                end tell
            end tell
        end timeout
        """
    }

    static func verifiedOutput(_ output: String, target: Appearance) -> Result<AppearanceApplication, AppearanceFailure> {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("{"), text.hasSuffix("}") else {
            return .failure(.init(message: "", permissionDenied: false, reason: .verification))
        }
        let values = text.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard values.count == 2, values.allSatisfy({ $0 == "true" || $0 == "false" }),
              (values[0] == "true") == (target == .dark) else {
            return .failure(.init(message: "", permissionDenied: false, reason: .verification))
        }
        return .success(.init(changed: values[1] == "true"))
    }

    static func scriptFailure(_ stderr: String) -> AppearanceFailure {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = message.range(of: #"\(-?\d+\)\s*$"#, options: .regularExpression)
        let code = range.flatMap { Int(message[$0].trimmingCharacters(in: CharacterSet(charactersIn: "() \n\r\t"))) } ?? 0
        let denied = code == -1743 || code == -1744
        return .init(message: message, permissionDenied: denied, reason: denied ? .authorization : .script(code))
    }

    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        run(arguments: { self.arguments(appearance) }, timeout: timeout, purpose: appearance.rawValue) { result in
            completion(result.flatMap { Self.verifiedOutput($0, target: appearance) })
        }
    }

    func readAppearance(completion: @escaping (Result<Appearance, AppearanceFailure>) -> Void) {
        run(arguments: readinessArguments, timeout: readinessTimeout, purpose: "startup-readiness") { result in
            completion(result.flatMap { output in
                switch output.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "true": return .success(.dark)
                case "false": return .success(.light)
                default: return .failure(.init(message: "", permissionDenied: false, reason: .verification))
                }
            })
        }
    }

    private func run(arguments: @escaping () -> [String], timeout: TimeInterval, purpose: String,
                     completion: @escaping (Result<String, AppearanceFailure>) -> Void) {
        processLock.lock()
        let generation = cancellationGeneration
        processLock.unlock()
        queue.async {
            let outcome = self.execute(arguments: arguments(), timeout: timeout, purpose: purpose, generation: generation)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// Called on shutdown before the app terminates. Invalidates queued work
    /// and kills the active child immediately; no child is allowed to outlive us.
    func cancel() {
        processLock.lock()
        cancellationGeneration += 1
        if let process = activeProcess, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        processLock.unlock()
    }

    private func isCurrent(_ generation: Int) -> Bool {
        processLock.lock(); defer { processLock.unlock() }
        return generation == cancellationGeneration
    }

    private var cancelled: Result<String, AppearanceFailure> {
        .failure(.init(message: "", permissionDenied: false, reason: .script(-128)))
    }

    private func execute(arguments: [String], timeout: TimeInterval, purpose: String, generation: Int) -> Result<String, AppearanceFailure> {
        let process = Process(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        logger.info("Appearance request started: \(purpose, privacy: .public)")
        processLock.lock()
        guard generation == cancellationGeneration else { processLock.unlock(); return cancelled }
        activeProcess = process
        do { try process.run() }
        catch {
            activeProcess = nil
            processLock.unlock()
            logger.error("Appearance runner failed to launch: \((error as NSError).code)")
            return .failure(.init(message: error.localizedDescription, permissionDenied: false, reason: .script((error as NSError).code)))
        }
        processLock.unlock()
        defer {
            processLock.lock()
            if activeProcess === process { activeProcess = nil }
            processLock.unlock()
        }
        // Only this worker waits. There is no main-thread wait, polling or
        // in-process AppleScript execution. The script emits just two booleans.
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            processLock.lock()
            if process.isRunning { process.terminate() }
            processLock.unlock()
            if exited.wait(timeout: .now() + terminationGrace) == .timedOut {
                processLock.lock()
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                processLock.unlock()
                _ = exited.wait(timeout: .now() + terminationGrace)
            }
            logger.error("Appearance request timed out; runner terminated")
            return .failure(.init(message: "", permissionDenied: false, reason: .script(-1712)))
        }
        guard isCurrent(generation) else { return cancelled }
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let failure = Self.scriptFailure(error)
            logger.error("Appearance script failed, exit status: \(process.terminationStatus)")
            return .failure(failure)
        }
        logger.info("Appearance request returned: \(purpose, privacy: .public)")
        return .success(output)
    }
}
