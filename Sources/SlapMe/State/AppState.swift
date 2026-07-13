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
    @Published var listeningEnabled: Bool {
        didSet { defaults.set(listeningEnabled, forKey: Keys.listeningEnabled) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }
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
    /// Visible page within the current search batch (5 clips each).
    @Published var soundboardPage: Int = 1
    /// MyInstants search page currently loaded into `soundboardResults`.
    @Published var soundboardSitePage: Int = 1
    @Published var soundboardSiteHasMore: Bool = false
    @Published var isSearchingSoundboard = false
    @Published var isDownloadingSoundboard = false
    @Published var soundboardNote: String?
    @Published var previewingClipID: String?
    @Published var newPackName: String = "my-pack"
    @Published var newPackIsNSFW: Bool = false

    let packManager = PackManager()
    let audioEngine = AudioEngine()

    private let defaults = UserDefaults.standard
    private var socketClient: SocketClient?
    private var lastPlayAt: Date = .distantPast

    private enum Keys {
        static let listeningEnabled = "listeningEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let sensitivity = "sensitivity"
        static let cooldown = "cooldown"
        static let volumeScaling = "volumeScaling"
        static let masterVolume = "masterVolume"
        static let nsfwEnabled = "nsfwEnabled"
        static let selectedPackID = "selectedPackID"
        static let iconTintMode = "iconTintMode"
        static let iconColorHex = "iconColorHex"
        static let helperEverConnected = "helperEverConnected"
        static let settingsVersion = "settingsVersion"
    }

    var selectedPack: SoundPack? {
        packs.first { $0.id == selectedPackID } ?? packs.first
    }

    func reloadPacks() {
        // NSFW packs appear whenever Packs/nsfw/… folders exist (no UI gate).
        packManager.reload(nsfwEnabled: true)
        packs = packManager.packs
        if !packs.contains(where: { $0.id == selectedPackID }) {
            selectedPackID = packManager.defaultPackID
        }
    }

    var iconColor: Color {
        Color(hex: iconColorHex) ?? .pink
    }

    init() {
        // One-time bump to the recommended defaults (keeps later user edits).
        if defaults.integer(forKey: Keys.settingsVersion) < 2 {
            defaults.set(0.20, forKey: Keys.sensitivity)
            defaults.set(0.65, forKey: Keys.cooldown)
            defaults.set(0.7, forKey: Keys.masterVolume)
            defaults.set(true, forKey: Keys.launchAtLogin)
            defaults.set(2, forKey: Keys.settingsVersion)
        }
        if defaults.integer(forKey: Keys.settingsVersion) < 3 {
            defaults.set(true, forKey: Keys.volumeScaling)
            defaults.set(3, forKey: Keys.settingsVersion)
        }

        listeningEnabled = defaults.object(forKey: Keys.listeningEnabled) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? true
        sensitivity = defaults.object(forKey: Keys.sensitivity) as? Double ?? 0.20
        cooldown = defaults.object(forKey: Keys.cooldown) as? Double ?? 0.65
        volumeScaling = defaults.object(forKey: Keys.volumeScaling) as? Bool ?? true
        masterVolume = defaults.object(forKey: Keys.masterVolume) as? Double ?? 0.7
        nsfwEnabled = defaults.bool(forKey: Keys.nsfwEnabled)
        selectedPackID = defaults.string(forKey: Keys.selectedPackID) ?? "sfw.default"
        iconTintMode = IconTintMode(rawValue: defaults.string(forKey: Keys.iconTintMode) ?? "") ?? .solid
        iconColorHex = defaults.string(forKey: Keys.iconColorHex) ?? "#FF4D6D"

        Paths.ensureSupportDirectories()
        reloadPacks()
        let helperKnown = defaults.bool(forKey: Keys.helperEverConnected)
        showSetupGuide = !helperKnown
        setupNote = helperKnown
            ? "Reconnecting to helper…"
            : "Admin access required once to start the sensor helper."
        startSocketClient()
        applyLaunchAtLogin()

        Task { @MainActor in
            self.refreshDiagnostics()
            if self.diagnostics.helperProcessRunning {
                self.showSetupGuide = false
                self.setupNote = "Helper running from last session."
            }
        }
    }

    private func applyLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(launchAtLogin)
        } catch {
            statusMessage = "Start at login: \(error.localizedDescription)"
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
                        self.setupNote = "Password accepted — helper installed for reboot. Waiting for socket…"
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
                    self?.defaults.set(true, forKey: Keys.helperEverConnected)
                    self?.showSetupGuide = false
                    self?.setupNote = "Permissions look good."
                } else if self?.defaults.bool(forKey: Keys.helperEverConnected) == true {
                    // Keep guide collapsed after first successful setup; user can reopen.
                    self?.showSetupGuide = false
                    self?.setupNote = "Helper offline — use Grant access if needed."
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

    static let soundboardPageSize = 5

    var visibleSoundboardClips: [SoundboardClip] {
        let start = (soundboardPage - 1) * Self.soundboardPageSize
        guard start < soundboardResults.count else { return [] }
        return Array(soundboardResults[start..<min(start + Self.soundboardPageSize, soundboardResults.count)])
    }

    var soundboardLocalPageCount: Int {
        max(1, Int(ceil(Double(soundboardResults.count) / Double(Self.soundboardPageSize))))
    }

    var soundboardCanGoPrevious: Bool {
        soundboardPage > 1 || soundboardSitePage > 1
    }

    var soundboardCanGoNext: Bool {
        soundboardPage < soundboardLocalPageCount || soundboardSiteHasMore
    }

    func searchSoundboard(sitePage: Int = 1, jumpToLastLocalPage: Bool = false) {
        stopSoundboardPreview()
        let query = soundboardQuery
        let site = max(1, sitePage)
        isSearchingSoundboard = true
        soundboardNote = site == 1 ? "Searching MyInstants…" : "Loading more…"
        soundboardResults = []
        soundboardPage = 1
        soundboardSiteHasMore = false

        Task {
            do {
                let result = try await SoundboardImporter.search(query: query, page: site)
                await MainActor.run {
                    self.soundboardResults = result.clips
                    self.soundboardSitePage = result.page
                    self.soundboardSiteHasMore = result.hasMore
                    let localCount = max(1, Int(ceil(Double(result.clips.count) / Double(Self.soundboardPageSize))))
                    self.soundboardPage = jumpToLastLocalPage ? localCount : 1
                    self.isSearchingSoundboard = false
                    if result.clips.isEmpty {
                        self.soundboardNote = "No more clips."
                    } else {
                        self.soundboardNote = "\(result.clips.count) clips — 5 per page. You must have rights to use them."
                    }
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

    func soundboardGoToAdjacentPage(_ delta: Int) {
        if delta < 0 {
            if soundboardPage > 1 {
                soundboardPage -= 1
                stopSoundboardPreview()
            } else if soundboardSitePage > 1 {
                searchSoundboard(sitePage: soundboardSitePage - 1, jumpToLastLocalPage: true)
            }
            return
        }
        if soundboardPage < soundboardLocalPageCount {
            soundboardPage += 1
            stopSoundboardPreview()
        } else if soundboardSiteHasMore {
            searchSoundboard(sitePage: soundboardSitePage + 1)
        }
    }

    struct SoundboardSaveTarget: Identifiable, Hashable {
        static let sfwDefaultID = "sfw.default.save"
        static let newPackID = "__new__"

        let id: String
        let packName: String
        let isNSFW: Bool
        let title: String

        var folderComponents: [String] {
            if isNSFW {
                return ["nsfw", packName]
            }
            if id == Self.sfwDefaultID {
                return ["sfw", "default"]
            }
            if id.hasPrefix("sfw.") {
                return ["sfw", packName]
            }
            return [packName]
        }

        var packIDAfterSave: String {
            if isNSFW {
                return "nsfw.user.\(packName)"
            }
            if id == Self.sfwDefaultID {
                return "sfw.user.default"
            }
            if id.hasPrefix("sfw.") {
                return "sfw.user.\(packName)"
            }
            return "custom.\(packName)"
        }

        static var sfwDefault: SoundboardSaveTarget {
            SoundboardSaveTarget(
                id: sfwDefaultID,
                packName: "default",
                isNSFW: false,
                title: "Default"
            )
        }

        static var newPackOption: SoundboardSaveTarget {
            SoundboardSaveTarget(
                id: newPackID,
                packName: "new",
                isNSFW: false,
                title: "+ New pack…"
            )
        }
    }

    /// Pack destinations for the Add menu (SFW Default first). Excludes “new pack”.
    var menuSaveDestinations: [SoundboardSaveTarget] {
        var options: [SoundboardSaveTarget] = [.sfwDefault]

        for pack in packs {
            if pack.id == "sfw.default" || pack.id == "sfw.user.default" { continue }

            let isNSFW = pack.category == .nsfw
            let name: String
            if pack.id.hasPrefix("nsfw.user.") {
                name = String(pack.id.dropFirst("nsfw.user.".count))
            } else if pack.id.hasPrefix("sfw.user.") {
                name = String(pack.id.dropFirst("sfw.user.".count))
            } else if pack.id.hasPrefix("custom.") {
                name = String(pack.id.dropFirst("custom.".count))
            } else if pack.id.hasPrefix("sfw.") {
                name = String(pack.id.dropFirst("sfw.".count))
            } else if pack.id.hasPrefix("nsfw.") {
                name = String(pack.id.dropFirst("nsfw.".count))
            } else {
                name = pack.id
            }

            options.append(
                SoundboardSaveTarget(
                    id: pack.id,
                    packName: name,
                    isNSFW: isNSFW,
                    title: pack.name
                )
            )
        }

        return options
    }

    func makeNewPackTarget() -> SoundboardSaveTarget {
        var name = sanitizePackName(newPackName)
        if name.isEmpty { name = "my-pack" }
        let nsfw = nsfwEnabled && newPackIsNSFW
        return SoundboardSaveTarget(
            id: SoundboardSaveTarget.newPackID,
            packName: name,
            isNSFW: nsfw,
            title: nsfw ? "NSFW: \(name)" : "Custom: \(name)"
        )
    }

    private func sanitizePackName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let filtered = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let collapsed = filtered
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(collapsed.prefix(40)).lowercased()
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
        soundboardNote = "Previewing \(clip.title)"
        statusMessage = "Preview: \(clip.title)"
    }

    func stopSoundboardPreview() {
        audioEngine.stopPreview()
        previewingClipID = nil
    }

    func downloadSoundboardClip(_ clip: SoundboardClip, to destination: SoundboardSaveTarget) {
        stopSoundboardPreview()
        isDownloadingSoundboard = true
        soundboardNote = "Downloading \(clip.title) → \(destination.title)…"

        Task {
            do {
                var dir = Paths.customPacksDirectory
                for component in destination.folderComponents {
                    dir = dir.appendingPathComponent(component, isDirectory: true)
                }
                let url = try await SoundboardImporter.download(clip, into: dir)
                await MainActor.run {
                    self.isDownloadingSoundboard = false
                    self.reloadPacks()
                    let preferID = destination.packIDAfterSave
                    if self.packs.contains(where: { $0.id == preferID }) {
                        self.selectedPackID = preferID
                    } else if destination.id == SoundboardSaveTarget.sfwDefaultID,
                              self.packs.contains(where: { $0.id == "sfw.default" }) {
                        self.selectedPackID = "sfw.default"
                    }
                    self.soundboardNote = "Saved \(url.lastPathComponent) → \(destination.title)"
                    self.statusMessage = "Imported \(clip.title) → \(destination.title)"
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

        try? LaunchAtLogin.setEnabled(false)

        // Stop helper + LaunchDaemon (best-effort with admin)
        let stopScript = #"do shell script "launchctl bootout system /Library/LaunchDaemons/game.sixthree.slapme-helper.plist 2>/dev/null || true; pkill -x slapme-helper || true; rm -f /Library/LaunchDaemons/game.sixthree.slapme-helper.plist; rm -rf '/Library/Application Support/SlapMe'" with administrator privileges"#
        var err: NSDictionary?
        NSAppleScript(source: stopScript)?.executeAndReturnError(&err)

        let support = Paths.supportDirectory
        try? FileManager.default.removeItem(at: support)

        if let appURL = Bundle.main.bundleURL as URL?,
           appURL.pathExtension == "app" {
            try? FileManager.default.trashItem(at: appURL, resultingItemURL: nil)
        }

        NSApp.terminate(nil)
    }
}
