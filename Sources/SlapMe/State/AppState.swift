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
    @Published var muted: Bool = false
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
            guard listeningEnabled, !muted else { return }
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

    func previewSoundboardClip(_ clip: SoundboardClip) {
        if previewingClipID == clip.id {
            audioEngine.stopPreview()
            previewingClipID = nil
            soundboardNote = "Preview stopped"
            return
        }
        muted = false
        audioEngine.previewRemote(url: clip.audioURL, volume: masterVolume)
        previewingClipID = clip.id
        soundboardNote = "Previewing \(clip.title) — Add to keep it"
        statusMessage = "Preview: \(clip.title)"
    }

    func stopSoundboardPreview() {
        audioEngine.stopPreview()
        previewingClipID = nil
    }

    func downloadSoundboardClip(_ clip: SoundboardClip) {
        stopSoundboardPreview()
        isDownloadingSoundboard = true
        soundboardNote = "Downloading \(clip.title)…"

        Task {
            do {
                let dir = Paths.customPacksDirectory.appendingPathComponent("soundboard", isDirectory: true)
                let url = try await SoundboardImporter.download(clip, into: dir)
                await MainActor.run {
                    self.isDownloadingSoundboard = false
                    self.reloadPacks()
                    if self.packs.contains(where: { $0.id == "custom.soundboard" }) {
                        self.selectedPackID = "custom.soundboard"
                    }
                    self.soundboardNote = "Saved \(url.lastPathComponent) → Custom: soundboard"
                    self.statusMessage = "Imported \(clip.title)"
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

    func downloadTopSoundboardResults(limit: Int = 5) {
        stopSoundboardPreview()
        let clips = Array(soundboardResults.prefix(limit))
        guard !clips.isEmpty else { return }
        isDownloadingSoundboard = true
        soundboardNote = "Downloading \(clips.count) clips…"

        Task {
            var ok = 0
            let dir = Paths.customPacksDirectory.appendingPathComponent("soundboard", isDirectory: true)
            for clip in clips {
                do {
                    _ = try await SoundboardImporter.download(clip, into: dir)
                    ok += 1
                } catch {
                    continue
                }
            }
            await MainActor.run {
                self.isDownloadingSoundboard = false
                self.reloadPacks()
                if self.packs.contains(where: { $0.id == "custom.soundboard" }) {
                    self.selectedPackID = "custom.soundboard"
                }
                self.soundboardNote = "Imported \(ok)/\(clips.count) into Custom: soundboard"
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
}
