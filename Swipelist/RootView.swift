import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    /// The tab bar steps aside while a keyboard is up — stacked above one it
    /// costs a screen's worth of room the field being typed into needs.
    @State private var keyboardUp = false

    var body: some View {
        Group {
            switch app.tab {
            case .create: CreateTabView()
            case .library: LibraryView()
            case .profile: ProfileView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // An inset rather than a VStack row, so content scrolls under the glass.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardUp {
                GlassTabBar(selection: $app.tab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.swBackground.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardUp = false }
        }
    }
}

/// Floating Liquid Glass tab bar. Uses the iOS 26 glass APIs where available and
/// falls back to a material capsule on older systems.
///
/// The selection pill is finger-driven the way the system bar is: grab it and
/// slide, and it tracks the touch continuously instead of hopping tab to tab.
/// Pushed past either end it squeezes flat against the edge with rubber-band
/// resistance, then springs back to the slot on release.
struct GlassTabBar: View {
    @Binding var selection: AppState.Tab

    /// Live touch position in bar-content space; nil whenever the pill is resting.
    @State private var dragX: CGFloat?
    /// True once a touch has been promoted from a plain tap into a pill drag.
    @State private var tracking = false
    /// Resets itself if the gesture is cancelled rather than ended, so a pill
    /// can never be stranded mid-drag.
    @GestureState private var touching = false

    private struct Item: Identifiable {
        let tab: AppState.Tab
        let icon: String
        let label: String
        var id: AppState.Tab { tab }
    }

    private let items: [Item] = [
        Item(tab: .create, icon: "rectangle.stack", label: "Create"),
        Item(tab: .library, icon: "square.grid.2x2", label: "Library"),
        Item(tab: .profile, icon: "person", label: "Profile")
    ]

