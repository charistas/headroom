import SwiftUI
import AppKit
import HeadroomCore

struct HeadroomPanel: View {
    @ObservedObject var model: AppModel
    @State private var settings = CommandLine.arguments.contains("--demo") && CommandLine.arguments.contains("--show-settings")
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Headroom").font(.headline)
                if model.demo { Text("DEMO").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Button { settings.toggle(); model.launchAtLogin.refresh(); model.refreshNotificationSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).accessibilityLabel("Settings")
            }
            storageSection
            Divider()
            codexSection
            if settings { Divider(); settingsSection }
            Divider()
            HStack {
                Button { model.refreshAll() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.font(.caption)
        }
        .padding(20)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.now = Date() }
    }
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Storage").font(.headline)
                Spacer()
                if let s = model.storage {
                    Text("\(s.freeGB, specifier: "%.1f") GB free").font(.headline).monospacedDigit()
                } else { Text("Unavailable").foregroundStyle(.secondary) }
            }
            if let s = model.storage {
                Text(s.volumeName).font(.caption).foregroundStyle(.secondary)
                ProgressView(value: s.usedPercent, total: 100).tint(Color(nsColor: model.warningColor))
                    .accessibilityLabel("Disk space used").accessibilityValue("\(Int(floor(s.usedPercent))) percent")
                HStack {
                    Text("\(Int(floor(s.usedPercent)))% used · \(s.totalBytes / 1_000_000_000) GB total")
                    Spacer()
                }.font(.caption).foregroundStyle(.secondary)
                Text(model.age(s.fetchedAt)).font(.caption2).foregroundStyle(.secondary)
                if s.usedPercent >= 90 {
                    Label(s.usedPercent >= 95 ? "Low disk space" : "Space running low", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Color(nsColor: model.warningColor))
                }
                Button { settings = true; model.launchAtLogin.refresh(); model.refreshNotificationSettings() } label: {
                    Label("Critical alerts: " + model.notificationReadiness.rawValue, systemImage: "bell")
                }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                if let message = model.notificationMessage {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text(model.storageError ?? "Reading disk capacity…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Codex").font(.headline)
                Spacer()
                if let q = model.codex, model.quotaPresentation.text != "—" {
                    Text(QuotaPresentation.remainingText(q.remainingPercent) + " left").font(.headline).monospacedDigit()
                        .foregroundStyle(q.remainingPercent == 0 ? Color.red : Color.primary)
                } else if model.codexRefreshing { ProgressView().controlSize(.small) }
            }
            if let q = model.codex, model.quotaPresentation.text != "—" {
                Text(q.windowLabel).font(.caption).foregroundStyle(.secondary)
                Text("Remaining").font(.caption2).foregroundStyle(.secondary)
                ProgressView(value: q.remainingPercent, total: 100).tint(Color(nsColor: model.codexPaceColor))
                    .accessibilityLabel("Codex allowance remaining").accessibilityValue(QuotaPresentation.remainingText(q.remainingPercent))
                if q.remainingPercent == 0 {
                    Label("\(q.windowLabel) exhausted", systemImage: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                if let reset = q.resetsAt {
                    Text("\(q.windowLabel) resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                weeklyPaceSection
                HStack {
                    Text(model.age(q.fetchedAt))
                    if model.codexRefreshing { Text("· Refreshing…") }
                }.font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(model.codexError ?? (model.codexRefreshing ? "Reading allowance…" : "Allowance needs a fresh reading."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.codexNeedsSetup {
                    Button("Choose Codex…", action: chooseCodex).font(.caption)
                } else if !model.codexRefreshing {
                    Button("Retry") { model.refreshCodex() }.font(.caption)
                }
            }
        }
    }
    @ViewBuilder private var weeklyPaceSection: some View {
        if let pace = model.weeklyPace {
            VStack(alignment: .leading, spacing: 6) {
                Label("Weekly pace · " + pace.status.rawValue,
                      systemImage: pace.status == .onPace || pace.status == .nearPace ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color(nsColor: model.weeklyPaceColor))
                if let q = model.codex, q.windowLabel != "Weekly allowance", let weekly = q.weekly {
                    Text("Weekly: \(QuotaPresentation.remainingText(weekly.remainingPercent)) left · resets \(weekly.resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let budget = pace.dailyBudgetPercent, pace.remainingPercent > 0 {
                    Text("Daily budget: ~\(floor(budget * 10) / 10, specifier: "%.1f")% of weekly allowance")
                        .font(.caption.weight(.medium))
                } else {
                    Text("\(pace.daysRemaining * 24, specifier: "%.1f") hours until the weekly reset.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("Even-use estimate")
                    .font(.caption2).foregroundStyle(.secondary)
                    .help("Assumes even usage until the weekly reset. A deficit up to 2 percentage points is Near pace. Currently \(String(format: "%.1f", abs(pace.percentagePointsFromPace))) points \(pace.percentagePointsFromPace >= 0 ? "under" : "over") that budget. Future workload may differ; this is not a prediction.")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        } else {
            Text("Weekly pace needs a fresh seven-day limit and reset time.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func chooseCodex() {
        guard !model.demo else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose your installed Codex CLI executable."
        if panel.runModal() == .OK, let url = panel.url {
            model.cliPath = url.path; model.saveCLIPath()
        }
    }
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LaunchAtLoginSetting(login: model.launchAtLogin)
            Toggle("Notify when disk reaches 95%", isOn: Binding(get: { model.alertsEnabled }, set: { model.setAlerts($0) }))
                .disabled(model.demo || model.requestingNotificationPermission)
                .help("Amber starts at 90%, red at 95%. After an alert, two successful readings below 94% re-arm notifications. Failed submissions retry at most three times, at least one minute apart.")
            if model.notificationReadiness == .blocked {
                Text("Allow Headroom alerts in System Settings → Notifications. Menu-bar warnings remain active.")
                    .font(.caption).foregroundStyle(.orange)
                Button("Open Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                }
            }
            DisclosureGroup("Advanced") {
                HStack {
                    Text("Codex CLI").font(.caption)
                    Spacer()
                    Text(model.cliPath.isEmpty ? "Auto-detected" : URL(fileURLWithPath: model.cliPath).lastPathComponent)
                        .foregroundStyle(.secondary)
                    Button("Choose…", action: chooseCodex)
                    if !model.cliPath.isEmpty { Button("Auto") { model.cliPath = ""; model.saveCLIPath() } }
                }.padding(.top, 6)
            }
            Text("GB uses decimal units.")
                .font(.caption2).foregroundStyle(.secondary)
                .help("Used space is total capacity minus ordinary free space, including shared APFS allocations. Headroom does not scan directories or clean up files.")
        }.font(.caption)
            .fixedSize(horizontal: false, vertical: true)
    }
}
