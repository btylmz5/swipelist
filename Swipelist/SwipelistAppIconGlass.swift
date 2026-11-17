import SwiftUI

// MARK: - Swipelist app icon, liquid-glass build (variant 3b geometry)
//
// Three fanned cards; the leading card carries a four-bar waveform.
// Geometry is identical across appearances — only the material changes.
// Every dimension is a fraction of `size`, so 40pt and 1024pt are the same drawing.
//
//     SwipelistAppIcon(size: 180)                                  // dark, masked
//     SwipelistAppIcon(size: 180, appearance: .light)
//     SwipelistAppIcon(size: 180, appearance: .tinted(.lime))
//     SwipelistAppIcon(size: 1024, appearance: .dark, masked: false) // submission artwork
//
// For Icon Composer: prefer the layered export (AppIcon-glass-*.svg) and let
// Apple's renderer apply its own specular/shadow instead of these baked ones.

struct SwipelistAppIcon: View {

    enum Tint {
        case lime, indigo, slate, violet

        /// highlight, mid, shadow — drives the tinted-mode field and bar cut-outs.
        var ramp: (Color, Color, Color) {
            switch self {
            case .lime:   return (h("#4E6410"), h("#2C3A08"), h("#161D04"))
            case .indigo: return (h("#3A3F86"), h("#232752"), h("#12142E"))
            case .slate:  return (h("#3A4048"), h("#242A31"), h("#12161B"))
            case .violet: return (h("#4B2C7A"), h("#301A52"), h("#180D2A"))
            }
        }
    }

    enum Appearance: Equatable {
        case dark, light
        case tinted(Tint)
    }

    var size: CGFloat = 180
    var appearance: Appearance = .dark
    /// `true` applies the iOS superellipse mask + drop shadow (in-app, previews).
    /// Must be `false` for the 1024² asset you ship — the system applies the mask.
    var masked: Bool = true

    // MARK: Geometry (fractions of `size`) — shared by all appearances
    private let cardSide: CGFloat   = 0.47
    private let cardRadius: CGFloat = 0.088
    private let hairline: CGFloat   = 0.009

    private let backAngle: Double   = -16
    private let backOffset  = CGSize(width: -0.123, height:  0.033)
    private let midAngle: Double    = -7
    private let midOffset   = CGSize(width: -0.053, height:  0.009)
    private let frontAngle: Double  = 9
    private let frontOffset = CGSize(width:  0.088, height: -0.026)

    private let barWidth: CGFloat   = 0.047
    private let barRadius: CGFloat  = 0.024
    private let barGap: CGFloat     = 0.031
    private let barHeights: [CGFloat] = [0.153, 0.27, 0.20, 0.317]