    /// Height of the bar's content; the pill fills it.
    private let barHeight: CGFloat = 48
    private let iconSize: CGFloat = 18
    /// Roomy enough for an 18pt symbol at its largest (semibold, popped).
    private let iconBox: CGFloat = 24
    /// A touch that starts off the pill only takes it over once it has moved.
    private let grabThreshold: CGFloat = 8

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // The container lets the selection pill blend with the bar as it moves.
                GlassEffectContainer(spacing: 18) { bar }
            } else {
                bar
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var bar: some View {
        GeometryReader { geo in
            let slot = geo.size.width / CGFloat(items.count)
            ZStack {
                pill(slot: slot, barWidth: geo.size.width, height: geo.size.height)
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        label(item).frame(width: slot)
                    }
                }
            }
            // The whole bar is one gesture surface, so a slide can cross tabs.
            .contentShape(Rectangle())
            .gesture(dragGesture(slot: slot))
        }
        .frame(height: barHeight)
        .padding(6)
        .modifier(GlassCapsule(tint: nil, interactive: false))
        // The bar gives a little under the finger, the way glass controls do.
        .scaleEffect(touching ? 0.985 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: touching)
        // A cancelled gesture never reaches onEnded; this always brings it home.
        .onChange(of: touching) { _, isTouching in
            if !isTouching { release() }
        }
    }

    private func label(_ item: Item) -> some View {
        let active = selection == item.tab
        return VStack(spacing: 3) {
            Image(systemName: item.icon)
                .font(.system(size: iconSize, weight: active ? .semibold : .regular))
                // Sized for the tallest glyph in the set (rectangle.stack) so no
                // symbol overflows its box and crowds the pill's edge.
                .frame(height: iconBox)
                // The glyph pops as the pill arrives under it — kept small
                // enough to stay inside the box above.
                .scaleEffect(active ? 1.05 : 1)
            Text(item.label)
                .font(.system(size: 11, weight: active ? .semibold : .medium))
        }
        // These labels have no descenders, so the text box's reserved descender
        // space would otherwise park the whole stack above the pill's centre.
        .offset(y: 1.5)
        .foregroundStyle(active ? Color.swAccent : Color.white.opacity(0.55))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(item.tab) }
    }

    private func pill(slot: CGFloat, barWidth: CGFloat, height: CGFloat) -> some View {
        let shape = pillShape(slot: slot, barWidth: barWidth)
        return Group {
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .modifier(GlassCapsule(tint: Color.swAccent.opacity(0.14), interactive: true))
            } else {
                Capsule()
                    .fill(Color.swAccent.opacity(0.16))
                    .overlay(Capsule().strokeBorder(Color.swAccent.opacity(0.35), lineWidth: 0.5))
            }
        }
        .frame(width: shape.width, height: height)
        .modifier(LiquidMotion(x: shape.centerX, restWidth: shape.width, centerY: height / 2))
    }

    // MARK: - Pill geometry

    private struct PillShape {
        var centerX: CGFloat
        var width: CGFloat
    }

    /// Resting the pill sits centred in its slot; dragging, it rides the finger;
    /// past the ends it stops at the edge and compresses by the overshoot.
    private func pillShape(slot: CGFloat, barWidth: CGFloat) -> PillShape {
        let resting = slot * (CGFloat(selectedIndex) + 0.5)
        guard let dragX else { return PillShape(centerX: resting, width: slot) }

        let half = slot / 2
        if dragX < half {
            let squeeze = rubberBand(half - dragX, limit: slot) * 0.5
            return PillShape(centerX: (slot - squeeze) / 2, width: slot - squeeze)
        }
        if dragX > barWidth - half {
            let squeeze = rubberBand(dragX - (barWidth - half), limit: slot) * 0.5
            return PillShape(centerX: barWidth - (slot - squeeze) / 2, width: slot - squeeze)
        }
        return PillShape(centerX: dragX, width: slot)
    }

    /// Asymptotic falloff: overshoot resists more the further it is pushed and
    /// never exceeds `limit`.
    private func rubberBand(_ distance: CGFloat, limit: CGFloat) -> CGFloat {
        let d = max(0, distance)
        return limit * (1 - 1 / (d / (limit * 0.6) + 1))
    }

    // MARK: - Gesture

    private func dragGesture(slot: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
                if tracking {
                    // Chasing rather than pinning the finger is what gives the
                    // pill its lag, and the lag is what stretches it.
                    withAnimation(.interactiveSpring(response: 0.17, dampingFraction: 0.8)) {
                        dragX = value.location.x
                    }
                } else {
                    // A touch that lands on the pill takes it over at once; one
                    // that lands elsewhere is still a tap until the finger moves.
                    let onPill = index(at: value.startLocation.x, slot: slot) == selectedIndex
                    guard onPill || abs(value.translation.width) > grabThreshold else { return }
                    tracking = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragX = value.location.x
                    }
                }
                select(items[index(at: value.location.x, slot: slot)].tab)
            }
            .onEnded { value in
                if !tracking {
                    select(items[index(at: value.location.x, slot: slot)].tab)
                }
                release()
            }
    }

    /// Hands the pill back to its slot with an overshoot, so it arrives with a
    /// wobble instead of stopping dead.
    private func release() {
        tracking = false
        guard dragX != nil else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { dragX = nil }
    }

    private var selectedIndex: Int {
        items.firstIndex { $0.tab == selection } ?? 0
    }

    private func index(at x: CGFloat, slot: CGFloat) -> Int {
        min(items.count - 1, max(0, Int(x / slot)))
    }

    private func select(_ tab: AppState.Tab) {
        guard tab != selection else { return }
        Haptics.light()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.62)) { selection = tab }
    }
}

/// Places the pill and deforms it by how far it is running behind.
///
/// `animatedX` is interpolated by SwiftUI over the life of the animation while
/// `targetX` jumps to the final value immediately, so the gap between them is
/// the pill's instantaneous speed — no velocity tracking needed. Fast travel
/// stretches the capsule along its path and thins it out, the way a drop of
/// liquid draws out when it is flung; the stretch relaxes to nothing as the
/// pill catches up.
private struct LiquidMotion: ViewModifier, Animatable {
    private var animatedX: CGFloat
    private let targetX: CGFloat
    private let restWidth: CGFloat
    private let centerY: CGFloat

