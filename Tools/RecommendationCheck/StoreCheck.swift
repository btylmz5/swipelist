import Foundation
@MainActor final class SupabaseAuth { static let shared=SupabaseAuth();var userID:String? }
@MainActor final class SupabaseRepository {
 static let shared=SupabaseRepository()
 func loadPreferences() async throws -> PreferenceProfile? {
  let id=SupabaseAuth.shared.userID ?? "none"
  try await Task.sleep(for:.milliseconds(id=="A" ? 100:10))
  return PreferenceProfile(artists:[id],completed:true)
 }
 func loadPreferenceFeedback() async throws -> [PreferenceStore.Feedback] {[]}
 func savePreferences(_ profile:PreferenceProfile) async throws {}
 func savePreferenceFeedback(candidateID:String,brief:String,verdict:String) async throws {}
 func resetPreferenceFeedback() async throws {}
}
@main struct StoreCheck {
 @MainActor static func main() async {
  let store=PreferenceStore.shared
  SupabaseAuth.shared.userID="A"
  let old=Task {await store.load(userID:"A")}
  try? await Task.sleep(for:.milliseconds(15))
  SupabaseAuth.shared.userID="B"
  await store.load(userID:"B")
  await old.value
  precondition(store.profile.artists==["B"])
  SupabaseAuth.shared.userID=nil
  await store.load(userID:nil)
  precondition(store.profile.isEmpty && store.feedback.isEmpty && store.lastSync==nil)
  print("PASS account isolation: late response cannot overwrite new account; sign-out clears profile and feedback")
 }
}