    // MARK: Body
    var body: some View {
        ZStack {
            backdrop
            glassCard(style: .back)
                .rotationEffect(.degrees(backAngle))
                .offset(x: backOffset.width * size, y: backOffset.height * size)
            glassCard(style: .mid)
                .rotationEffect(.degrees(midAngle))
                .offset(x: midOffset.width * size, y: midOffset.height * size)
            leadingCard
                .rotationEffect(.degrees(frontAngle))
                .offset(x: frontOffset.width * size, y: frontOffset.height * size)
                .shadow(color: dropColor, radius: size * 0.032,
                        x: -size * 0.028, y: size * 0.014)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: masked ? size * 0.2237 : 0, style: .continuous))
        .shadow(color: masked ? .black.opacity(0.5) : .clear,
                radius: size * 0.07, x: 0, y: size * 0.03)
    }

    // MARK: Backdrop
    private var backdrop: some View {
        RadialGradient(gradient: Gradient(stops: backdropStops),
                       center: UnitPoint(x: 0.40, y: 0.24),
                       startRadius: 0, endRadius: size * 0.82)
    }

    private var backdropStops: [Gradient.Stop] {
        switch appearance {
        case .dark:
            return [.init(color: h("#24242E"), location: 0.00),
                    .init(color: h("#14141A"), location: 0.46),
                    .init(color: h("#0B0B0D"), location: 0.78),
                    .init(color: h("#06060A"), location: 1.00)]
        case .light:
            return [.init(color: h("#F4FFD1"), location: 0.00),
                    .init(color: h("#E9FFAE"), location: 0.42),
                    .init(color: h("#DBF988"), location: 0.76),
                    .init(color: h("#CBEE63"), location: 1.00)]
        case .tinted(let t):
            let (hi, mid, lo) = t.ramp
            return [.init(color: hi,  location: 0.00),
                    .init(color: mid, location: 0.52),
                    .init(color: lo,  location: 1.00)]
        }
    }

    // MARK: Trailing (stacked) glass cards
    private enum CardStyle { case back, mid }

    private func glassCard(style: CardStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: cardRadius * size, style: .continuous)
        return shape
            .fill(LinearGradient(gradient: Gradient(stops: cardStops(style)),
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(                                    // specular top-left edge
                shape.trim(from: 0.50, to: 1.0)
                    .stroke(specularEdge(style), lineWidth: hairline * size)
                    .blur(radius: size * 0.002)
            )
            .overlay(                                    // shadow bottom-right edge
                shape.trim(from: 0.0, to: 0.50)
                    .stroke(shadowEdge, lineWidth: hairline * size)
            )
            .overlay(shape.strokeBorder(rimColor(style), lineWidth: hairline * size))
            .frame(width: cardSide * size, height: cardSide * size)
            .shadow(color: appearance == .light ? h("#505064").opacity(0.16) : .black.opacity(0.35),
                    radius: size * 0.02, x: -size * 0.012, y: size * 0.006)
    }

    private func cardStops(_ style: CardStyle) -> [Gradient.Stop] {
        let isBack = style == .back
        switch appearance {
        case .dark:
            let a: Double = isBack ? 0.10 : 0.16
            let b: Double = isBack ? 0.03 : 0.05
            let c: Double = isBack ? 0.055 : 0.09
            return [.init(color: .white.opacity(a), location: 0.0),
                    .init(color: .white.opacity(b), location: isBack ? 0.60 : 0.58),
                    .init(color: .white.opacity(c), location: 1.0)]
        case .light:
            let a: Double = isBack ? 0.90 : 0.96
            let b: Double = isBack ? 0.42 : 0.52
            let c: Double = isBack ? 0.60 : 0.68
            return [.init(color: .white.opacity(a), location: 0.0),
                    .init(color: .white.opacity(b), location: isBack ? 0.62 : 0.58),
                    .init(color: .white.opacity(c), location: 1.0)]
        case .tinted:
            let a: Double = isBack ? 0.14 : 0.24
            let b: Double = isBack ? 0.04 : 0.08
            let c: Double = isBack ? 0.07 : 0.13
            return [.init(color: .white.opacity(a), location: 0.0),
                    .init(color: .white.opacity(b), location: isBack ? 0.60 : 0.58),
                    .init(color: .white.opacity(c), location: 1.0)]
        }
    }

    private func specularEdge(_ style: CardStyle) -> Color {
        switch appearance {
        case .dark:   return .white.opacity(style == .back ? 0.16 : 0.22)
        case .light:  return .white.opacity(style == .back ? 0.95 : 1.00)
        case .tinted: return .white.opacity(style == .back ? 0.20 : 0.30)
        }
    }

    private var shadowEdge: Color {
        switch appearance {
        case .dark:   return .black.opacity(0.38)
        case .light:  return h("#78788C").opacity(0.18)
        case .tinted: return .black.opacity(0.32)
        }
    }

    private func rimColor(_ style: CardStyle) -> Color {
        switch appearance {
        case .dark:   return .white.opacity(style == .back ? 0.07 : 0.10)
        case .light:  return .white.opacity(style == .back ? 0.70 : 0.80)
        case .tinted: return .white.opacity(style == .back ? 0.09 : 0.13)
        }
    }

    // MARK: Leading card + waveform
    private var leadingCard: some View {
        let shape = RoundedRectangle(cornerRadius: cardRadius * size, style: .continuous)
        return shape
            .fill(LinearGradient(gradient: Gradient(stops: frontStops),
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: cardSide * size, height: cardSide * size)
            .overlay(waveform)
            .overlay(sheen)                              // sits above the bars
            .overlay(shape.strokeBorder(.white.opacity(frontRim), lineWidth: hairline * size))
            .clipShape(shape)
    }

    private var frontStops: [Gradient.Stop] {
        switch appearance {
        case .dark:
            return [.init(color: h("#EAFF95"), location: 0.00),
                    .init(color: h("#D9FF52"), location: 0.34),
                    .init(color: h("#C4F02E"), location: 0.68),
                    .init(color: h("#A6D024"), location: 1.00)]
        case .light:
            return [.init(color: h("#F2FFB4"), location: 0.00),
                    .init(color: h("#DEFF6B"), location: 0.32),
                    .init(color: h("#CDF93C"), location: 0.66),
                    .init(color: h("#B4E024"), location: 1.00)]
        case .tinted:
            return [.init(color: .white.opacity(0.97), location: 0.00),
                    .init(color: .white.opacity(0.80), location: 0.40),
                    .init(color: .white.opacity(0.66), location: 1.00)]
        }
    }

    private var frontRim: Double {
        switch appearance {
        case .dark: return 0.30
        case .light: return 0.55
        case .tinted: return 0.40
        }
    }

    private var waveform: some View {
        HStack(spacing: barGap * size) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, hFrac in
                RoundedRectangle(cornerRadius: barRadius * size, style: .continuous)
                    .fill(barColor)
                    .frame(width: barWidth * size, height: hFrac * size)
                    .overlay(                            // light catch on the lower lip
                        RoundedRectangle(cornerRadius: barRadius * size, style: .continuous)
                            .trim(from: 0.0, to: 0.5)
                            .stroke(.white.opacity(appearance == .light ? 0.55 : 0.28),
                                    lineWidth: size * 0.006)
                    )
                    .shadow(color: .black.opacity(0.45), radius: size * 0.006, y: size * 0.004)
            }
        }
    }

    private var barColor: Color {
        switch appearance {
        case .dark:  return h("#090E02").opacity(0.82)
        case .light: return h("#101604").opacity(0.86)
        case .tinted(let t): return t.ramp.2
        }
    }

    private var sheen: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .white.opacity(sheenPeak),         location: 0.00),
                .init(color: .white.opacity(sheenPeak * 0.20),  location: 0.32),
                .init(color: .white.opacity(0),                 location: 0.48)
            ]),
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .allowsHitTesting(false)
    }

    private var sheenPeak: Double {
        switch appearance {
        case .dark: return 0.62
        case .light: return 0.75
        case .tinted: return 0.55
        }
    }

    private var dropColor: Color {
        appearance == .light ? h("#505064").opacity(0.28) : .black.opacity(0.50)
    }
}

