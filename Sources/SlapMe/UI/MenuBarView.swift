import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showSoundDownloader = false
    @State private var showCustomise = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                helperStatusSection

                if !appState.helperConnected || appState.showSetupGuide {
                    VStack(alignment: .leading, spacing: 8) {
                        SetupGuideView()
                        if appState.helperConnected {
                            Button("Hide setup guide") {
                                appState.showSetupGuide = false
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
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
                packPickerSection
                Divider()
                sensitivitySection
                Divider()

                disclosureButton(title: "Sound Downloader", isExpanded: $showSoundDownloader)
                if showSoundDownloader {
                    soundDownloaderSection
                        .padding(.leading, 4)
                }

                Divider()

                disclosureButton(title: "Customise", isExpanded: $showCustomise)
                if showCustomise {
                    customiseSection
                        .padding(.leading, 4)
                }

                Divider()

                Button("Quit SlapMe") {
                    appState.quit()
                }
                .buttonStyle(.bordered)

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
        HStack(alignment: .center, spacing: 10) {
            Text("SlapMe")
                .font(.title3.weight(.bold))
            Spacer(minLength: 8)
            Button("Drop me a tip") {
                appState.openTip()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
        }
    }

    private var helperStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

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

            Toggle("Listen for slaps", isOn: $appState.listeningEnabled)
            Toggle("Enable NSFW packs", isOn: $appState.nsfwEnabled)
            Toggle("Scale volume with slap force", isOn: $appState.volumeScaling)
        }
    }

    private var packPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sound pack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Sound pack", selection: $appState.selectedPackID) {
                ForEach(appState.packs) { pack in
                    Text(pack.name).tag(pack.id)
                }
            }
            .labelsHidden()
            HStack {
                Button("Reload packs") {
                    appState.reloadPacks()
                }
                Button("Open packs folder") {
                    appState.openCustomPacksFolder()
                }
            }
            .font(.caption)
        }
    }

    private var sensitivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledSlider("Sensitivity (threshold)", value: $appState.sensitivity, range: 0.01...0.35)
            labeledSlider("Cooldown (s)", value: $appState.cooldown, range: 0.2...2.0)
            labeledSlider("Volume", value: $appState.masterVolume, range: 0...1)
        }
    }

    private var soundDownloaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search MyInstants, preview, then Add to a custom pack (default: “default”).")
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

            if !appState.soundboardResults.isEmpty {
                HStack {
                    Button("Add top 5…") {
                        appState.downloadTopSoundboardResultsAskingWhere(limit: 5)
                    }
                    .disabled(appState.isDownloadingSoundboard)
                    if appState.previewingClipID != nil {
                        Button("Stop preview") {
                            appState.stopSoundboardPreview()
                        }
                    }
                    Spacer()
                }
                .font(.caption)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.soundboardResults.prefix(12)) { clip in
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
                            Button("Add…") {
                                appState.downloadSoundboardClipAskingWhere(clip)
                            }
                            .font(.caption2)
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.isDownloadingSoundboard)
                        }
                    }
                }
            }
        }
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

    private func disclosureButton(title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
