import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: SpotifyAuth
    @EnvironmentObject private var account: SupabaseAuth

    @ObservedObject private var preferences = PreferenceStore.shared
    @State private var showPreferences = false
    @State private var resetConfirmation = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Profile")
                    .font(.swDisplay)
                    .tracking(-0.4)
                    .foregroundStyle(Color.swTextPrimary)
                    .padding(.top, 16)

                accountCard
                    .padding(.top, 24)

                Text("MUSIC")
                    .font(.swLabel)
                    .tracking(0.8)
                    .foregroundStyle(Color.swTextTertiary)
                    .padding(.top, 32)
                    .padding(.bottom, 10)

                // The nudge shown after they tried to build a playlist with nothing
                // connected — the deck can't resolve or preview a single song without it.
                if app.needsMusicConnection, !auth.isAuthenticated {
                    Text("Connect a music service to start building playlists.")
                        .font(.swCaption)
                        .foregroundStyle(Color.swAccent)
                        .padding(.bottom, 10)
                }

                spotifyRow
                SpotifyAccessTestView()
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR MUSIC TASTE").font(.swLabel)
                    Text(preferences.profile.isEmpty ? "No explicit preferences yet" : "Source: preferences you provided")
                    Text(RecommendationFeatures.spotifyLocalExperiment ? "Development experiment: Spotify history and library matching on device. Snapshot refreshed for each deck; no Spotify data sent to AI." : "Spotify listening history and playlist analysis: off")
                        .font(.swCaption).foregroundStyle(Color.swTextSecondary)
                    if let date = preferences.lastSync { Text("Last preference sync: \(date.formatted())").font(.swCaption) }
                    if let error = preferences.error { Text(error).foregroundStyle(.red); Button("Retry sync") { Task { await preferences.reload() } } }
                    Button("Edit music preferences") { showPreferences = true }
                    Button("Reset music preferences", role: .destructive) { resetConfirmation = true }
                }.padding(.vertical, 20)
                appleMusicRow
                    .padding(.top, 10)

                Button {
                    auth.signOut()
                    account.signOut()
                    preferences.clearMemory()
                    app.signedIn = false
                    app.needsMusicConnection = false
                    app.briefDraft = PlaylistBrief(text: "")
                } label: {
                    Text("Sign out of Swipelist")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.swTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.plain)
                .padding(.top, 36)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.swBackground)
        .sheet(isPresented: $showPreferences) { PreferenceEditorView() }
        .confirmationDialog("Reset your stated music preferences and feedback?", isPresented: $resetConfirmation) {
            Button("Reset", role: .destructive) { Task { await preferences.reset() } }
        }
        .task { await preferences.load(userID: account.userID) }
        .onChange(of: auth.isAuthenticated) { _, connected in
            if connected { app.needsMusicConnection = false }
        }
    }

    private var accountCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.swSurfaceControl)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.swTextSecondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName ?? "Signed in")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.swTextPrimary)
                    .lineLimit(1)
                Text("Your playlists sync to this account")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.swTextTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.swSurfaceCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var spotifyRow: some View {
        HStack(spacing: 14) {
            serviceIcon("music.note", tinted: auth.isAuthenticated)

            VStack(alignment: .leading, spacing: 2) {
                Text("Spotify")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.swTextPrimary)
                Text(auth.isAuthenticated ? "Connected" : "Not connected")
                    .font(.system(size: 13))
                    .foregroundStyle(auth.isAuthenticated ? Color.swAccent : Color.swTextTertiary)
            }

            Spacer(minLength: 0)

            Button {
                Task {
                    if auth.isAuthenticated {
                        auth.signOut()
                    } else {
                        await auth.signIn()
                    }
                }
            } label: {
                Group {
                    if auth.isWorking {
                        ProgressView().tint(Color.swOnAccent)
                    } else {
                        Text(auth.isAuthenticated ? "Disconnect" : "Connect")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(auth.isAuthenticated ? Color.swTextSecondary : Color.swOnAccent)
                .padding(.horizontal, 18)
                .frame(height: 38)
                .background(
                    Capsule().fill(auth.isAuthenticated ? Color.swSurfaceControl : Color.swAccent)
                )
            }
            .buttonStyle(.plain)
            .disabled(auth.isWorking)
        }
        .padding(16)
        .background(Color.swSurfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    app.needsMusicConnection && !auth.isAuthenticated ? Color.swAccent : .clear,
                    lineWidth: 1.5
                )
        )
    }

    /// Listed but not connectable: MusicKit needs a paid Apple Developer account to
    /// issue a developer token, so the row announces itself rather than offering a
    /// Connect button that could only fail.
    private var appleMusicRow: some View {
        HStack(spacing: 14) {
            serviceIcon("applelogo", tinted: false)

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Music")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.swTextSecondary)
                Text("Coming soon")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.swTextTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.swSurfaceCard, in: RoundedRectangle(cornerRadius: 16))
        .opacity(0.6)
    }

    private func serviceIcon(_ name: String, tinted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.swSurfaceControl)
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tinted ? Color.swAccent : Color.swTextSecondary)
            )
    }
}
