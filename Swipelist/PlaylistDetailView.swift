import SwiftUI

/// One saved playlist: its artwork, its songs, and a way back out to the service
/// it was exported to.
struct PlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let playlist: Playlist

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.swBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    songList
                }
                .padding(.bottom, 40)
            }

            backButton
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.swTextPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .padding(.top, 8)
        .accessibilityLabel("Back to library")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlaylistCoverView(playlist: playlist, cornerRadius: 20)
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 56)

            Text(playlist.name)
                .font(.swDisplay)
                .tracking(-0.4)
                .foregroundStyle(Color.swTextPrimary)
                .padding(.top, 24)

            Text("\(playlist.count) songs · \(Format.shortDuration(playlist.count))")
                .font(.swBody)
                .foregroundStyle(Color.swTextSecondary)
                .padding(.top, 6)

            if let url = playlist.externalURL {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.forward.square")
                        Text("Open in \(playlist.exportedProvider?.displayName ?? "Spotify")")
                            .font(.swHeadline)
                    }
                    .foregroundStyle(Color.swOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.swAccent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            } else {
                Text("Saved as a draft — not on a music service yet.")
                    .font(.swCaption)
                    .foregroundStyle(Color.swTextTertiary)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var songList: some View {
        if playlist.tracks.isEmpty {
            Text("This playlist has no songs.")
                .font(.swBody)
                .foregroundStyle(Color.swTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { _, track in
                    TrackListRow(track: track)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
    }
}
