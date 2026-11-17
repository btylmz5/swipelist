import SwiftUI

struct PreferenceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PreferenceStore.shared
    @State private var artists = ""
    @State private var examples = ""
    @State private var likes = ""
    @State private var avoids = ""
    @State private var saving = false
    var onboarding = false
    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.uniqued { $0.folded }
    }
    private var valid: Bool {
        lines(artists).count <= 5 && lines(examples).count <= 5 && lines(likes).count <= 10 && lines(avoids).count <= 10 &&
        [artists,examples,likes,avoids].flatMap(lines).allSatisfy { $0.count <= 200 }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tell us about 3–5 artists or songs you like. These are preferences you provide, not an analysis of your Spotify history. They guide both candidate discovery and a separate musical comparison. Your taste requires a supported connection; the playlist brief still comes first.")
                }
                Section("Favorite artists · one per line · up to 5") { TextField("Artist names", text: $artists, axis: .vertical).lineLimit(3...6) }
                Section("Songs you know · Artist — Song · up to 5") { TextField("Example songs", text: $examples, axis: .vertical).lineLimit(3...6) }
                Section("Musical qualities you enjoy · one per line") { TextField("Airy vocals, warm bass…", text: $likes, axis: .vertical) }
                Section("Qualities you usually avoid · one per line") { TextField("Harsh vocals…", text: $avoids, axis: .vertical) }
                if let error = store.error { Section { Text(error).foregroundStyle(.red) } }
                if !valid { Text("Use at most 5 artists, 5 songs, and 10 qualities per field; 200 characters per line.").foregroundStyle(.red) }
                Section {
                    Button(saving ? "Saving…" : "Save preferences") { save(skip: false) }.disabled(saving || !valid)
                    if onboarding { Button("Skip for now") { save(skip: true) }.disabled(saving) }
                }
            }
            .navigationTitle("Your music taste")
            .toolbar { if !onboarding { Button("Cancel") { dismiss() } } }
            .onAppear {
                let p = store.profile
                artists=p.artists.joined(separator:"\n"); examples=p.examples.joined(separator:"\n")
                likes=p.likes.joined(separator:"\n"); avoids=p.avoids.joined(separator:"\n")
            }
        }
        .interactiveDismissDisabled(onboarding || saving)
    }
    private func save(skip: Bool) {
        saving = true
        let profile = PreferenceProfile(artists: skip ? [] : lines(artists), examples: skip ? [] : lines(examples), likes: skip ? [] : lines(likes), avoids: skip ? [] : lines(avoids), completed: true)
        Task { if await store.save(profile) { dismiss() }; saving = false }
    }
}
