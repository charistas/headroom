import AppKit
import SwiftUI
import HeadroomCore

@MainActor final class StatusReading: NSView {
    weak var model: AppModel?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    static func title(for model: AppModel) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 12)
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let title = NSMutableAttributedString(string: model.diskText, attributes: [.font: font, .foregroundColor: model.warningColor])
        title.append(NSAttributedString(string: " | ", attributes: base))
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [model.codexPaceColor]))
        if let icon = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Codex")?.withSymbolConfiguration(configuration) {
            let attachment = NSTextAttachment()
            attachment.image = icon
            attachment.bounds = NSRect(x: 0, y: -2, width: 14, height: 12)
            title.append(NSAttributedString(attachment: attachment))
        } else {
            title.append(NSAttributedString(string: ">_", attributes: base))
        }
        title.append(NSAttributedString(string: " " + model.quotaText, attributes: base))
        return title
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let model else { return }
        let title = Self.title(for: model)
        title.draw(at: NSPoint(x: 8, y: (bounds.height - title.size().height) / 2))
    }
}

@MainActor final class HeadroomDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel(demo: CommandLine.arguments.contains("--demo"))
    private var terminating = false
    var status: NSStatusItem?
    var reading: StatusReading?
    let popover = NSPopover()
    var previewWindow: NSWindow?
    var renderPath: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "--render"), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        if CommandLine.arguments.contains("--check-notifications") {
            NSApp.activate(ignoringOtherApps: true)
            Task { await model.checkNotifications(); NSApp.terminate(nil) }
            return
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: HeadroomPanel(model: model))
        model.changed = { [weak self] in self?.updateStatus() }
        if CommandLine.arguments.contains("--preview-window") {
            let host = NSHostingView(rootView: HeadroomPanel(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Headroom"; window.contentView = host; window.isReleasedWhenClosed = false
            window.center(); window.makeKeyAndOrderFront(nil); previewWindow = window
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let item = NSStatusBar.system.statusItem(withLength: 210)
            status = item
            if let button = item.button {
                let label = StatusReading(frame: button.bounds)
                label.model = model; label.autoresizingMask = [.width, .height]
                button.addSubview(label); reading = label
                button.target = self; button.action = #selector(togglePanel)
            }
        }
        model.start()
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + (CommandLine.arguments.contains("--quit-during-refresh") ? 1 : 15)) {
                print("Native smoke: storage=\(self.model.storage != nil), codex=\(self.model.codex != nil), statusWidth=\(self.status?.length ?? 0)")
                print("Weekly pace: \(self.model.weeklyPace?.status.rawValue ?? "unavailable")")
                if let frame = self.status?.button?.window?.frame, let area = self.status?.button?.window?.screen?.auxiliaryTopRightArea {
                    print("Menu-bar fit: itemMinX=\(frame.minX), notchRight=\(area.minX), whollyOnRight=\(frame.minX >= area.minX && frame.maxX <= area.maxX)")
                }
                NSApp.terminate(nil)
            }
        }
        if renderPath != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.saveRender() }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.launchAtLogin.refresh() }
    func updateStatus() {
        // Measure the same attributed content that is drawn, including the icon.
        let width = ceil(StatusReading.title(for: model).size().width) + 16
        status?.length = max(210, width)
        reading?.needsDisplay = true
        let full = "Disk \(model.diskText); \(model.quotaPresentation.accessibilityText)."
        let paceText = model.weeklyPace.map { " Weekly pace: " + $0.status.rawValue + ". Assumes even usage until reset." } ?? " Weekly pace unavailable."
        status?.button?.toolTip = full + paceText
        status?.button?.setAccessibilityLabel("Headroom. " + full + paceText)
    }
    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = status?.button else { return }
        model.now = Date(); model.refreshAll()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func saveRender() {
        guard let path = renderPath, let view = previewWindow?.contentView else { return }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        guard let pendingRead = model.beginShutdown() else { return .terminateNow }
        // terminateLater runs a modal loop, which does not service MainActor tasks.
        // Await process cleanup away from MainActor and reply in that modal mode.
        Task.detached {
            _ = try? await pendingRead.value
            RunLoop.main.perform(inModes: [.modalPanel, .default]) {
                MainActor.assumeIsolated { sender.reply(toApplicationShouldTerminate: true) }
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { model.stop(); if let status { NSStatusBar.system.removeStatusItem(status) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { previewWindow != nil }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}

import UserNotifications
