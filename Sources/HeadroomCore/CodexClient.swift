import Foundation
import CoreFoundation
import Darwin

public struct CodexWeeklyWindow: Codable, Equatable, Sendable {
    public let remainingPercent: Double
    public let resetsAt: Date

    public init(remainingPercent: Double, resetsAt: Date) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct CodexSnapshot: Codable, Equatable, Sendable {
    public let remainingPercent: Double
    public let windowLabel: String
    public let resetsAt: Date?
    public let fetchedAt: Date
    public let weekly: CodexWeeklyWindow?

    public init(remainingPercent: Double, windowLabel: String, resetsAt: Date?, fetchedAt: Date, weekly: CodexWeeklyWindow? = nil) {
        self.remainingPercent = remainingPercent
        self.windowLabel = windowLabel
        self.resetsAt = resetsAt
        self.fetchedAt = fetchedAt
        self.weekly = weekly
    }
}

public enum CodexClientError: Error, LocalizedError, Equatable {
    case launchFailed, timedOut, invalidResponse, outputLimit, serverError, missingCoreQuota, expiredWindow, usageUnavailable, processExited, shutdownFailed

    public var errorDescription: String? {
        switch self {
        case .launchFailed: return "Could not start the Codex CLI. Check its location and installation."
        case .timedOut: return "Codex did not respond in time."
        case .invalidResponse: return "Codex returned an unsupported usage response."
        case .outputLimit: return "Codex returned more data than expected."
        case .serverError: return "Codex could not read usage. Check your Codex login and connection."
        case .missingCoreQuota: return "Your core Codex allowance is unavailable."
        case .expiredWindow: return "Codex returned an expired usage window. Refresh to check again."
        case .usageUnavailable: return "Codex included usage is currently unavailable."
        case .processExited: return "The Codex helper stopped before returning usage."
        case .shutdownFailed: return "The Codex helper did not stop. Quit Headroom and check the CLI installation."
        }
    }
}

/// Parses only the core quota. Model-specific buckets, credits, and null windows
/// must never be interpreted as available core allowance.
public enum CodexRateLimitsParser {
    public static func parse(result data: Data, fetchedAt: Date = Date()) throws -> CodexSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexClientError.invalidResponse
        }
        if root["ordinaryUsageAllowed"] as? Bool == false { throw CodexClientError.usageUnavailable }
        let bucket: [String: Any]
        if let map = root["rateLimitsByLimitId"] as? [String: Any], let core = map["codex"] {
            guard let value = core as? [String: Any],
                  value["limitId"] == nil || value["limitId"] is NSNull || value["limitId"] as? String == "codex" else {
                throw CodexClientError.invalidResponse
            }
            bucket = value
        } else if let legacy = root["rateLimits"] as? [String: Any], legacy["limitId"] as? String == "codex" {
            bucket = legacy
        } else { throw CodexClientError.missingCoreQuota }
        if bucket["spendControlReached"] as? Bool == true { throw CodexClientError.usageUnavailable }
        var windows: [CodexSnapshot] = []
        var weeklyWindows: [CodexWeeklyWindow] = []
        for key in ["primary", "secondary"] {
            guard let raw = bucket[key], !(raw is NSNull) else { continue }
            guard let window = raw as? [String: Any], let used = number(window["usedPercent"]), used >= 0 else {
                throw CodexClientError.invalidResponse
            }
            let reset: Date?
            if let rawReset = window["resetsAt"], !(rawReset is NSNull) {
                guard let seconds = number(rawReset), seconds > 0 else { throw CodexClientError.invalidResponse }
                reset = Date(timeIntervalSince1970: seconds)
                // Dropping an expired constraint could falsely imply recovery.
                guard reset! > fetchedAt else { throw CodexClientError.expiredWindow }
            } else { reset = nil }
            var label = "Current window"
            if let rawDuration = window["windowDurationMins"], !(rawDuration is NSNull) {
                guard let minutes = number(rawDuration), minutes > 0, minutes.rounded() == minutes,
                      minutes <= 525_600 else { throw CodexClientError.invalidResponse }
                if minutes == 10_080 {
                    label = "Weekly allowance"
                    if let reset { weeklyWindows.append(CodexWeeklyWindow(remainingPercent: max(0, 100 - used), resetsAt: reset)) }
                }
                else if minutes.truncatingRemainder(dividingBy: 60) == 0 { label = "\(Int(minutes / 60))-hour allowance" }
                else { label = "\(Int(minutes))-minute allowance" }
            }
            windows.append(CodexSnapshot(remainingPercent: max(0, 100 - used), windowLabel: label, resetsAt: reset, fetchedAt: fetchedAt))
        }
        guard let selected = windows.min(by: { $0.remainingPercent < $1.remainingPercent }) else {
            throw CodexClientError.missingCoreQuota
        }
        return CodexSnapshot(remainingPercent: selected.remainingPercent, windowLabel: selected.windowLabel,
                             resetsAt: selected.resetsAt, fetchedAt: fetchedAt,
                             weekly: weeklyWindows.min(by: { $0.remainingPercent < $1.remainingPercent }))
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
}

public enum CodexExecutableResolver {
    public static func discover() -> URL? {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        var candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map {
            URL(fileURLWithPath: String($0)).appendingPathComponent("codex")
        }
        candidates += [home.appendingPathComponent(".local/bin/codex"), home.appendingPathComponent(".volta/bin/codex"),
                       URL(fileURLWithPath: "/opt/homebrew/bin/codex"), URL(fileURLWithPath: "/usr/local/bin/codex"),
                       URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")]
        let versions = home.appendingPathComponent(".nvm/versions/node")
        let directories = (try? manager.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil)) ?? []
        candidates += directories.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            .map { $0.appendingPathComponent("bin/codex") }
        return candidates.first { manager.isExecutableFile(atPath: $0.path) }
    }
}

