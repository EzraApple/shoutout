import SwiftUI

struct ModelProgressBar: View {
    let progress: Double
    var height: CGFloat = 7

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.95), Color.blue.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth(in: proxy.size.width))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.2), value: clampedProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Model download progress")
        .accessibilityValue("\(Int(clampedProgress * 100)) percent")
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        guard clampedProgress > 0 else { return 0 }
        return max(width * CGFloat(clampedProgress), height)
    }
}
