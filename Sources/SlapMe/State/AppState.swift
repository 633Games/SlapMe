import AppKit
import Combine
import Foundation
import SwiftUI

enum IconTintMode: String, CaseIterable, Identifiable {
    case solid
    case pride

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid: return "Solid"
        case .pride: return "Pride"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var listeningEnabled: Bool = true
    @Published var helperConnected: Bool = false
    @Published var lastAmplitude: Double = 0
    @Published var lastSlapAt: Date?
    @Published var statusMessage: String = "Connecting to helper…"
    @Published var diagnostics: PermissionDiagnostics = HelperLauncher.diagnose()
    @Published var isLaunchingHelper: Bool = false
    @Published var setupNote: String?
    @Published var showSetupGuide: Bool = true

    @Published var sensitivity: Double {
        didSet { defaults.set(sensitivity, forKey: Keys.sensitivity) }
    }
    @Published var cooldown: Double {
        didSet { defaults.set(cooldown, forKey: Keys.cooldown) }
    }
    @Published var volumeScaling: Bool {
        didSet { defaults.set(volumeScaling, forKey: Keys.volumeScaling) }
    }
    @Published var masterVolume: Double {
        didSet { defaults.set(masterVolume, forKey: Keys.masterVolume) }
    }
    @Published var nsfwEnabled: Bool {
        didSet {
            defaults.set(nsfwEnabled, forKey: Keys.nsfwEnabled)
            reloadPacks()
        }
    }
    @Published var selectedPackID: String {
        didSet { defaults.set(selectedPackID, forKey: Keys.selectedPackID) }
    }

    @Published var iconTintMode: IconTintMode {
        didSet { defaults.set(iconTintMode.rawValue, forKey: Keys.iconTintMode) }
    }
    @Published var iconColorHex: String {
        didSet { defaults.set(iconColorHex, forKey: Keys.iconColorHex) }
    }
    @Published var packs: [SoundPack] = []
    @Published var soundboardQuery: String = "anime ow"
    @Published var soundboardResults: [SoundboardClip] = []
    @Published var isSearchingSoundboard = false
    @Published var isDownloadingSoundboard = false
    @Published var soundboardNote: String?
    @Published var previewingClipID: String?

    let packManager = PackManager()
    let audioEngine = AudioEngine()

    private let defaults = UserDefaults.standard
    private var socketClient: SocketClient?
    private var lastPlayAt: Date = .distantPast

    private enum Keys {
        static let sensitivity = "sensitivity"
        static let cooldown = "cooldown"
        static let volumeScaling = "volumeScaling"
        static let masterVolume = "masterVolume"
        static let nsfwEnabled = "nsfwEnabled"
        static let selectedPackID = "selectedPackID"
        static let iconTintMode = "iconTintMode"
        static let iconColorHex = "iconColorHex"
    }

    var selectedPack: SoundPack? {
        packs.first { $0.id == selectedPackID } ?? packs.first
    }

    func reloadPacks() {
        packManager.reload(nsfwEnabled: nsfwEnabled)
        packs = packManager.packs
        if !packs.contains(where: { $0.id == selectedPackID }) {
            selectedPackID = packManager.defaultPackID
        }
    }

    var iconColor: Color {
        Color(hex: iconColorHex) ?? .pink
    }

    init() {
        sensitivity = defaults.object(forKey: Keys.sensitivity) as? Double ?? 0.05
        cooldown = defaults.object(forKey: Keys.cooldown) as? Double ?? 0.65
        volumeScaling = defaults.object(forKey: Keys.volumeScaling) as? Bool ?? true
        masterVolume = defaults.object(forKey: Keys.masterVolume) as? Double ?? 0.9
        nsfwEnabled = defaults.bool(forKey: Keys.nsfwEnabled)
        selectedPackID = defaults.string(forKey: Keys.selectedPackID) ?? "sfw.default"
        iconTintMode = IconTintMode(rawValue: defaults.string(forKey: Keys.iconTintMode) ?? "") ?? .solid
        iconColorHex = defaults.string(forKey: Keys.iconColorHex) ?? "#FF4D6D"

        Paths.ensureSupportDirectories()
        reloadPacks()
        showSetupGuide = true
        setupNote = "Admin access required once to start the sensor helper."
        startSocketClient()

        // Diagnostics can touch ioreg — never block init / first click.
        Task { @MainActor in
            self.refreshDiagnostics()
        }
    }