public struct CodexClient: Sendable {
    public let executableURL: URL
    public let timeout: TimeInterval

    public init(executableURL: URL, timeout: TimeInterval = 15) {
        self.executableURL = executableURL
        self.timeout = min(120, max(0.05, timeout))
    }

    public func read() async throws -> CodexSnapshot {
        let session = CodexSession(executableURL: executableURL, timeout: timeout)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in session.start(continuation) }
        }, onCancel: { session.cancel() })
    }
}

/// Every session owns exactly one helper. Serial confinement protects process,
/// protocol, cancellation, timeout, and continuation state from racing callbacks.
private final class CodexSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Headroom.CodexSession")
    private let executableURL: URL
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<CodexSnapshot, Error>?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var receivedBytes = 0
    private var initialized = false
    private var finished = false
    private var cancelled = false
    private var timeoutWork: DispatchWorkItem?

    init(executableURL: URL, timeout: TimeInterval) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func start(_ continuation: CheckedContinuation<CodexSnapshot, Error>) {
        queue.async { [self] in
            self.continuation = continuation
            if self.cancelled { self.finish(.failure(CancellationError())); return }
            let process = Process()
            let input = Pipe(), output = Pipe()
            self.process = process; self.input = input; self.output = output
            process.executableURL = self.executableURL
            process.arguments = ["app-server", "--listen", "stdio://"]
            var environment = ProcessInfo.processInfo.environment
            // npm's codex shim uses /usr/bin/env node. GUI apps have a short PATH.
            environment["PATH"] = self.executableURL.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            process.environment = environment
            // Suppress SIGPIPE on this descriptor, without changing app-wide signal handling.
            _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                var bytes = [UInt8](repeating: 0, count: 65_536)
                let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
                let data = count > 0 ? Data(bytes.prefix(count)) : Data()
                self?.queue.async { [weak self] in self?.receive(data) }
            }
            process.terminationHandler = { [weak self] _ in
                // stdout's EOF callback is authoritative: it drains the final reply
                // even if the helper exits immediately after writing it.
                self?.queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, !self.finished else { return }
                    self.finish(.failure(CodexClientError.processExited))
                }
            }
            do {
                try process.run()
                let timer = DispatchWorkItem { [weak self] in self?.finish(.failure(CodexClientError.timedOut)) }
                self.timeoutWork = timer
                self.queue.asyncAfter(deadline: .now() + self.timeout, execute: timer)
                try self.send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "headroom", "title": "Headroom", "version": "0.1.0"], "capabilities": ["experimentalApi": false]]])
            } catch { self.finish(.failure(CodexClientError.launchFailed)) }
        }
    }

    func cancel() {
        queue.async {
            self.cancelled = true
            if self.continuation != nil { self.finish(.failure(CancellationError())) }
        }
    }

    private func receive(_ data: Data) {
        guard !finished else { return }
        guard !data.isEmpty else { finish(.failure(CodexClientError.processExited)); return }
        receivedBytes += data.count
        guard receivedBytes <= 1_048_576 else { finish(.failure(CodexClientError.outputLimit)); return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw CodexClientError.invalidResponse }
                guard let identifier = message["id"] as? Int else { continue } // Notifications carry no response ID.
                guard identifier == (initialized ? 2 : 1) else { continue }
                if message["error"] != nil { throw CodexClientError.serverError }
                guard let result = message["result"] as? [String: Any] else { throw CodexClientError.invalidResponse }
                if !initialized {
                    initialized = true
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read", "params": [:]])
                } else {
                    let snapshot = try CodexRateLimitsParser.parse(result: JSONSerialization.data(withJSONObject: result))
                    finish(.success(snapshot)); return
                }
            } catch {
                finish(.failure((error as? CodexClientError) ?? CodexClientError.invalidResponse)); return
            }
        }
    }

    private func send(_ value: [String: Any]) throws {
        guard let input else { throw CodexClientError.processExited }
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func finish(_ result: Result<CodexSnapshot, Error>) {
        guard !finished else { return }
        finished = true
        timeoutWork?.cancel(); timeoutWork = nil
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        // Let the read handle close on deallocation after any in-progress
        // readability callback returns; closing it here can race that callback.
        buffer.removeAll(keepingCapacity: false)
        if let process, process.isRunning {
            process.terminate()
            awaitShutdown(process, result: result, startedAt: Date(), forced: false)
        } else { complete(result) }
    }

    private func awaitShutdown(_ process: Process, result: Result<CodexSnapshot, Error>, startedAt: Date, forced: Bool) {
        guard process.isRunning else { complete(result); return }
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed >= 2 { complete(.failure(CodexClientError.shutdownFailed)); return }
        var didForce = forced
        if elapsed >= 0.5 && !forced {
            // Only this owned process object can be targeted. The normal CLI
            // wrapper forwards SIGTERM to its native helper before this fallback.
            kill(process.processIdentifier, SIGKILL)
            didForce = true
        }
        let nextForced = didForce
        queue.asyncAfter(deadline: .now() + 0.025) { [self] in
            awaitShutdown(process, result: result, startedAt: startedAt, forced: nextForced)
        }
    }

    private func complete(_ result: Result<CodexSnapshot, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