// MARK: - Hex helper
private func h(_ hex: String) -> Color {
    var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
    let v = UInt32(s, radix: 16) ?? 0
    return Color(
        red:   Double((v & 0xFF0000) >> 16) / 255,
        green: Double((v & 0x00FF00) >> 8)  / 255,
        blue:  Double( v & 0x0000FF)        / 255
    )
}

// MARK: - Previews
#Preview("Three appearances") {
    HStack(spacing: 24) {
        SwipelistAppIcon(size: 180, appearance: .dark)
        SwipelistAppIcon(size: 180, appearance: .light)
        SwipelistAppIcon(size: 180, appearance: .tinted(.lime))
    }
    .padding(40)
    .background(h("#0E0E10"))
}

#Preview("Size ladder — dark") {
    HStack(alignment: .bottom, spacing: 20) {
        ForEach([180, 120, 80, 58, 40], id: \.self) { s in
            SwipelistAppIcon(size: CGFloat(s), appearance: .dark)
        }
    }
    .padding(40)
    .background(h("#0E0E10"))
}

#Preview("Tint ramp") {
    HStack(spacing: 20) {
        SwipelistAppIcon(size: 120, appearance: .tinted(.lime))
        SwipelistAppIcon(size: 120, appearance: .tinted(.indigo))
        SwipelistAppIcon(size: 120, appearance: .tinted(.violet))
        SwipelistAppIcon(size: 120, appearance: .tinted(.slate))
    }
    .padding(40)
    .background(h("#0E0E10"))
}
