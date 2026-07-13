import SwiftUI

struct SetupGuideView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Permissions needed", systemImage: "lock.shield")
                .font(.headline)

            Text("Slap detection reads your MacBook’s accelerometer. macOS only allows that with admin access for a small helper process.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            diagnosticList

            if !appState.diagnostics.isAppleSilicon || !appState.diagnostics.sensorPresent {
                Text(hardwareWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                appState.grantHelperAccess()
            } label: {
                if appState.isLaunchingHelper {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Grant access & start helper…")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLaunchingHelper || !appState.diagnostics.helperBinaryFound)

            VStack(alignment: .leading, spacing: 4) {
                Text("What happens next")
                    .font(.caption.weight(.semibold))
                Text("1. macOS asks for your login password")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("2. SlapMe starts slapme-helper as root (sensor only)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("3. This menu turns green when connected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Copy Terminal command") {
                    appState.copySetupCommand()
                }
                Button("Recheck") {
                    appState.refreshDiagnostics()
                }
                Button("Open log") {
                    HelperLauncher.openHelperLog()
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)

            if let note = appState.setupNote, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(appState.helperConnected ? .green : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var diagnosticList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(appState.diagnostics.summaryLines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: icon(for: line))
                        .font(.caption2)
                        .foregroundStyle(tint(for: line))
                        .frame(width: 12)
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var hardwareWarning: String {
        if !appState.diagnostics.isAppleSilicon {
            return "This Mac doesn’t look like Apple Silicon. SlapMe won’t work on Intel or desktops without the SPU sensor."
        }
        return "Accelerometer not detected. Confirm you’re on a supported MacBook (most M2+ / M1 Pro)."
    }

    private func icon(for line: String) -> String {
        let bad = line.contains(": no") || line.contains("not found") || line.contains("not running") || line.contains("missing")
        return bad ? "xmark.circle.fill" : "checkmark.circle.fill"
    }

    private func tint(for line: String) -> Color {
        let bad = line.contains(": no") || line.contains("not found") || line.contains("not running") || line.contains("missing")
        return bad ? .orange : .green
    }
}