    func refreshDiagnostics() {
        diagnostics = HelperLauncher.diagnose()
        if helperConnected {
            if setupNote == nil || setupNote?.contains("required") == true || setupNote?.contains("Waiting") == true {
                setupNote = "Helper connected — slap away."
            }
        } else if !diagnostics.helperBinaryFound {
            setupNote = "Helper binary missing. Run Scripts/build.sh, then reopen SlapMe."
            showSetupGuide = true
        } else if !diagnostics.isAppleSilicon || !diagnostics.sensorPresent {
            setupNote = "Hardware may not support slap detection on this Mac."
            showSetupGuide = true
        } else {
            setupNote = "Admin access required once to start the sensor helper."
            showSetupGuide = true
        }
    }

    func grantHelperAccess() {
        guard !isLaunchingHelper else { return }
        isLaunchingHelper = true
        setupNote = "Waiting for macOS password prompt…"
        statusMessage = "Requesting admin access…"

        Task.detached(priority: .userInitiated) {
            do {
                try HelperLauncher.startHelperWithAdminPrompt()
                // Give the helper a moment to bind the socket
                try await Task.sleep(nanoseconds: 800_000_000)
                await MainActor.run {
                    self.isLaunchingHelper = false
                    self.refreshDiagnostics()
                    if self.helperConnected || self.diagnostics.helperProcessRunning {
                        self.statusMessage = "Helper started — connecting…"
                        self.setupNote = "Password accepted. Waiting for socket…"
                        self.showSetupGuide = !self.helperConnected
                    } else {
                        self.statusMessage = "Helper started but not connected yet"
                        self.setupNote = "If this sticks, open the helper log or copy the Terminal command."
                        self.showSetupGuide = true
                    }
                }
                // Extra settle time for socket client reconnect
                try await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    self.refreshDiagnostics()
                    if self.helperConnected {
                        self.statusMessage = "Helper connected"
                        self.setupNote = "Permissions look good."
                        self.showSetupGuide = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLaunchingHelper = false
                    self.statusMessage = error.localizedDescription
                    self.setupNote = error.localizedDescription
                    self.showSetupGuide = true
                    self.refreshDiagnostics()
                }
            }
        }
    }

    func copySetupCommand() {
        HelperLauncher.copySetupCommandToClipboard()
        setupNote = "Terminal command copied. Paste into Terminal and enter your password."
        statusMessage = "Setup command copied"
    }

    func startSocketClient() {
        let path = Paths.socketPath
        let client = SocketClient(path: path)
        client.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        client.onConnectionChange = { [weak self] connected in
            Task { @MainActor in
                self?.helperConnected = connected
                self?.statusMessage = connected
                    ? "Helper connected"
                    : "Helper offline — grant access below"
                if connected {
                    self?.showSetupGuide = false
                    self?.setupNote = "Permissions look good."
                } else {
                    self?.showSetupGuide = true
                }
                self?.refreshDiagnostics()
            }
        }
        client.start()
        socketClient = client
    }

    private func handle(_ event: HelperEvent) {
        switch event {
        case .hello:
            helperConnected = true
            statusMessage = "Helper connected"
        case .slap(let amplitude, _):
            guard listeningEnabled else { return }
            guard amplitude >= sensitivity else { return }
            let now = Date()
            guard now.timeIntervalSince(lastPlayAt) >= cooldown else { return }
            lastPlayAt = now
            lastAmplitude = amplitude
            lastSlapAt = now
            playSlap(amplitude: amplitude)
        }
    }

