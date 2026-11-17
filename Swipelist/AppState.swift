import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Tab { case create, library, profile }

    /// Keep the in-progress form when connection setup temporarily opens Profile.
    var briefDraft = PlaylistBrief(text: "")

    @Published var signedIn = false
    @Published var tab: Tab = .create
    @Published var playlists: [Playlist] = []
    @Published var isLoadingLibrary = false
    /// Surfaced in Library when a load or save didn't reach the server, so a
    /// playlist that only exists on this device doesn't look permanently saved.
    @Published var libraryError: String?
    /// Set when the listener tried to build a playlist with no music service
    /// connected. Profile highlights the connect row until they do.
    @Published var needsMusicConnection = false

    private let repository = SupabaseRepository.shared
    private var didLoadLibrary = false

    /// Dev-only: jump straight to a screen via `-uiState <screen>` launch argument.
    /// Screens: onboarding, brief, deck, checkpoint, review, library, library-empty,
    /// playlist, profile.
    var debugScreen: String?

    /// Dev-only: run the real brief → deck pipeline headlessly, e.g.
    /// `-uiBrief "turkish hiphop" -uiEnergy Explosive -uiFor Gym`
    var debugBrief: PlaylistBrief?

    init() {
        #if DEBUG
        NSLog("SWKEYCHAIN selftest: %@", KeychainService.shared.selfTest())
        NSLog("SWSCOPES granted: %@", KeychainService.shared.load(.grantedScopes) ?? "NONE")

        // Dev probe: create a throwaway playlist and report exactly what Spotify says.
        if ProcessInfo.processInfo.arguments.contains("-testSpotifyExport") {
            Task {
                do {
                    let user = try await SpotifyService.shared.currentUser()
                    NSLog("SWPROBE user id=%@ name=%@", user.id, user.display_name ?? "-")
                    await SpotifyService.shared.probeFullExport()
                } catch {
                    NSLog("SWPROBE FAILED: %@", error.localizedDescription)
                }
            }
        }
        let args = ProcessInfo.processInfo.arguments

        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }

        if let text = value("-uiBrief") {
            signedIn = true
            debugBrief = PlaylistBrief(
                text: text,
                energy: value("-uiEnergy"),
                occasion: value("-uiFor")
            )
        }

        if let i = args.firstIndex(of: "-uiState"), i + 1 < args.count {
            let screen = args[i + 1]
            debugScreen = screen
            if screen != "onboarding" { signedIn = true }
            switch screen {
            case "library", "playlist":
                // Shows the account's real playlists — there is no sample data to
                // stand in for them now that the Library reads from Supabase.
                tab = .library
            case "library-empty":
                tab = .library
                didLoadLibrary = true
            case "profile": tab = .profile
            default: break
            }
        }
        #endif
    }

    // MARK: - Library

    /// Fills the library from the account. Runs once per launch unless forced —
    /// pull-to-refresh and a fresh sign-in force it.
    func loadLibrary(force: Bool = false) async {
        // Signed out or unconfigured: whatever was saved this session is all there
        // is, and it's already in `playlists`. Left unmarked so the first visit
        // after signing in still loads.
        guard repository.isAvailable else { return }
        guard force || !didLoadLibrary, !isLoadingLibrary else { return }

        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        do {
            playlists = try await repository.loadPlaylists()
            libraryError = nil
            didLoadLibrary = true
        } catch {
            libraryError = error.localizedDescription
        }
    }

    /// Shows the playlist in the library straight away, then persists it. The local
    /// copy stays put if the write fails, so the listener never loses the session's
    /// work to a network blip — `libraryError` says it isn't backed up.
    func save(
        name: String,
        brief: PlaylistBrief,
        tracks: [Track],
        exportedProvider: MusicProviderID? = nil,
        externalID: String? = nil
    ) {
        guard !tracks.isEmpty else { return }
        let playlist = Playlist(
            name: name,
            tracks: tracks,
            exportedProvider: exportedProvider,
            externalID: externalID
        )
        playlists.insert(playlist, at: 0)

        guard repository.isAvailable else { return }
        Task {
            do {
                let id = try await repository.savePlaylist(
                    name: name,
                    brief: brief,
                    tracks: tracks,
                    exportedProvider: exportedProvider,
                    externalID: externalID
                )
                // Adopt the server id so a later refresh matches this row rather
                // than showing it twice.
                if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
                    playlists[index].id = id
                }
                libraryError = nil
            } catch {
                libraryError = "\"\(name)\" is only on this device — \(error.localizedDescription)"
            }
        }
    }
}
