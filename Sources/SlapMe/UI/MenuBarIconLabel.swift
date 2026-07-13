import SwiftUI

/// Preview swatch inside the popover (menu bar itself stays a template SF Symbol).
struct IconPreview: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TimelineView(.animation(minimumInterval: appState.iconTintMode == .pride ? 1.0 / 20.0 : 60.0)) { timeline in
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(tint(at: timeline.date))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tint(at date: Date) -> Color {
        if appState.iconTintMode == .pride {
            let t = date.timeIntervalSinceReferenceDate
            return Color(
                hue: (t * 0.15).truncatingRemainder(dividingBy: 1.0),
                saturation: 0.85,
                brightness: 1.0
            )
        }
        return appState.iconColor
    }
}
