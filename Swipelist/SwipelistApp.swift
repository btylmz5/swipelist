import SwiftUI

@main
struct SwipelistApp: App {
    @StateObject private var app = AppState()
    @StateObject private var account = SupabaseAuth.shared
    @StateObject private var auth = SpotifyAuth()

    var body: some Scene {
        WindowGroup {
            Group {
                if app.signedIn || account.isSignedIn {
                    RootView().id(account.userID)
                } else {
                    OnboardingView(account: account)
                }
            }
            .environmentObject(app)
            .environmentObject(account)
            .environmentObject(auth)
            .preferredColorScheme(.dark)
            .animation(.easeInOut(duration: 0.3), value: account.isSignedIn)
            .task(id: account.userID) { await PreferenceStore.shared.load(userID: account.userID) }
            .task {
                if !app.signedIn {
                    await account.restore()
                    await auth.restoreSession()
                }
                await app.loadLibrary()
            }
        }
    }
}
