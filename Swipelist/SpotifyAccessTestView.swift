import SwiftUI

struct SpotifyAccessTestView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @State private var results: [SpotifyAccessResult] = []
    @State private var working = false
    @State private var task: Task<Void,Never>?
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("SPOTIFY DATA ACCESS").font(.swLabel)
            Text("Read-only test of top music, recent listening, liked songs and playlist access. Nothing is sent to AI or used for taste analysis.")
                .font(.swCaption).foregroundStyle(Color.swTextSecondary)
            Button(auth.hasReadAccess ? "Run data access test" : "Allow read access & test") {
                task = Task {
                    working = true; results = []
                    defer { working = false }
                    if !auth.hasReadAccess { await auth.signIn(readAccess: true) }
                    guard auth.isAuthenticated, auth.hasReadAccess, !Task.isCancelled else { return }
                    let response = await SpotifyService.shared.checkReadAccess()
                    guard !Task.isCancelled else { return }
                    results = response
                }
            }.disabled(working || auth.isWorking)
            if working { ProgressView("Checking access…") }
            if let message = auth.errorMessage { Text(message).font(.swCaption).foregroundStyle(.red) }
            ForEach(results) { result in
                VStack(alignment:.leading,spacing:3) {
                    Text(result.source).font(.system(size:14,weight:.semibold))
                    Text(result.detail).font(.swCaption).foregroundStyle(Color.swTextSecondary)
                }
            }
        }.padding(.vertical,20)
        .onDisappear { task?.cancel(); results=[] }
        .onChange(of: auth.isAuthenticated) { _, connected in
            if !connected { task?.cancel(); results=[] }
        }
    }
}
