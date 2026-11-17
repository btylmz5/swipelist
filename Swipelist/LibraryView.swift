import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var app: AppState
    @State private var path: [Playlist] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Library")
                        .font(.swDisplay)
                        .tracking(-0.4)
                        .foregroundStyle(Color.swTextPrimary)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                    if let error = app.libraryError {
                        errorBanner(error)
                    }

                    if app.playlists.isEmpty {
                        if app.isLoadingLibrary {
                            loadingState
                        } else {
                            emptyState
                        }
                    } else {
                        grid
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable { await app.loadLibrary(force: true) }
            .background(Color.swBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .task { await app.loadLibrary() }
        .onAppear(perform: applyDebugScreen)
    }

    private func applyDebugScreen() {
        #if DEBUG
        // `-uiState playlist` opens the first playlist's detail directly.
        guard app.debugScreen == "playlist", let first = app.playlists.first else { return }
        app.debugScreen = nil
        path = [first]
        #endif
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)],
            alignment: .leading,
            spacing: 20
        ) {
            ForEach(app.playlists) { playlist in
                NavigationLink(value: playlist) {
                    VStack(alignment: .leading, spacing: 0) {
                        PlaylistCoverView(playlist: playlist)
                        Text(playlist.name)
                            .font(.swHeadline)
                            .foregroundStyle(Color.swTextPrimary)
                            .lineLimit(1)
                            .padding(.top, 12)
                        Text("\(playlist.count) SONGS")
                            .font(.swLabel)
                            .tracking(0.8)
                            .foregroundStyle(Color.swTextTertiary)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            Button {
                app.tab = .create
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.06))
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 30, weight: .light))
                                .foregroundStyle(Color.swTextSecondary)
                        )
                    Text("New Playlist")
                        .font(.swHeadline)
                        .foregroundStyle(Color.swTextPrimary)
                        .padding(.top, 12)
                    Text("CREATE")
                        .font(.swLabel)
                        .tracking(0.8)
                        .foregroundStyle(Color.swTextTertiary)
                        .padding(.top, 4)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.swCaption)
            .foregroundStyle(Color.swDestructive)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.swDestructive.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
    }

    private var loadingState: some View {
        ProgressView()
            .tint(Color.swTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            DeckMotif()
                .frame(width: 110, height: 110)
            Text("Nothing here yet")
                .font(.swHeadline)
                .foregroundStyle(Color.swTextPrimary)
                .padding(.top, 36)
            Text("Your playlists will show up here")
                .font(.swBody)
                .foregroundStyle(Color.swTextSecondary)
                .padding(.top, 8)
            Button {
                app.tab = .create
            } label: {
                Text("Build one")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.swAccent)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.horizontal, 40)
    }
}

/// Two overlapping rounded squares at opposing angles — the deck motif for empty states.
struct DeckMotif: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                .rotationEffect(.degrees(-7))
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                .rotationEffect(.degrees(5))
        }
    }
}