    /// Cap so a long throw across the bar does not smear the pill.
    private let maxStretch: CGFloat = 34

    init(x: CGFloat, restWidth: CGFloat, centerY: CGFloat) {
        self.animatedX = x
        self.targetX = x
        self.restWidth = restWidth
        self.centerY = centerY
    }

    var animatableData: CGFloat {
        get { animatedX }
        set { animatedX = newValue }
    }

    func body(content: Content) -> some View {
        let stretch = min(abs(targetX - animatedX) * 0.8, maxStretch)
        let scaleX = (restWidth + stretch) / restWidth
        content
            // Losing height as it gains length keeps the volume looking constant.
            .scaleEffect(x: scaleX, y: 1 - (scaleX - 1) * 0.45, anchor: .center)
            .position(x: animatedX, y: centerY)
    }
}

/// Applies a capsule of Liquid Glass, or a material capsule before iOS 26.
private struct GlassCapsule: ViewModifier {
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: .capsule)
        } else {
            content
                // Material only — an opaque wash over it was what made this
                // read as a painted capsule rather than something see-through.
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(tint ?? .clear))
                }
                // Glass catches the light along its top edge and loses it
                // towards the bottom; a flat stroke reads as a drawn border.
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                )
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        return glass.interactive(interactive)
    }
}

/// The Create tab: the brief screen, launching the immersive deck flow.
struct CreateTabView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: SpotifyAuth
    @State private var session: DeckSession?

    var body: some View {
        PlaylistBriefView { brief in
            // Nothing can be resolved or previewed without a music service, so
            // send them to Profile rather than into a deck that can't build.
            guard auth.isAuthenticated else {
                app.needsMusicConnection = true
                app.tab = .profile
                return
            }
            session = DeckSession(brief: brief)
        }
        .fullScreenCover(item: $session) { session in
            DeckFlowView(session: session)
        }
        .onAppear(perform: applyDebugScreen)
    }

    private func applyDebugScreen() {
        #if DEBUG
        if let debugBrief = app.debugBrief {
            app.debugBrief = nil
            session = DeckSession(brief: debugBrief)
            return
        }
        guard let screen = app.debugScreen else { return }
        app.debugScreen = nil
        let brief = PlaylistBrief(
            text: "melancholic indie for a rainy commute",
            energy: "Chill",
            occasion: "Commute"
        )
        let pool = Track.deckSamples
        switch screen {
        case "deck":
            session = DeckSession(brief: brief, useMockTracks: true)
        case "deck-live":
            session = DeckSession(brief: brief)
        case "checkpoint":
            let added = (0..<20).map { pool[$0 % pool.count] }
            session = DeckSession(brief: brief, initialAdded: added, showCheckpointOnAppear: true, useMockTracks: true)
        case "review":
            let added = (0..<24).map { pool[$0 % pool.count] }
            session = DeckSession(brief: brief, initialAdded: added, startAtReview: true, useMockTracks: true)
        default:
            break
        }
        #endif
    }
}

