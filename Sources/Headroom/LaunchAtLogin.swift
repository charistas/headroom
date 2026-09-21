import Combine
import ServiceManagement
import SwiftUI

/// macOS owns the preference; no separate saved boolean can drift from System Settings.
@MainActor final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var message: String?
    let demo: Bool
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let openSettings: () -> Void

    init(demo: Bool = false,
         readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
         openSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }) {
        self.demo = demo
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
        refresh()
    }

    var isEnabled: Bool { status == .enabled }

    func refresh() {
        guard !demo else { return }
        let next = readStatus()
        if next != status { message = nil }
        status = next
    }

    func setEnabled(_ enabled: Bool) {
        guard !demo else { return }
        refresh()
        message = nil
        if enabled && status == .requiresApproval { openSettings(); return }
        guard enabled != isEnabled else { return }
        do {
            if enabled { try register() } else { try unregister() }
        } catch {
            refresh()
            message = "Could not change Launch at Login. " + error.localizedDescription
            return
        }
        refresh()
    }

    func showSettings() { if !demo { openSettings() } }
}

struct LaunchAtLoginSetting: View {
    @ObservedObject var login: LaunchAtLogin
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) }))
                .disabled(login.demo)
                .help("Start Headroom in the menu bar when you sign in to this Mac.")
            if login.status == .requiresApproval {
                Text("Allow Headroom in System Settings → General → Login Items & Extensions.")
                    .foregroundStyle(.orange)
                Button("Open Login Items", action: login.showSettings)
            } else if login.status == .notFound {
                Text("Login item unavailable. Keep Headroom in its installed location and try again.")
                    .foregroundStyle(.orange)
            }
            if let message = login.message { Text(message).foregroundStyle(.orange) }
        }
    }
}
