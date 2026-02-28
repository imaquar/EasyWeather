import SwiftUI

struct ErrorView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        Button(action: retryAction) {
            Text(message)
                .font(.system(.headline, design: .default, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.glass)
    }
}
