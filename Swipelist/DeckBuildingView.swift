import SwiftUI

/// Shown between "Start swiping" and the first card. No spinner — a stack of
/// cards that gathers and spreads, so the wait reads as assembly rather than delay.
struct DeckBuildingView: View {
    let status: String

    @State private var gathered = false

    private let cards: [(rotation: Double, offset: CGSize, tint: Color)] = [
        (-14, CGSize(width: -46, height: 10), Color(hex: 0x3FC9B8)),
        (-7, CGSize(width: -23, height: 3), Color(hex: 0x6F9FE8)),
        (0, CGSize(width: 0, height: 0), Color.swAccent),
        (7, CGSize(width: 23, height: 3), Color(hex: 0xB06FF0)),
        (14, CGSize(width: 46, height: 10), Color(hex: 0xD66FD0)),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            deck
            Text(status)
                .font(.swBody)
                .foregroundStyle(Color.swTextSecondary)
                .padding(.top, 56)
                .animation(.easeInOut(duration: 0.25), value: status)
                .contentTransition(.opacity)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.swBackground.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                gathered = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Building your deck. \(status).")
    }

    private var deck: some View {
        ZStack {
            ForEach(cards.indices, id: \.self) { i in
                let card = cards[i]
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.swSurfaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(card.tint.opacity(gathered ? 0.5 : 0.22), lineWidth: 1.5)
                    )
                    .frame(width: 92, height: 92)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
                    .rotationEffect(.degrees(gathered ? card.rotation * 0.25 : card.rotation))
                    .offset(
                        x: gathered ? card.offset.width * 0.2 : card.offset.width,
                        y: gathered ? card.offset.height * 0.2 : card.offset.height
                    )
                    .zIndex(Double(i))
            }
        }
        .frame(height: 150)
    }
}

/// Inline failure for the deck flow. Both cases keep the user's typed brief —
/// "Try again" reruns the chain, "Edit brief" returns to the still-populated form.
struct DeckFailureView: View {
    let failure: DeckBuilder.Failure
    var onRetry: () -> Void
    var onEditBrief: () -> Void
    var smallDeckCount: Int = 0
    var onSmallDeck: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            DeckMotif()
                .frame(width: 110, height: 110)

            Text(title)
                .font(.swHeadline)
                .foregroundStyle(Color.swTextPrimary)
                .padding(.top, 36)

            Text(message)
                .font(.swBody)
                .foregroundStyle(Color.swTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Spacer()

            if smallDeckCount > 0, let onSmallDeck {
                Button("Listen to these \(smallDeckCount) songs", action: onSmallDeck)
                    .font(.swHeadline)
                    .foregroundStyle(Color.swAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.bottom, 8)
            }
            Button(action: onRetry) {
                Text("Try again")
                    .font(.swHeadline)
                    .foregroundStyle(Color.swOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.swAccent, in: RoundedRectangle(cornerRadius: 14))
            }

            Button(action: onEditBrief) {
                Text("Edit brief")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.swTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.swBackground.ignoresSafeArea())
    }

    private var title: String {
        if smallDeckCount > 0 { return "A smaller selection is ready" }
        switch failure {
        case .suggestion: return "Couldn’t build your deck"
        case .network: return "No connection"
        case .notEnoughSongs: return "Not enough to swipe on"
        }
    }

    private var message: String {
        switch failure {
        case .suggestion(let message): return message
        case .network:
            return "We couldn't reach the music services.\nCheck your connection and try again."
        case .notEnoughSongs(let found):
            return found == 0
                ? "We couldn't find playable songs for that brief.\nTry describing it a different way."
                : "We only found \(found) playable \(found == 1 ? "song" : "songs") for that brief.\nTry describing it a different way."
        }
    }
}

#Preview("Building") {
    DeckBuildingView(status: "Finding artists")
        .preferredColorScheme(.dark)
}

#Preview("Not enough") {
    DeckFailureView(failure: .notEnoughSongs(found: 3), onRetry: {}, onEditBrief: {})
        .preferredColorScheme(.dark)
}

/// A failed history request never silently pretends to have personalized a deck.
struct ListeningHistoryUnavailableView: View {
    let message: String
    let onRetry: () -> Void
    let onProfile: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundStyle(Color.swAccent)
            Text("Listening history unavailable")
                .font(.swHeadline)
            Text(message)
                .font(.swBody)
                .foregroundStyle(Color.swTextSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Open Profile", action: onProfile)
                .font(.swHeadline)
                .foregroundStyle(Color.swOnAccent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.swAccent, in: RoundedRectangle(cornerRadius: 14))
            Button("Try again", action: onRetry)
                .foregroundStyle(Color.swTextPrimary)
                .frame(minHeight: 44)
            Button("Continue with brief only", action: onContinue)
                .foregroundStyle(Color.swTextSecondary)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .padding(24)
        .background(Color.swBackground.ignoresSafeArea())
    }
}
