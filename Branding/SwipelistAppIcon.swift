import SwiftUI

/// Swipelist app icon — variant 3b: "waveform card".
/// Three fanned cards; the leading card is lime with four bars knocked out of it.
///
/// All geometry is expressed as a fraction of `size`, so this renders identically
/// at 1024 (App Store artwork) and at 40 (Spotlight).
///
/// Usage:
///     SwipelistAppIcon(size: 180)                       // masked, for in-app / previews
///     SwipelistAppIcon(size: 1024, masked: false)       // App Store Connect artwork
struct SwipelistAppIcon: View {
    var size: CGFloat = 180
    /// `true` applies the iOS superellipse mask + drop shadow (in-app use).
    /// Must be `false` for the 1024² asset you submit — Apple applies the mask.
    var masked: Bool = true

    // MARK: Palette
    private let lime      = Color(red: 0.831, green: 1.000, blue: 0.247) // #D4FF3F
    private let ink       = Color(red: 0.043, green: 0.043, blue: 0.051) // #0B0B0D
    private let cardBack  = Color(red: 0.078, green: 0.078, blue: 0.094) // #141418
    private let cardMid   = Color(red: 0.114, green: 0.114, blue: 0.133) // #1D1D22
    private let bgTop     = Color(red: 0.102, green: 0.102, blue: 0.125) // #1A1A20
    private let bgEdge    = Color(red: 0.024, green: 0.024, blue: 0.039) // #06060A

    // MARK: Geometry (fractions of `size`)
    private let cardSide: CGFloat      = 0.40
    private let cardRadius: CGFloat    = 0.075
    private let strokeWidth: CGFloat   = 0.010

    private let backAngle: Double      = -16
    private let backOffset  = CGSize(width: -0.105, height:  0.028)
    private let midAngle: Double       = -7
    private let midOffset   = CGSize(width: -0.045, height:  0.008)
    private let frontAngle: Double     = 9
    private let frontOffset = CGSize(width:  0.075, height: -0.022)

    private let barWidth: CGFloat      = 0.040
    private let barRadius: CGFloat     = 0.020
    private let barGap: CGFloat        = 0.026
    private let barHeights: [CGFloat]  = [0.13, 0.23, 0.17, 0.27]

    var body: some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: bgTop,  location: 0.00),
                    .init(color: ink,    location: 0.62),
                    .init(color: bgEdge, location: 1.00)
                ]),
                center: UnitPoint(x: 0.42, y: 0.28),
                startRadius: 0,
                endRadius: size * 0.78
            )

            card(fill: cardBack, strokeOpacity: 0.09)
                .rotationEffect(.degrees(backAngle))
                .offset(x: backOffset.width * size, y: backOffset.height * size)

            card(fill: cardMid, strokeOpacity: 0.13)
                .rotationEffect(.degrees(midAngle))
                .offset(x: midOffset.width * size, y: midOffset.height * size)

            leadingCard
                .rotationEffect(.degrees(frontAngle))
                .offset(x: frontOffset.width * size, y: frontOffset.height * size)
                .shadow(color: .black.opacity(0.6), radius: size * 0.05, x: -size * 0.02, y: 0)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: masked ? size * 0.2237 : 0, style: .continuous))
        .shadow(color: masked ? .black.opacity(0.5) : .clear,
                radius: size * 0.07, x: 0, y: size * 0.03)
    }

    private func card(fill: Color, strokeOpacity: Double) -> some View {
        RoundedRectangle(cornerRadius: cardRadius * size, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius * size, style: .continuous)
                    .strokeBorder(.white.opacity(strokeOpacity), lineWidth: strokeWidth * size)
            )
            .frame(width: cardSide * size, height: cardSide * size)
    }

    /// Lime card with the waveform punched out, so the bars show the backdrop
    /// rather than a painted-on dark. Swap `.blendMode(.destinationOut)` for a
    /// plain `ink` fill if you need a flattened, compositing-free version.
    private var leadingCard: some View {
        RoundedRectangle(cornerRadius: cardRadius * size, style: .continuous)
            .fill(lime)
            .frame(width: cardSide * size, height: cardSide * size)
            .overlay(waveform)
    }

    private var waveform: some View {
        HStack(spacing: barGap * size) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, h in
                RoundedRectangle(cornerRadius: barRadius * size, style: .continuous)
                    .fill(ink)
                    .frame(width: barWidth * size, height: h * size)
            }
        }
    }
}

#Preview("Size ladder") {
    HStack(alignment: .bottom, spacing: 20) {
        ForEach([180, 120, 80, 58, 40], id: \.self) { s in
            SwipelistAppIcon(size: CGFloat(s))
        }
    }
    .padding(40)
    .background(Color(red: 0.055, green: 0.055, blue: 0.063))
}

#Preview("1024 artwork") {
    SwipelistAppIcon(size: 1024, masked: false)
        .scaleEffect(0.3)
        .frame(width: 320, height: 320)
}
