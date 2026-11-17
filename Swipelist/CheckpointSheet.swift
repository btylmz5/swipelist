import SwiftUI

struct CheckpointSheet: View {
    let count: Int
    let arts: [Track]
    var onKeep: () -> Void = {}
    var onFinish: () -> Void = {}

    private let rotations: [Double] = [-9, -4, 0, 4, 8]
    private let scales: [Double] = [0.82, 0.9, 0.96, 1.02, 1.08]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Text("\(count) songs in.")
                .font(.swTitle)
                .tracking(-0.3)
                .foregroundStyle(Color.swTextPrimary)
                .padding(.top, 28)

            Text("That's about \(Format.longDuration(count)).")
                .font(.swBody)
                .foregroundStyle(Color.swTextSecondary)
                .padding(.top, 8)

            fan
                .padding(.top, 32)
                .padding(.bottom, 36)

            Button(action: onKeep) {
                Text("Keep swiping")
                    .font(.swHeadline)
                    .foregroundStyle(Color.swOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.swAccent, in: RoundedRectangle(cornerRadius: 14))
            }

            Button(action: onFinish) {
                Text("Finish playlist")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.swTextPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .presentationBackground {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.swSurfaceSheet.opacity(0.6))
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
                }
        }
    }

    private var fan: some View {
        HStack(spacing: -26) {
            ForEach(arts.indices, id: \.self) { i in
                TrackArtView(track: arts[i])
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .rotationEffect(.degrees(rotations[i % rotations.count]))
                    .scaleEffect(scales[i % scales.count])
                    .shadow(color: .black.opacity(0.5 + Double(i) * 0.04), radius: 10 + Double(i) * 2, y: 8 + Double(i) * 1.5)
            }
        }
    }
}
