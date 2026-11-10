import SwiftUI

struct HUDView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
