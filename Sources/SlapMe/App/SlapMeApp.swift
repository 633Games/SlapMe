import AppKit
import Combine
import SwiftUI

@main
enum SlapMeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegateRetention.shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

private enum AppDelegateRetention {
    static var shared: AppDelegate?
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var appState: AppState?
    private var prideTimer: Timer?
    private var iconCancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()

        Task { @MainActor in
            self.buildPopover()
            self.observeIconAppearance()
            self.refreshStatusItemIcon()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.toolTip = "SlapMe — click for settings"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // Start with a visible pink hand (non-template so color sticks).
            button.image = StatusItemIcon.image(color: NSColor(calibratedRed: 1, green: 0.3, blue: 0.43, alpha: 1))
        }
        statusItem = item
    }

    @MainActor
    private func buildPopover() {
        guard popover == nil else { return }

        let state = AppState()
        appState = state

        let hosting = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(state)
        )
        hosting.preferredContentSize = NSSize(width: 360, height: 620)

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 360, height: 620)
        pop.contentViewController = hosting
        pop.delegate = self
        popover = pop
    }

    @MainActor
    private func observeIconAppearance() {
        guard let appState else { return }
        iconCancellables.removeAll()

        Publishers.CombineLatest3(appState.$iconTintMode, appState.$iconColorHex, appState.$listeningEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] mode, _, listening in
                self?.updatePrideTimer(mode: listening ? mode : .solid)
                self?.refreshStatusItemIcon()
            }
            .store(in: &iconCancellables)

        updatePrideTimer(mode: appState.listeningEnabled ? appState.iconTintMode : .solid)
    }

    @MainActor
    private func updatePrideTimer(mode: IconTintMode) {
        prideTimer?.invalidate()
        prideTimer = nil
        guard mode == .pride, appState?.listeningEnabled != false else { return }

        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusItemIcon()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        prideTimer = timer
    }

    @MainActor
    private func refreshStatusItemIcon() {
        guard let button = statusItem?.button else { return }

        let listening = appState?.listeningEnabled ?? true
        button.alphaValue = listening ? 1.0 : 0.35

        let color: NSColor
        if !listening {
            color = NSColor.secondaryLabelColor
        } else if let state = appState {
            switch state.iconTintMode {
            case .pride:
                color = StatusItemIcon.prideColor()
            case .solid:
                color = nsColor(fromHex: state.iconColorHex) ?? NSColor.systemPink
            }
        } else {
            color = NSColor.systemPink
        }

        button.image = StatusItemIcon.image(color: color)
    }

    private func nsColor(fromHex hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        Task { @MainActor in
            self.handleStatusItemClick()
        }
    }

    @MainActor
    private func handleStatusItemClick() {
        if popover == nil {
            buildPopover()
            observeIconAppearance()
            refreshStatusItemIcon()
        }

        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        appState?.refreshDiagnostics()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        prideTimer?.invalidate()
    }
}