    private func playSlap(amplitude: Double) {
        guard let pack = selectedPack else {
            statusMessage = "No sound pack selected"
            return
        }
        var volume = masterVolume
        if volumeScaling {
            let scaled = min(1.0, max(0.25, amplitude / max(sensitivity * 4, 0.01)))
            volume *= scaled
        }
        do {
            try audioEngine.playRandom(from: pack, volume: volume)
            statusMessage = String(format: "Slap %.3fg → %@", amplitude, pack.name)
        } catch {
            statusMessage = "Audio error: \(error.localizedDescription)"
        }
    }

    func openTip() {
        if let url = URL(string: "https://ko-fi.com/633games") {
            NSWorkspace.shared.open(url)
        }
    }

    func openCustomPacksFolder() {
        NSWorkspace.shared.open(Paths.customPacksDirectory)
    }

    func searchSoundboard() {
        stopSoundboardPreview()
        let query = soundboardQuery
        isSearchingSoundboard = true
        soundboardNote = "Searching MyInstants…"
        soundboardResults = []

        Task {
            do {
                let clips = try await SoundboardImporter.search(query: query)
                await MainActor.run {
                    self.soundboardResults = clips
                    self.isSearchingSoundboard = false
                    self.soundboardNote = "Found \(clips.count) clips. You must have rights to use them."
                }
            } catch {
                await MainActor.run {
                    self.isSearchingSoundboard = false
                    self.soundboardNote = error.localizedDescription
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    struct SoundboardSaveTarget {
        let packName: String
        let isNSFW: Bool

        var folderComponents: [String] {
            if isNSFW {
                return ["nsfw", packName]
            }
            return [packName]
        }

        var packID: String {
            if isNSFW {
                return "nsfw.user.\(packName)"
            }
            // Bundled default still exists as sfw.default; user "default" is custom.default
            return packName == "default" ? "custom.default" : "custom.\(packName)"
        }

        var label: String {
            isNSFW ? "NSFW: \(packName)" : "Custom: \(packName)"
        }
    }

    /// Ask where to save; defaults to pack name "default" (Custom, not NSFW).
    func promptForSaveTarget(defaultPack: String = "default") -> SoundboardSaveTarget? {
        let alert = NSAlert()
        alert.messageText = "Save to soundboard pack"
        alert.informativeText = "Choose a pack folder name. “default” is used if you leave it blank."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let packField = NSTextField(string: defaultPack)
        packField.frame = NSRect(x: 0, y: 28, width: 260, height: 24)
        packField.placeholderString = "default"

        let nsfwBox = NSButton(checkboxWithTitle: "Save as NSFW pack", target: nil, action: nil)
        nsfwBox.state = .off
        nsfwBox.frame = NSRect(x: 0, y: 0, width: 260, height: 22)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        accessory.addSubview(packField)
        accessory.addSubview(nsfwBox)
        alert.accessoryView = accessory

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        var name = packField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "default" }
        name = sanitizePackName(name)
        return SoundboardSaveTarget(packName: name, isNSFW: nsfwBox.state == .on)
    }

    private func sanitizePackName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let filtered = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let collapsed = filtered
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "default" : String(collapsed.prefix(40)).lowercased()
    }

    func previewSoundboardClip(_ clip: SoundboardClip) {
        if previewingClipID == clip.id {
            audioEngine.stopPreview()
            previewingClipID = nil
            soundboardNote = "Preview stopped"
            return
        }
        audioEngine.previewRemote(url: clip.audioURL, volume: masterVolume)
        previewingClipID = clip.id
        soundboardNote = "Previewing \(clip.title) — Add… to save into a pack"
        statusMessage = "Preview: \(clip.title)"
    }

    func stopSoundboardPreview() {
        audioEngine.stopPreview()
        previewingClipID = nil
    }

    func downloadSoundboardClipAskingWhere(_ clip: SoundboardClip) {
        guard let target = promptForSaveTarget(defaultPack: "default") else { return }
        downloadSoundboardClip(clip, to: target)
    }

    func downloadTopSoundboardResultsAskingWhere(limit: Int = 5) {
        guard let target = promptForSaveTarget(defaultPack: "default") else { return }
        downloadTopSoundboardResults(limit: limit, to: target)
    }

    func downloadSoundboardClip(_ clip: SoundboardClip, to destination: SoundboardSaveTarget) {
        stopSoundboardPreview()
        isDownloadingSoundboard = true
        soundboardNote = "Downloading \(clip.title) → \(destination.label)…"

        Task {
            do {
                var dir = Paths.customPacksDirectory
                for component in destination.folderComponents {
                    dir = dir.appendingPathComponent(component, isDirectory: true)
                }
                let url = try await SoundboardImporter.download(clip, into: dir)
                await MainActor.run {
                    if destination.isNSFW {
                        self.nsfwEnabled = true
                    }
                    self.isDownloadingSoundboard = false
                    self.reloadPacks()
                    if self.packs.contains(where: { $0.id == destination.packID }) {
                        self.selectedPackID = destination.packID
                    }
                    self.soundboardNote = "Saved \(url.lastPathComponent) → \(destination.label)"
                    self.statusMessage = "Imported \(clip.title) → \(destination.label)"
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingSoundboard = false
                    self.soundboardNote = error.localizedDescription
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func downloadTopSoundboardResults(limit: Int = 5, to destination: SoundboardSaveTarget) {
        stopSoundboardPreview()
        let clips = Array(soundboardResults.prefix(limit))
        guard !clips.isEmpty else { return }
        isDownloadingSoundboard = true
        soundboardNote = "Downloading \(clips.count) clips → \(destination.label)…"

        Task {
            var ok = 0
            var dir = Paths.customPacksDirectory
            for component in destination.folderComponents {
                dir = dir.appendingPathComponent(component, isDirectory: true)
            }
            for clip in clips {
                do {
                    _ = try await SoundboardImporter.download(clip, into: dir)
                    ok += 1
                } catch {
                    continue
                }
            }
            await MainActor.run {
                if destination.isNSFW {
                    self.nsfwEnabled = true
                }
                self.isDownloadingSoundboard = false
                self.reloadPacks()
                if self.packs.contains(where: { $0.id == destination.packID }) {
                    self.selectedPackID = destination.packID
                }
                self.soundboardNote = "Imported \(ok)/\(clips.count) into \(destination.label)"
                self.statusMessage = self.soundboardNote ?? ""
            }
        }
    }

    func setSolidColor(_ color: Color) {
        iconTintMode = .solid
        iconColorHex = color.toHex() ?? iconColorHex
    }

    func quit() {
        NSApp.terminate(nil)
    }

    /// Quit helper, trash the app, and remove Application Support data (with confirmation).
    func uninstallFromMac() {
        let alert = NSAlert()
        alert.messageText = "Remove SlapMe from this Mac?"
        alert.informativeText = """
        This will:
        • Quit SlapMe and stop slapme-helper
        • Move SlapMe.app to Trash
        • Delete ~/Library/Application Support/SlapMe (packs & settings)
        • Remove the optional LaunchDaemon if installed

        Your Mac login password may be required to stop the helper.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        statusMessage = "Removing SlapMe…"

        // Stop helper (best-effort with admin)
        let stopScript = #"do shell script "pkill -x slapme-helper || true" with administrator privileges"#
        var err: NSDictionary?
        NSAppleScript(source: stopScript)?.executeAndReturnError(&err)

        let support = Paths.supportDirectory
        try? FileManager.default.removeItem(at: support)

        let plist = "/Library/LaunchDaemons/game.sixthree.slapme-helper.plist"
        if FileManager.default.fileExists(atPath: plist) {
            let unload = """
            do shell script "launchctl bootout system \(plist) 2>/dev/null || true; rm -f \(plist)" with administrator privileges
            """
            var unloadErr: NSDictionary?
            NSAppleScript(source: unload)?.executeAndReturnError(&unloadErr)
        }

        if let appURL = Bundle.main.bundleURL as URL?,
           appURL.pathExtension == "app" {
            try? FileManager.default.trashItem(at: appURL, resultingItemURL: nil)
        }

        NSApp.terminate(nil)
    }
}
