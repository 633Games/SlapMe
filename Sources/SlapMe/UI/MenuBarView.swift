import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var activePanel: ActivePanel = .downloader
    /// When set, show the in-popover “new pack” form (not a separate window).
    @State private var pendingNewPack: PendingNewPack?

    private enum ActivePanel {
        case none
        case settings
        case customise
        case downloader
    }

    private enum PendingNewPack {
        case clip(SoundboardClip)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                listenButton

                if activePanel == .settings {
                    settingsSection
                } else if activePanel == .customise {
                    customiseSection
                }

                Divider()
                packPickerSection

                if activePanel == .downloader {
                    soundDownloaderSection
                        .padding(.top, 4)
                }

                Divider()

                Text("╰(✿´⌣`✿)╯♡")
                    .font(.title2.bold())
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.90, green: 0.10, blue: 0.22),
                                Color(red: 1.00, green: 0.55, blue: 0.00),
                                Color(red: 1.00, green: 0.90, blue: 0.10),
                                Color(red: 0.15, green: 0.75, blue: 0.30),
                                Color(red: 0.15, green: 0.55, blue: 0.95),
                                Color(red: 0.48, green: 0.20, blue: 0.85),
                                Color(red: 0.90, green: 0.30, blue: 0.70),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)

                Button("Remove SlapMe from this Mac…", role: .destructive) {
                    appState.uninstallFromMac()
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .frame(width: 340)
        }
        .frame(width: 360, height: 620)
        .onAppear {
            appState.refreshDiagnostics()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("SlapMe")
                .font(.title3.weight(.bold))
            panelIconButton(
                systemName: "gearshape",
                panel: .settings,
                help: "Settings"
            )
            panelIconButton(
                systemName: "paintbrush",
                panel: .customise,
                help: "Customise"
            )
            Spacer(minLength: 8)
            Button("Drop me a tip") {
                appState.openTip()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
            Button("Quit") {
                appState.quit()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var listenButton: some View {
        Button {
            appState.listeningEnabled.toggle()
        } label: {
            HStack {
                Image(systemName: appState.listeningEnabled ? "hand.raised.fill" : "hand.raised.slash")
                Text(appState.listeningEnabled ? "Listening for slaps" : "Listen for slaps")
                Spacer(minLength: 4)
                Text(appState.listeningEnabled ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appState.listeningEnabled ? Color.green : Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(appState.listeningEnabled ? .green : nil)
        .controlSize(.large)
    }

    private func panelIconButton(systemName: String, panel: ActivePanel, help: String) -> some View {
        let selected = activePanel == panel
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activePanel = selected ? .none : panel
            }
        } label: {
            Image(systemName: selected ? "\(systemName).fill" : systemName)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Circle()
                    .fill(appState.helperConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(appState.helperConnected ? "Helper online" : "Helper offline")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let at = appState.lastSlapAt {
                    Spacer()
                    Text(String(format: "Last %.3fg", appState.lastAmplitude))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(at, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !appState.helperConnected || appState.showSetupGuide {
                SetupGuideView()
                if appState.helperConnected {
                    Button("Hide setup guide") {
                        appState.showSetupGuide = false
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            } else {
                Button("Permissions / helper details") {
                    appState.showSetupGuide = true
                    appState.refreshDiagnostics()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }

            Divider()

            Toggle("Scale volume with slap force", isOn: $appState.volumeScaling)
            Toggle("Start SlapMe at login", isOn: $appState.launchAtLogin)
            labeledSlider("Sensitivity (threshold)", value: $appState.sensitivity, range: 0.01...0.35)
            labeledSlider("Cooldown (s)", value: $appState.cooldown, range: 0.2...2.0)
            labeledSlider("Volume", value: $appState.masterVolume, range: 0...1)
        }
    }

    private var packPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sound pack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Picker("Sound pack", selection: $appState.selectedPackID) {
                    ForEach(appState.packs) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                .labelsHidden()
                Button {
                    appState.reloadPacks()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload packs")
                .accessibilityLabel("Reload packs")
                Button {
                    appState.openCustomPacksFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Open packs folder")
                .accessibilityLabel("Open packs folder")
                panelIconButton(
                    systemName: "arrow.down.circle",
                    panel: .downloader,
                    help: "Sound Downloader"
                )
            }
        }
    }

    private var soundDownloaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search MyInstants, preview, then Add and pick a pack from the menu.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                TextField("Search…", text: $appState.soundboardQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { appState.searchSoundboard() }
                Button("Search") {
                    appState.searchSoundboard()
                }
                .disabled(
                    appState.isSearchingSoundboard
                        || appState.soundboardQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if pendingNewPack != nil {
                newPackForm
            }

            if appState.isSearchingSoundboard || appState.isDownloadingSoundboard {
                ProgressView()
                    .controlSize(.small)
            }

            if let note = appState.soundboardNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !appState.visibleSoundboardClips.isEmpty || !appState.soundboardResults.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.visibleSoundboardClips) { clip in
                        HStack(spacing: 6) {
                            Text(clip.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Button(appState.previewingClipID == clip.id ? "Stop" : "Preview") {
                                appState.previewSoundboardClip(clip)
                            }
                            .font(.caption2)
                            .disabled(appState.isDownloadingSoundboard)

                            addDestinationMenu(title: "Add") {
                                pendingNewPack = .clip(clip)
                            } onPick: { destination in
                                appState.downloadSoundboardClip(clip, to: destination)
                            }
                            .font(.caption2)
                            .disabled(appState.isDownloadingSoundboard)
                        }
                    }
                }

                HStack {
                    Button {
                        appState.soundboardGoToAdjacentPage(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(appState.isSearchingSoundboard || !appState.soundboardCanGoPrevious)

                    Text("Page \(appState.soundboardPage)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 64)

                    Button {
                        appState.soundboardGoToAdjacentPage(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(appState.isSearchingSoundboard || !appState.soundboardCanGoNext)

                    Spacer()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var newPackForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New pack")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Pack name", text: $appState.newPackName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") {
                    pendingNewPack = nil
                }
                Button("Save here") {
                    confirmNewPack()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isDownloadingSoundboard)
                Spacer()
            }
            .font(.caption)
        }
        .padding(8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func addDestinationMenu(
        title: String,
        onNewPack: @escaping () -> Void,
        onPick: @escaping (AppState.SoundboardSaveTarget) -> Void
    ) -> some View {
        Menu {
            ForEach(appState.menuSaveDestinations) { destination in
                Button(destination.title) {
                    onPick(destination)
                }
            }
            Divider()
            Button("+ New pack…") {
                onNewPack()
            }
        } label: {
            Text(title)
        }
    }

    private func confirmNewPack() {
        let destination = appState.makeNewPackTarget()
        if case .clip(let clip) = pendingNewPack {
            appState.downloadSoundboardClip(clip, to: destination)
        }
        pendingNewPack = nil
    }

    private var customiseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Menu bar icon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            IconPreview()

            Picker("Tint", selection: $appState.iconTintMode) {
                ForEach(IconTintMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if appState.iconTintMode == .solid {
                HStack(spacing: 6) {
                    ForEach(IconPresets.colors, id: \.0) { name, color in
                        Button {
                            appState.setSolidColor(color)
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1)
                                )
                                .accessibilityLabel(name)
                        }
                        .buttonStyle(.plain)
                    }
                    ColorPicker("", selection: Binding(
                        get: { appState.iconColor },
                        set: { appState.setSolidColor($0) }
                    ))
                    .labelsHidden()
                    .frame(width: 28)
                }
            } else {
                Text("Pride — rainbow cycles on the menu bar hand")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
