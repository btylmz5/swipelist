import SwiftUI

struct SwipeDeckView: View {
    @Binding var added: [Track]
    /// The deck's songs — built by DeckBuilder from the user's brief, or
    /// Track.deckSamples for previews and debug shortcuts. May grow while the
    /// deck is on screen as later batches resolve.
    let tracks: [Track]
    var startWithCheckpoint = false
    var onFinish: () -> Void = {}
    var onClose: () -> Void = {}
    /// Reports each committed swipe so the builder can adapt later suggestions.
    /// The third value is how far through the preview the listener got (0...1) —
    /// an instant skip and a last-second one are different taste signals.
    var onSwipe: (Track, Bool, Double) -> Void = { _, _, _ in }
    /// Reports how many unswiped cards are left, so the builder can refill in time.
    var reasons: [UUID: String] = [:]
    var onFeedback: (Track, String) -> Void = { _, _ in }
    @State private var explanation: String?
    var onRemainingChanged: (Int) -> Void = { _ in }

    private enum Phase { case idle, exit, undoIn }

    private let threshold: CGFloat = 120
    private let maxRotation: Double = 10
    private let checkpointCount = 20

    private var pool: [Track] { tracks }

    @StateObject private var preview = PreviewPlayer()
    @State private var idx = 0
    @State private var history: [Int] = []
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var dragging = false
    @State private var phase: Phase = .idle
    @State private var exitDir: CGFloat = 0
    @State private var crossed = false
    @State private var playing = true
    @State private var progress: Double = 0
    @State private var showCheckpoint = false
    @State private var checkpointShown = false

    private let previewTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    /// True once every resolved card has been swiped and the refill hasn't landed.
    private var isExhausted: Bool { idx >= pool.count }
    private var front: Track { pool[min(idx, pool.count - 1)] }
    private var next: Track { pool[min(idx + 1, pool.count - 1)] }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.swBackground.ignoresSafeArea()
                if !pool.isEmpty {
                    backdrop
                    dimOverlay
                }

