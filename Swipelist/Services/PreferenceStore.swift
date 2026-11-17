import Foundation
import Combine

@MainActor final class PreferenceStore: ObservableObject {
    static let shared = PreferenceStore()
    @Published private(set) var profile = PreferenceProfile()
    @Published private(set) var lastSync: Date?
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    struct Feedback: Decodable { let candidate_id: String; let brief: String; let verdict: String }
    @Published private(set) var feedback: [Feedback] = []
    private var owner: String?

    func load(userID: String?) async {
        if owner == userID {
            while loading { try? await Task.sleep(for: .milliseconds(30)); if Task.isCancelled { return } }
            return
        }
        owner = userID; profile = PreferenceProfile(); feedback = []; lastSync = nil; error = nil; loading = false
        guard let userID else { return }
        loading = true
        defer { if owner == userID { loading = false } }
        do {
            let value = try await SupabaseRepository.shared.loadPreferences()
            guard owner == userID else { return }
            profile = value ?? PreferenceProfile(); lastSync = Date()
            let rows = try await SupabaseRepository.shared.loadPreferenceFeedback()
            if owner == userID { feedback = rows }
        } catch { if owner == userID { self.error = "Preferences couldn't sync. Try again in Profile." } }
    }
    func save(_ value: PreferenceProfile) async -> Bool {
        guard let userID = SupabaseAuth.shared.userID else { return false }
        do {
            try await SupabaseRepository.shared.savePreferences(value)
            guard userID == SupabaseAuth.shared.userID else { return false }
            owner = userID; profile = value; lastSync = Date(); error = nil
            return true
        } catch { self.error = "Preferences weren't saved. Please retry."; return false }
    }
    func record(candidateID: String, brief: String, verdict: String) async {
        let userID = SupabaseAuth.shared.userID
        do {
            try await SupabaseRepository.shared.savePreferenceFeedback(candidateID: candidateID, brief: brief, verdict: verdict)
            if owner == userID { feedback.insert(Feedback(candidate_id: candidateID, brief: brief, verdict: verdict), at: 0) }
        } catch { if owner == userID { self.error = "Feedback wasn't synced. Please retry." } }
    }
    func reset() async {
        do { try await SupabaseRepository.shared.resetPreferenceFeedback(); feedback = []; _ = await save(PreferenceProfile(completed: true)) }
        catch { self.error = "Reset couldn't complete. Please retry." }
    }
    func reload() async { owner = nil; await load(userID: SupabaseAuth.shared.userID) }
    func clearMemory() { owner = nil; profile = PreferenceProfile(); feedback = []; lastSync = nil; error = nil; loading = false }
}
