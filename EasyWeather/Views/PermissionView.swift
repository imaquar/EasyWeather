import SwiftUI

struct PermissionView: View {
    let onOpenAppSettings: () -> Void
    let onOpenInAppSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Location is off. Enable it in Settings.")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("You can also choose a city in the in-app Settings screen.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Open iOS Settings", action: onOpenAppSettings)
                .buttonStyle(.glassProminent)

            Button("Open In-App Settings", action: onOpenInAppSettings)
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(14)
        .liquidGlassCard()
    }
}