/// Immersive deck flow presented over the tab bar: building → deck → review.
struct DeckFlowView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: SpotifyAuth
    @Environment(\.dismiss) private var dismiss

    let session: DeckSession
    @StateObject private var builder = DeckBuilder()
    @State private var added: [Track]
    @State private var showReview: Bool

    init(session: DeckSession) {
        self.session = session
        _added = State(initialValue: session.initialAdded)
        _showReview = State(initialValue: session.startAtReview)
    }

    /// Debug shortcuts and previews bypass the builder entirely.
    private var mockTracks: [Track]? {
        session.useMockTracks ? Track.deckSamples : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let mockTracks {
                    deck(tracks: mockTracks)
                } else {
                    switch builder.phase {
                    case .loading:
                        DeckBuildingView(status: builder.status)
                    case .ready:
                        deck(tracks: builder.tracks)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                if let note = builder.personalizationNote {
                                    Text(note)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.swTextSecondary)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 6)
                                        .background(Color.swBackground)
                                }
                            }
                    case .historyUnavailable(let message):
                        ListeningHistoryUnavailableView(
                            message: message,
                            onRetry: startBuild,
                            onProfile: { dismiss(); app.tab = .profile },
                            onContinue: {
                                builder.build(text: session.brief.text,
                                              refinements: session.brief.refinements,
                                              mode: session.brief.recommendationMode,
                                              useListeningHistory: false)
                            }
                        )
                    case .failed(let failure):
                        DeckFailureView(
                            failure: failure,
                            onRetry: startBuild,
                            onEditBrief: { dismiss() },
                            smallDeckCount: builder.tracks.count,
                            onSmallDeck: { builder.continueWithSmallDeck() }
                        )
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showReview) {
                ReviewView(
                    name: Format.suggestedName(for: session.brief),
                    tracks: added,
                    onSaveDraft: { name in
                        app.save(name: name, brief: session.brief, tracks: added)
                        Haptics.success()
                        dismiss()
                        app.tab = .library
                    },
                    onExport: { name in
                        // Awaited, so a failure surfaces on the Review screen
                        // instead of leaving a playlist that only looks saved.
                        let externalID = try await exportToProvider(name: name, tracks: added)
                        app.save(
                            name: name,
                            brief: session.brief,
                            tracks: added,
                            exportedProvider: MusicProviders.shared.active,
                            externalID: externalID
                        )
                        Haptics.success()
                        dismiss()
                        app.tab = .library
                    }
                )
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .task {
            guard mockTracks == nil, builder.tracks.isEmpty else { return }
            startBuild()
        }
        .onDisappear { builder.cancel() }
    }

    /// Creates the playlist on Spotify and adds every track that came from there.
    /// Returns the external playlist id, so the library can link back to it.
    @discardableResult
    private func exportToProvider(name: String, tracks: [Track]) async throws -> String {
        let provider = MusicProviders.shared.current
        guard await provider.isConnected else {
            throw ExportError.notConnected(provider.displayName)
        }
        guard tracks.contains(where: { $0.spotifyURI != nil }) else {
            throw ExportError.nothingToExport
        }
        let id = try await provider.export(
            name: name,
            description: "Created by Swipelist · \(session.brief.text)",
            tracks: tracks
        )
        NSLog("SWEXPORT created playlist %@ with %d tracks", id, tracks.count)
        return id
    }

    enum ExportError: LocalizedError {
        case notConnected(String)
        case nothingToExport

        var errorDescription: String? {
            switch self {
            case .notConnected(let name):
                return "\(name) isn't connected. Open Profile to connect it, then try again."
            case .nothingToExport:
                return "None of these songs have an ID the service can save."
            }
        }
    }

    private func startBuild() {
        builder.build(
            text: session.brief.text,
            refinements: session.brief.refinements,
            mode: session.brief.recommendationMode, useListeningHistory: RecommendationFeatures.spotifyLocalExperiment, familiarShare: session.brief.familiarShare
        )
    }

    private func deck(tracks: [Track]) -> some View {
        SwipeDeckView(
            added: $added,
            tracks: tracks,
            startWithCheckpoint: session.showCheckpointOnAppear,
            onFinish: { showReview = true },
            onClose: {
                if added.isEmpty { dismiss() } else { showReview = true }
            },
            onSwipe: { track, wasAdded, listened in
                guard mockTracks == nil else { return }
                builder.record(track, liked: wasAdded, listenedFraction: listened)
            },
            reasons: builder.reasons,
            onFeedback: { track, verdict in builder.explicitFeedback(track, verdict: verdict) },
            onRemainingChanged: { remaining in
                guard mockTracks == nil else { return }
                builder.refillIfNeeded(remaining: remaining)
            }
        )
    }
}
