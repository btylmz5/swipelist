import SwiftUI

struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @State var name: String
    let tracks: [Track]
    /// Saves locally only — no service is touched.
    var onSaveDraft: (String) -> Void = { _ in }
    /// Writes the playlist to the connected music service. Throws so the failure
    /// can be shown here rather than swallowed.
    var onExport: (String) async throws -> Void = { _ in }

    @State private var editingName = false
    @State private var draftName = ""
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.swBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    songList
                }
                .padding(.bottom, 150)
            }

            footer
        }
        .alert("Playlist name", isPresented: $editingName) {
            TextField("Name", text: $draftName)
            Button("Done") {
                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { name = trimmed }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.swTextPrimary)
                    .frame(width: 40, height: 40)
            }
            .padding(.leading, -10)

            HStack(spacing: 10) {
                Text(name)
                    .font(.swDisplay)
                    .tracking(-0.4)
                    .foregroundStyle(Color.swTextPrimary)
                    .lineLimit(1)
                Button {
                    draftName = name
                    editingName = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.swTextTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)

            Text("\(tracks.count) songs · \(Format.shortDuration(tracks.count))")
                .font(.swBody)
                .foregroundStyle(Color.swTextSecondary)
                .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var songList: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                TrackListRow(track: track)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let exportError {
                Text(exportError)
                    .font(.swCaption)
                    .foregroundStyle(Color.swDestructive)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }

            Button {
                Task { await export() }
            } label: {
                Group {
                    if isExporting {
                        ProgressView().tint(Color.swOnAccent)
                    } else {
                        Text(exportError == nil ? "Save to Spotify" : "Try again")
                            .font(.swHeadline)
                    }
                }
                .foregroundStyle(Color.swOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.swAccent, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isExporting)

            Button {
                onSaveDraft(name)
            } label: {
                Text("Save as draft")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.swTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 52)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color.swBackground.opacity(0), location: 0),
                    .init(color: Color.swBackground, location: 0.35),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func export() async {
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            try await onExport(name)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
