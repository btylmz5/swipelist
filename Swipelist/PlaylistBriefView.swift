import SwiftUI

struct PlaylistBriefView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var spotify: SpotifyAuth
    @State private var recommendationMode: RecommendationMode = .balanced
    @ObservedObject private var preferences = PreferenceStore.shared
    @State private var showPreferences = false
    @State private var familiarShare = 0.25
    @State private var title = ""
    @State private var brief = ""
    @State private var picks: [BriefRefinement: String] = [:]
    @State private var showRefinements = false
    @FocusState private var field: Field?

    private enum Field { case title, brief }

    /// Called with the composed brief when the user taps "Start swiping".
    var onStart: (PlaylistBrief) -> Void = { _ in }

    private let editorID = "brief-editor"

    private var hasText: Bool {
        !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        form
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .safeAreaInset(edge: .bottom, spacing: 0) { startButton }
            .background(Color.swBackground.ignoresSafeArea())
            .onAppear {
                let draft = app.briefDraft
                title = draft.title
                brief = draft.text
                recommendationMode = draft.recommendationMode
                familiarShare = draft.familiarShare
                picks = Dictionary(uniqueKeysWithValues: BriefRefinement.allCases.compactMap { key in
                    draft.pick(key).map { (key, $0) }
                })
            }
            .onDisappear { app.briefDraft = composedBrief }
            .task {
                await preferences.load(userID: SupabaseAuth.shared.userID)
                showPreferences = RecommendationFeatures.v2 && !preferences.profile.completed && preferences.error == nil
            }
            .sheet(isPresented: $showPreferences) { PreferenceEditorView(onboarding: !preferences.profile.completed) }
    }

    /// The whole screen scrolls, so the keyboard can take half of it without
    /// squeezing the editor down to a two-line slot.
    private var form: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("What are we building?")
                        .font(.swDisplay)
                        .tracking(-0.4)
                        .foregroundStyle(Color.swTextPrimary)
                        .padding(.top, 16)

                    titleField
                        .padding(.top, 24)
                    editor
                        .padding(.top, 16)
                        .id(editorID)
                    recommendationPanel
                        .padding(.top, 20)
                    refinementPanel
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            // The caret sits at the end of the text, so keeping the editor's bottom
            // edge in view is what keeps the line being typed in view.
            .onChange(of: field) { _, newField in
                guard newField == .brief else { return }
                // The keyboard resizes the scroll view a beat after focus lands,
                // so the useful scroll is the second one.
                scrollToEditor(proxy, animation: .easeOut(duration: 0.25))
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    scrollToEditor(proxy, animation: .easeOut(duration: 0.2))
                }
            }
            .onChange(of: brief) { _, _ in
                guard field == .brief else { return }
                scrollToEditor(proxy, animation: .easeOut(duration: 0.12))
            }
        }
    }

    private func scrollToEditor(_ proxy: ScrollViewProxy, animation: Animation) {
        withAnimation(animation) { proxy.scrollTo(editorID, anchor: .bottom) }
    }

    /// Optional — left blank, the playlist is named from the brief on review.
    private var titleField: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("TITLE")

            TextField(
                "",
                text: $title,
                prompt: Text("Rainy Commute").foregroundStyle(Color.swTextTertiary)
            )
            .focused($field, equals: .title)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Color.swTextPrimary)
            .tint(Color.swAccent)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { field = .brief }
            .padding(.horizontal, 15)
            .frame(height: 52)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(fieldBorder(focused: field == .title))
            .animation(.easeOut(duration: 0.2), value: field)
        }
    }

    /// A vertical `TextField` rather than a `TextEditor`: it grows with the text
    /// instead of scrolling inside a fixed box, and it lets the enclosing
    /// ScrollView do the keyboard avoidance.
    private var editor: some View {
        TextField("", text: $brief, axis: .vertical)
            .focused($field, equals: .brief)
            .lineLimit(4...10)
            .font(.system(size: 17))
            .lineSpacing(2)
            .foregroundStyle(Color.swTextPrimary)
            .tint(Color.swAccent)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(fieldBorder(focused: field == .brief))
            .overlay(alignment: .topLeading) {
                if brief.isEmpty {
                    Text("melancholic indie for a rainy commute, something like Phoebe Bridgers but less sad…")
                        .font(.system(size: 17))
                        .lineSpacing(2)
                        .foregroundStyle(Color.swTextTertiary)
                        .padding(15)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.2), value: field)
    }

    // MARK: - Fine-tune

    /// Collapsed by default: the brief itself is the point, and five chip rows
    /// pushed the editor off screen. Collapsed it still reports what's picked.
    private var refinementPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                field = nil
                withAnimation(.easeInOut(duration: 0.25)) { showRefinements.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(picks.isEmpty ? Color.swTextTertiary : Color.swAccent)

                    Text("Fine-tune")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.swTextPrimary)

                    if !showRefinements, !pickSummary.isEmpty {
                        Text(pickSummary)
                            .font(.swCaption)
                            .foregroundStyle(Color.swTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.swTextTertiary)
                        .rotationEffect(.degrees(showRefinements ? 180 : 0))
                }
                .padding(.horizontal, 15)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showRefinements {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(BriefRefinement.allCases.filter { $0 != .discovery }) { refinement in
                        chipSection(refinement)
                    }

                    if !picks.isEmpty {
                        Button("Clear all") {
                            withAnimation(.easeOut(duration: 0.15)) { picks.removeAll() }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.swTextSecondary)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(fieldBorder(focused: false))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func chipSection(_ refinement: BriefRefinement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel(refinement.label.uppercased())

            FlowLayout(spacing: 8) {
                ForEach(refinement.options, id: \.self) { option in
                    chip(option, isSelected: picks[refinement] == option) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            if picks[refinement] == option {
                                picks[refinement] = nil
                            } else {
                                picks[refinement] = option
                            }
                        }
                    }
                }
            }
        }
    }

    private func chip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.swOnAccent : Color.swTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(isSelected ? Color.swAccent : .clear))
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.swAccent : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var pickSummary: String {
        BriefRefinement.allCases
            .compactMap { picks[$0] }
            .joined(separator: " · ")
    }

    // MARK: - Shared bits

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.swLabel)
            .tracking(0.8)
            .foregroundStyle(Color.swTextTertiary)
    }

    private func fieldBorder(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                focused ? Color.swAccent.opacity(0.5) : Color.white.opacity(0.08),
                lineWidth: 1
            )
    }

    /// A solid bar with a short fade above it. The button itself dims when the
    /// brief is empty, so anything scrolling behind has to be hidden by the bar
    /// rather than by the button.
    private var startButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.swBackground.opacity(0), Color.swBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)

            submitButton
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .background(Color.swBackground)
        }
    }

    private var recommendationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("PERSONALIZATION")
            HStack(spacing: 6) {
                ForEach(RecommendationMode.allCases) { mode in
                    Button {
                        recommendationMode = mode
                        if mode == .personal && !preferences.profile.hasPositiveReferences { showPreferences = true }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(recommendationMode == mode ? Color.swOnAccent : Color.swTextSecondary)
                            .background(recommendationMode == mode ? Color.swAccent : Color.swSurfaceCard,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!RecommendationFeatures.v2 || (preferences.profile.isEmpty && !(RecommendationFeatures.spotifyLocalExperiment && spotify.hasReadAccess)))
                    .accessibilityAddTraits(recommendationMode == mode ? .isSelected : [])
                    .accessibilityHint(mode.detail)
                }
            }
            Text(recommendationMode.detail)
                .font(.swCaption)
                .foregroundStyle(Color.swTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if RecommendationFeatures.v2 {
                Text("Familiar songs target: \(Int(familiarShare * 100))%")
                    .font(.swCaption)
                Slider(value: $familiarShare, in: 0...1, step: 0.05)
                    .accessibilityLabel("Familiar songs target")
                Text("Based on available listening history and songs you identify as known. Saved songs alone are not proof of listening.")
                    .font(.swCaption).foregroundStyle(Color.swTextSecondary)
                Button(preferences.profile.isEmpty ? "Set up your taste" : "Edit your taste") { showPreferences = true }
                    .foregroundStyle(Color.swAccent)
            }
            Text(RecommendationFeatures.spotifyLocalExperiment && spotify.hasReadAccess
                 ? "Spotify history and library matches rank checked songs on this device. Spotify data isn't sent to AI. This uses a limited snapshot."
                 : (preferences.profile.isEmpty || !RecommendationFeatures.v2
                 ? "Brief-only recommendations. Add favorite songs to discover music with a specific connection to your taste."
                 : "Uses your references to find candidates and check their musical connection to your taste."))
                .font(.system(size: 12))
                .foregroundStyle(Color.swTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var composedBrief: PlaylistBrief {
        PlaylistBrief(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                      text: brief, energy: picks[.energy], occasion: picks[.occasion],
                      mood: picks[.mood], era: picks[.era], discovery: picks[.discovery],
                      recommendationMode: recommendationMode, familiarShare: familiarShare)
    }

    private var submitButton: some View {
        Button {
            field = nil
            app.briefDraft = composedBrief
            onStart(composedBrief)
        } label: {
            Text("Start swiping")
                .font(.swHeadline)
                .foregroundStyle(Color.swOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.swAccent, in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!hasText)
        .opacity(hasText ? 1 : 0.3)
        .animation(.easeOut(duration: 0.2), value: hasText)
    }
}

// MARK: - Refinements

/// The axes the listener can pin down without writing them into the brief. Each
/// is optional and single-choice — they narrow the brief, they never replace it.
enum BriefRefinement: String, CaseIterable, Identifiable {
    case energy, mood, occasion, era, discovery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .energy: "Energy"
        case .mood: "Mood"
        case .occasion: "For"
        case .era: "Era"
        case .discovery: "Discovery"
        }
    }

    var options: [String] {
        switch self {
        case .energy: ["Chill", "Steady", "Upbeat", "Driving", "Intense"]
        case .mood: ["Happy", "Nostalgic", "Dreamy", "Melancholy", "Dark", "Romantic"]
        case .occasion: ["Workout", "Focus", "Commute", "Party", "Dinner", "Road trip", "Sleep"]
        case .era: ["Classics", "80s", "90s", "2000s", "2010s", "Recent"]
        case .discovery: ["Familiar hits", "Balanced", "Deep cuts"]
        }
    }

    /// How a pick reaches the suggestion model. The chip labels are shorthand —
    /// "90s" or "Deep cuts" on their own leave too much to the model's guess.
    func promptLine(for option: String) -> String {
        switch self {
        case .energy:
            return "Energy level: \(option.lowercased())"
        case .mood:
            return "Emotional tone: \(option.lowercased())"
        case .occasion:
            return "Listening context: \(option.lowercased())"
        case .era:
            switch option {
            case "Classics": return "Era: released before 1980"
            case "Recent": return "Era: released in the last two years"
            case "80s": return "Era: released in the 1980s"
            case "90s": return "Era: released in the 1990s"
            default: return "Era: released in the \(option)"
            }
        case .discovery:
            switch option {
            case "Familiar hits": return "Familiarity: well-known songs the listener is likely to recognise"
            case "Deep cuts": return "Familiarity: album cuts and under-the-radar artists rather than the obvious hits"
            default: return "Familiarity: a mix of recognisable songs and lesser-known finds"
            }
        }
    }
}

struct PlaylistBrief: Identifiable {
    let id = UUID()
    /// What the listener wants the playlist called. Empty means we suggest a
    /// name from the brief text instead.
    var title: String = ""
    var text: String
    var energy: String? = nil
    var occasion: String? = nil
    var mood: String? = nil
    var era: String? = nil
    var discovery: String? = nil
    var recommendationMode: RecommendationMode = .balanced
    var familiarShare: Double = 0.25

    func pick(_ refinement: BriefRefinement) -> String? {
        switch refinement {
        case .energy: energy
        case .mood: mood
        case .occasion: occasion
        case .era: era
        case .discovery: discovery
        }
    }

    /// The fine-tune picks as prompt lines, in a stable order. Empty when the
    /// listener left them alone, so a bare brief stays a bare brief.
    var refinements: [String] {
        BriefRefinement.allCases.compactMap { refinement in
            pick(refinement).map { refinement.promptLine(for: $0) }
        }
    }
}

// MARK: - Flow layout

/// Chips wrap onto as many lines as they need. Inside the fine-tune panel there
/// is room to show every option at once, and the horizontal scrollers this
/// replaces kept half of each row hidden behind a swipe.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private struct Item {
        let index: Int
        let x: CGFloat
        let size: CGSize
    }

    private struct Row {
        let y: CGFloat
        var height: CGFloat = 0
        var items: [Item] = []
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = rows(for: subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in rows(for: subviews, width: bounds.width) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(y: 0)
        var x: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.items.isEmpty, x + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
                x = 0
            }
            current.items.append(Item(index: index, x: x, size: size))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

#Preview {
    PlaylistBriefView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
