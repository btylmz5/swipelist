import SwiftUI
import UIKit

// Swipelist design system — values from uploads/DESIGN.md. Dark only.

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

extension Color {
    static let swBackground = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0D / 255)
    static let swSurfaceCard = Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255)
    static let swSurfaceSheet = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1F / 255)
    static let swSurfaceControl = Color.white.opacity(0.08)
    static let swTextPrimary = Color.white
    static let swTextSecondary = Color.white.opacity(0.70)
    static let swTextTertiary = Color.white.opacity(0.45)
    static let swAccent = Color(red: 0xD4 / 255, green: 0xFF / 255, blue: 0x3F / 255)
    static let swOnAccent = swBackground
    static let swSkip = Color(red: 0x6E / 255, green: 0x6E / 255, blue: 0x73 / 255)
    static let swSeparator = Color.white.opacity(0.08)
    static let swDestructive = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
}

extension Font {
    static let swDisplay = Font.system(size: 32, weight: .bold)
    static let swTitle = Font.system(size: 26, weight: .bold)
    static let swHeadline = Font.system(size: 20, weight: .semibold)
    static let swBody = Font.system(size: 16, weight: .regular)
    static let swCaption = Font.system(size: 14, weight: .regular)
    static let swLabel = Font.system(size: 12, weight: .semibold)
}
