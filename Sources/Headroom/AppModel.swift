import AppKit
import Combine
import HeadroomCore
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    @Published var storage: StorageSnapshot?
    @Published var codex: CodexSnapshot?
    @Published var storageError: String?
    @Published var codexError: String?
    @Published var codexRefreshing = false
    @Published var codexNeedsSetup = false
    private let checkingNotifications = CommandLine.arguments.contains("--check-notifications")
    @Published var alertsEnabled = UserDefaults.standard.bool(forKey: "storageAlertsEnabled")
    @Published var notificationMessage: String?
    @Published var notificationPermission: NotificationPermission = .unknown
    @Published var requestingNotificationPermission = false
    private var notificationCheckTask: Task<Void, Never>?
    var notificationReadiness: NotificationReadiness {
        NotificationReadiness.evaluate(requested: alertsEnabled, permission: notificationPermission)
    }
    @Published var cliPath = UserDefaults.standard.string(forKey: "codexExecutable") ?? ""
    @Published var now = Date()
    let demo: Bool
    let launchAtLogin: LaunchAtLogin
    let volumeURL: URL
    var changed: (() -> Void)?
    private var policy: StorageAlertPolicy
    private var diskTimer: Timer?
    private var codexTimer: Timer?
    private var codexTask: Task<Void, Never>?
    private var codexReadTask: Task<CodexSnapshot, Error>?
    private var sleeping = false
    private var pendingCodexRefresh = false

    init(demo: Bool = false) {
        self.demo = demo
        launchAtLogin = LaunchAtLogin(demo: demo)
        if demo { alertsEnabled = false }
        if let index = CommandLine.arguments.firstIndex(of: "--codex-cli"), index + 1 < CommandLine.arguments.count { cliPath = CommandLine.arguments[index + 1] }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dev = home.appendingPathComponent("Dev", isDirectory: true)
        volumeURL = FileManager.default.fileExists(atPath: dev.path) ? dev : home
        if let data = UserDefaults.standard.data(forKey: "storageAlertEpisode"), let saved = try? JSONDecoder().decode(StorageAlertPolicy.self, from: data) {
            policy = saved
        } else { policy = StorageAlertPolicy() }
    }
    func start() {
        refreshAll()
        if !demo { startTimers() }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    func stop() {
        sleeping = true
        diskTimer?.invalidate(); codexTimer?.invalidate()
        codexReadTask?.cancel(); codexTask?.cancel(); notificationCheckTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    func beginShutdown() -> Task<CodexSnapshot, Error>? {
        stop()
        return codexReadTask
    }
    private func startTimers() {
        diskTimer?.invalidate(); codexTimer?.invalidate()
        diskTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStorage() }
        }
        codexTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCodex() }
        }
        diskTimer?.tolerance = 3; codexTimer?.tolerance = 10
    }
    @objc private func willSleep() {
        sleeping = true
        pendingCodexRefresh = false
        diskTimer?.invalidate(); codexTimer?.invalidate(); codexReadTask?.cancel(); codexTask?.cancel()
    }
    @objc private func didWake() {
        sleeping = false
        if !demo { startTimers() }
        refreshAll()
    }
    func refreshAll() { launchAtLogin.refresh(); refreshStorage(); refreshCodex() }
    func refreshStorage() {
        guard !sleeping else { return }
        now = Date()
        do {
            storage = demo ? StorageSnapshot(totalBytes: 250_000_000_000, freeBytes: 25_000_000_000, volumeName: "Example disk", fetchedAt: now) : try StorageReader.read(url: volumeURL)
            storageError = nil
            if !demo, let storage {
                policy.observe(usedPercent: storage.usedPercent, notificationsEnabled: false)
                persistAlertPolicy()
                if !policy.isLatched && policy.deliveryAttempts == 0 { notificationMessage = nil }
                if policy.retriesExhausted { notificationMessage = "Critical alert failed after 3 attempts. Menu-bar warnings remain active." }
                refreshNotificationSettings()
            }
        } catch {
            storage = nil; storageError = "Disk capacity is unavailable. Retry when the volume is accessible."
            policy.recordFailure()
            if let data = try? JSONEncoder().encode(policy) { UserDefaults.standard.set(data, forKey: "storageAlertEpisode") }
        }
        changed?()
    }
    func refreshCodex() {
        guard !sleeping else { return }
        if demo {
            let scenario = CommandLine.arguments.firstIndex(of: "--demo-state").flatMap {
                CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil
            } ?? "normal"
            codexNeedsSetup = scenario == "missing-cli"
            if codexNeedsSetup {
                codex = nil; codexError = "Codex CLI not found. Choose your installed Codex executable."
                changed?(); return
            }
            let left: Double = scenario == "faster" ? 20 : scenario == "near" ? 42 : 79
            let short = scenario == "short-exhausted"
            codex = CodexSnapshot(remainingPercent: short ? 0 : left, windowLabel: short ? "5-hour allowance" : "Weekly allowance", resetsAt: Date().addingTimeInterval(short ? 3600 : 86400 * 3), fetchedAt: Date(), weekly: CodexWeeklyWindow(remainingPercent: left, resetsAt: Date().addingTimeInterval(86400 * 3)))
            if scenario == "blocked" { alertsEnabled = true; notificationPermission = .blocked }
            codexError = nil; changed?(); return
        }
        guard codexTask == nil else { pendingCodexRefresh = true; return }
        let executable: URL?
        if cliPath.isEmpty { executable = CodexExecutableResolver.discover() }
        else { executable = URL(fileURLWithPath: (cliPath as NSString).expandingTildeInPath) }
        guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else {
            codexNeedsSetup = true
            codex = nil; codexError = "Codex CLI not found. Choose your installed Codex executable."
            changed?(); return
        }
        codexNeedsSetup = false
        codexRefreshing = true; changed?()
        let readTask = Task.detached { try await CodexClient(executableURL: executable).read() }
        codexReadTask = readTask
        codexTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.codexRefreshing = false; self.codexTask = nil; self.codexReadTask = nil; self.changed?()
                if self.pendingCodexRefresh && !self.sleeping {
                    self.pendingCodexRefresh = false; self.refreshCodex()
                }
            }
            do {
                let snapshot = try await readTask.value
                try Task.checkCancellation()
                self.codex = snapshot; self.codexError = nil
            } catch is CancellationError {
                self.codex = nil; self.codexError = "Refresh paused."
            } catch {
                // Never present cached allowance after authentication/identity uncertainty.
                self.codex = nil; self.codexError = error.localizedDescription
            }
        }
    }
    func saveCLIPath() {
        cliPath = cliPath.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(cliPath, forKey: "codexExecutable")
        refreshCodex()
    }
    private func persistAlertPolicy() {
        guard !checkingNotifications else { return }
        if let data = try? JSONEncoder().encode(policy) { UserDefaults.standard.set(data, forKey: "storageAlertEpisode") }
    }
    func setAlerts(_ enabled: Bool) {
        guard !demo, !requestingNotificationPermission else { return }
        alertsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "storageAlertsEnabled")
        notificationMessage = nil
        guard enabled else { return }
        requestingNotificationPermission = true
        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch { notificationMessage = "Could not request permission. Check macOS notification settings." }
            requestingNotificationPermission = false
            // Any earlier query must finish before rechecking the new authorization.
            await notificationCheckTask?.value
            refreshNotificationSettings()
        }
    }
    func refreshNotificationSettings() {
        guard !demo, !sleeping, notificationCheckTask == nil else { return }
        notificationCheckTask = Task {
            defer { notificationCheckTask = nil }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard !Task.isCancelled, !sleeping else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationPermission = settings.alertSetting == .enabled ? .allowed : .blocked
            case .notDetermined: notificationPermission = .notRequested
            default: notificationPermission = .blocked
            }
            guard !requestingNotificationPermission, notificationReadiness == .enabled,
                  let snapshot = storage, snapshot.usedPercent >= 95,
                  Date().timeIntervalSince(snapshot.fetchedAt) <= 35,
                  policy.observe(usedPercent: snapshot.usedPercent, now: Date()),
                  let attemptID = policy.pendingAttemptID else { return }
            persistAlertPolicy()
            let content = UNMutableNotificationContent()
            content.title = checkingNotifications ? "Headroom test — no disk issue" : "Low disk space"
            content.body = "\(Int(floor(snapshot.usedPercent)))% used · \(String(format: "%.1f", snapshot.freeGB)) GB free. Review storage before continuing large builds."
            if checkingNotifications { content.body = "Synthetic low-space check. Your actual disk reading and saved alert preference are unchanged." }
            content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: checkingNotifications ? "headroom.storage.verification" : "headroom.storage.critical", content: content, trigger: nil))
                guard policy.pendingAttemptID == attemptID else { return }
                policy.completeDelivery(attemptID: attemptID, succeeded: true)
                notificationMessage = nil
            } catch {
                guard policy.pendingAttemptID == attemptID else { return }
                policy.completeDelivery(attemptID: attemptID, succeeded: false)
                notificationMessage = policy.retriesExhausted
                    ? "Critical alert failed after 3 attempts. Menu-bar warnings remain active."
                    : "Critical alert could not be submitted. Retrying after one minute."
            }
            persistAlertPolicy()
        }
    }
    /// Explicit local diagnostic: actual OS delivery, synthetic capacity, no saved preference/episode writes.
    func checkNotifications() async {
        guard checkingNotifications else { return }
        let center = UNUserNotificationCenter.current()
        if CommandLine.arguments.contains("--request-notification-permission") {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                print("Notification permission request: granted=\(granted)")
            } catch { print("Notification permission request failed: \(error.localizedDescription)") }
        }
        policy = StorageAlertPolicy()
        alertsEnabled = true // Diagnostic-only, deliberately not saved.
        storage = StorageSnapshot(totalBytes: 100_000_000_000, freeBytes: 4_000_000_000,
                                  volumeName: "Synthetic notification check", fetchedAt: Date())
        refreshNotificationSettings()
        await notificationCheckTask?.value
        print("Notification permission state: \(notificationPermission)")
        print("Notification readiness: \(notificationReadiness.rawValue)")
        print("Submission: accepted=\(policy.isLatched), attempts=\(policy.deliveryAttempts)")
        guard policy.isLatched else {
            print("BLOCKED: notification delivery needs macOS permission/presentation settings or a successful submission.")
            return
        }
        for _ in 0..<2 {
            refreshNotificationSettings()
            await notificationCheckTask?.value
        }
        print("Same-episode suppression: \(policy.deliveryAttempts == 1 ? "PASS" : "FAIL")")
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let delivered = await center.deliveredNotifications()
        let observed = delivered.contains { $0.request.identifier == "headroom.storage.verification" }
        print("Present in macOS delivered notifications: \(observed)")
        center.removeDeliveredNotifications(withIdentifiers: ["headroom.storage.verification"])
        center.removePendingNotificationRequests(withIdentifiers: ["headroom.storage.verification"])
    }
    var diskText: String {
        guard let s = storage else { return "Disk —" }
        return "\(Int(floor(s.usedPercent)))% used ·\(Int(floor(s.freeGB)))GB free"
    }
    var quotaPresentation: QuotaPresentation { QuotaPresentation.evaluate(codex) }
    var quotaText: String { quotaPresentation.text }
    var weeklyPace: WeeklyPace? {
        guard let codex else { return nil }
        return WeeklyPace.evaluate(snapshot: codex)
    }
    var codexPaceColor: NSColor {
        switch quotaPresentation.tone {
        case .warning: return .systemOrange
        case .critical: return .systemRed
        case .neutral: return .labelColor
        }
    }
    var weeklyPaceColor: NSColor {
        switch weeklyPace?.status {
        case .faster: return .systemOrange
        case .exhausted: return .systemRed
        default: return .labelColor
        }
    }
    var warningColor: NSColor {
        guard let s = storage else { return .labelColor }
        return s.usedPercent >= 95 ? .systemRed : s.usedPercent >= 90 ? .systemOrange : .labelColor
    }
    func age(_ date: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        return seconds < 60 ? "Updated just now" : "Updated \(Int(seconds / 60)) min ago"
    }
}