                VStack(spacing: 0) {
                    topBar
                    Group {
                        if pool.isEmpty {
                            EmptyView()
                        } else if isExhausted {
                            waitingForMore
                        } else {
                            cardStack(in: geo)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    if !pool.isEmpty, !isExhausted {
                        controls(in: geo)
                    }
                }
            }
        }
        .onAppear {
            startPreview()
            onRemainingChanged(max(0, pool.count - idx - 1))
        }
        .onDisappear { preview.stop() }
        .onReceive(preview.$progress) { p in
            guard !pool.isEmpty, !isExhausted, front.previewURL != nil else { return }
            progress = p
            if p >= 1 { playing = false }
        }
        .onReceive(previewTimer) { _ in
            // Fake preview clock for mock tracks without real audio.
            guard !pool.isEmpty, !isExhausted, front.previewURL == nil else { return }
            guard playing, phase == .idle, !dragging else { return }
            progress = min(1, progress + 0.1 / 30)
            if progress >= 1 { playing = false }
        }
        .onAppear {
            if startWithCheckpoint {
                checkpointShown = true
                // Wait for the fullScreenCover transition before presenting the sheet.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showCheckpoint = true
                }
            }
        }
        .alert("Why this song?", isPresented: Binding(get: { explanation != nil }, set: { if !$0 { explanation = nil } })) {
            Button("OK") { explanation = nil }
        } message: { Text(explanation ?? "") }
        .sheet(isPresented: $showCheckpoint) {
            CheckpointSheet(
                count: added.count,
                arts: Array(added.suffix(5)),
                onKeep: { showCheckpoint = false },
                onFinish: {
                    showCheckpoint = false
                    onFinish()
                }
            )
        }
    }

    // MARK: - Backdrop

    /// Blurred artwork of the current track, crossfading as the deck advances.
    private var backdrop: some View {
        ZStack {
            TrackArtView(track: front)
                .id(front.id)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.6), value: front.id)
        .scaleEffect(1.3)
        .blur(radius: 60)
        .saturation(0.4)
        .opacity(0.55)
        .ignoresSafeArea()
    }

    private var dimOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: Color.swBackground.opacity(0.2), location: 0),
                .init(color: Color.swBackground.opacity(0), location: 0.3),
                .init(color: Color.swBackground.opacity(0), location: 0.55),
                .init(color: Color.swBackground.opacity(0.85), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Playback

    /// Starts audio for the front card, if it has a real preview URL.
    private func startPreview() {
        progress = 0
        playing = true
        guard !pool.isEmpty, !isExhausted, let url = front.previewURL else { return }
        preview.play(url)
    }

    /// Shown when the listener has swiped everything resolved so far. The builder
    /// is already fetching more; this replaces the old behaviour of silently
    /// looping back to the first card.
    private var waitingForMore: some View {
        VStack(spacing: 14) {
            DeckMotif()
                .frame(width: 92, height: 92)
            Text("Finding more songs")
                .font(.swBody)
                .foregroundStyle(Color.swTextSecondary)
        }
        .onAppear { onRemainingChanged(0) }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("\(added.count) added")
                .font(.system(size: 14))
                .foregroundStyle(Color.swTextSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .background(.ultraThinMaterial, in: Capsule())
                .clipShape(Capsule())

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.swTextSecondary)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.08))
                    .background(.ultraThinMaterial, in: Circle())
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Cards

    private func cardStack(in geo: GeometryProxy) -> some View {
        let width = min(geo.size.width - 62, 400)
        let p = min(abs(dragX) / threshold, 1)
        let rotation = max(-maxRotation, min(maxRotation, (dragX / geo.size.width) * 14))
        let scale = dragX > 0 ? 1 + p * 0.03 : 1
        let opacity = phase == .exit ? 0 : (dragX < 0 ? 1 - p * 0.25 : 1)
        let addOp = phase == .exit ? (exitDir > 0 ? 1 : 0) : max(0, min(dragX / threshold, 1))
        let skipOp = phase == .exit ? (exitDir < 0 ? 1 : 0) : max(0, min(-dragX / threshold, 1))
        let exitX = exitDir * geo.size.width * 1.4

        return ZStack {
            // Next card, rising as the front card exits
            card(next, width: width, showsControls: false)
                .scaleEffect(phase == .exit ? 1 : 0.94)
                .offset(y: phase == .exit ? 0 : 18)
                .opacity(phase == .exit ? 1 : 0.7)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: phase == .exit)

            // Front card
            card(front, width: width, showsControls: true)
                .overlay(glow(color: .swAccent, shadow: Color.swAccent.opacity(0.7), trailing: true).opacity(addOp))
                .overlay(glow(color: Color(hex: 0x8E8E93), shadow: Color(hex: 0x8E8E93).opacity(0.55), trailing: false).opacity(skipOp))
                .overlay(alignment: .topTrailing) { swipeLabel("ADDED", color: .swAccent, opacity: addOp) }
                .overlay(alignment: .topLeading) { swipeLabel("SKIPPED", color: Color(hex: 0xC7C7CC), opacity: skipOp) }
                .rotationEffect(.degrees(phase == .exit ? exitDir * 11 : rotation))
                .scaleEffect(scale)
                .opacity(opacity)
                .offset(x: phase == .exit ? exitX : dragX, y: dragY)
                .gesture(dragGesture(in: geo))
        }
    }

    private func card(_ track: Track, width: CGFloat, showsControls: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TrackArtView(track: track)
                .frame(width: width, height: width)
                .clipShape(UnevenRoundedRectangle(cornerRadii: .init(
                    topLeading: 20, bottomLeading: 12, bottomTrailing: 12, topTrailing: 20
                )))
                .overlay(alignment: .bottomTrailing) {
                    if showsControls { playButton }
                }
                .accessibilityLabel("Artwork for \(track.title) by \(track.artist)")

            VStack(alignment: .leading, spacing: 0) {
                Text(track.title)
                    .font(.swTitle)
                    .tracking(-0.3)
                    .foregroundStyle(Color.swTextPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.swBody)
                    .foregroundStyle(Color.swTextSecondary)
                    .lineLimit(1)
                    .padding(.top, 4)
                if showsControls, let reason = reasons[track.id] {
                    HStack {
                        Button("Why this song?") { explanation = reason }
                        Spacer()
                        Menu("Feedback") {
                            Button("Doesn't fit this brief") { onFeedback(track, "off_brief") }
                            Button("I don't like this song") { onFeedback(track, "dislike") }
                            Button("I know this song") { onFeedback(track, "known") }
                        }
                    }.font(.system(size: 12)).foregroundStyle(Color.swAccent).padding(.top, 8)
                }
                Text(track.meta.uppercased())
                    .font(.swLabel)
                    .tracking(0.8)
                    .foregroundStyle(Color.swTextTertiary)
                    .padding(.top, 12)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width)
        .background(Color.swSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 20)
    }

    private var playButton: some View {
        Button {
            playing.toggle()
            preview.setPaused(!playing)
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x28282C).opacity(0.55))
                    .background(.ultraThinMaterial, in: Circle())
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.swAccent, lineWidth: 2)
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .padding(1)
        }
        .buttonStyle(.plain)
        .padding(14)
    }

    private func glow(color: Color, shadow: Color, trailing: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(color, lineWidth: 3)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.52),
                        .init(color: .black, location: 0.76),
                    ],
                    startPoint: trailing ? .leading : .trailing,
                    endPoint: trailing ? .trailing : .leading
                )
            )
            .shadow(color: shadow, radius: 16)
            .allowsHitTesting(false)
    }

    private func swipeLabel(_ text: String, color: Color, opacity: Double) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .tracking(2.4)
            .foregroundStyle(color)
            .shadow(color: color, radius: 7)
            .scaleEffect(crossed && opacity > 0 ? 1.08 : 1)
            .animation(.easeOut(duration: 0.15), value: crossed)
            .opacity(opacity)
            .padding(22)
            .allowsHitTesting(false)
    }

    // MARK: - Controls

    private func controls(in geo: GeometryProxy) -> some View {
        HStack(spacing: 12) {
            Button {
                undo(width: geo.size.width)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.swTextSecondary)
                    .frame(width: 44, height: 44)
                    .background(Color.swSurfaceControl, in: Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Button {
                    buttonCommit(-1, width: geo.size.width)
                } label: {
                    Text("SKIP")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Color(hex: 0x8E8E93))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 12)

                Button {
                    buttonCommit(1, width: geo.size.width)
                } label: {
                    Text("ADD")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(Color.swAccent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 56)
            .background(Color.white.opacity(0.06))
            .background(.ultraThinMaterial, in: Capsule())
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Gesture & motion

    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard phase == .idle else { return }
                dragging = true
                dragX = value.translation.width
                dragY = value.translation.height * 0.12
                let nowCrossed = abs(dragX) >= threshold
                if nowCrossed != crossed {
                    if nowCrossed { Haptics.light() }
                    crossed = nowCrossed
                }
            }
            .onEnded { value in
                guard phase == .idle, dragging else { return }
                dragging = false
                let velocity = value.velocity.width
                let commitByDistance = abs(dragX) >= threshold
                let commitByVelocity = abs(velocity) >= 800 && abs(dragX) > 40 && (velocity > 0) == (dragX > 0)
                if commitByDistance || commitByVelocity {
                    commit(dragX > 0 ? 1 : -1)
                } else {
                    crossed = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        dragX = 0
                        dragY = 0
                    }
                }
            }
    }

    private func buttonCommit(_ dir: CGFloat, width: CGFloat) {
        guard phase == .idle, !dragging else { return }
        commit(dir)
    }

    private func commit(_ dir: CGFloat) {
        Haptics.medium()
        crossed = false
        playing = false
        // Captured before stop(), which zeroes the player's published progress.
        let listened = progress
        preview.stop()
        if dir > 0 { added.append(front) }
        onSwipe(front, dir > 0, listened)
        history.append(dir > 0 ? 1 : -1)
        exitDir = dir
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            phase = .exit
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            advance()
        }
    }

    private func advance() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            idx += 1
            dragX = 0
            dragY = 0
            phase = .idle
            exitDir = 0
        }
        startPreview()
        onRemainingChanged(max(0, pool.count - idx - 1))
        if added.count >= checkpointCount && !checkpointShown {
            checkpointShown = true
            showCheckpoint = true
        }
    }

    private func undo(width: CGFloat) {
        guard phase == .idle, !dragging, let last = history.last else { return }
        history.removeLast()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if last > 0, !added.isEmpty { added.removeLast() }
            idx = max(0, idx - 1)
            phase = .undoIn
            dragX = CGFloat(last) * width * 1.4
            dragY = 0
        }
        startPreview()
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                dragX = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if phase == .undoIn { phase = .idle }
            }
        }
    }
}
