import Foundation

// `Secrets` comes from Swipelist/Config.swift when it exists; run.sh otherwise
// compiles in a temporary shim that reads ANTHROPIC_API_KEY from the environment.

var failures = 0
func check(_ label: String, _ condition: Bool) {
    print("\(condition ? "  PASS" : "  FAIL") — \(label)")
    if !condition { failures += 1 }
}

// MARK: - Defensive decoding

print("=== Defensive decoding ===\n")

let bare = #"[{"artist":"Phoebe Bridgers","track":"Motion Sickness"},{"artist":"Big Thief","track":"Paul"}]"#
let fenced = """
```json
[{"artist":"Ezhel","track":"Geceler"}]
```
"""
let fencedPlain = """
```
[{"artist":"Alvvays","track":"Archie, Marry Me"}]
```
"""
let withPreamble = """
Here are the songs you asked for:

[{"artist":"Ceza","track":"Suspus"},{"artist":"Sagopa Kajmer","track":"Bir Pesimistin Gozyaslari"}]

Let me know if you'd like adjustments.
"""

for (label, raw) in [
    ("bare JSON array", bare),
    ("```json fence", fenced),
    ("``` fence", fencedPlain),
    ("preamble + trailing prose", withPreamble),
] {
    do {
        let songs = try PromptParser.decodeSuggestions(from: raw)
        print("  \(label): \(songs.map { "\($0.artist) — \($0.title)" }.joined(separator: ", "))")
        check("\(label) decoded", !songs.isEmpty)
    } catch {
        check("\(label) decoded", false)
        print("    error: \(error)")
    }
}

print("\n=== Version-suffix stripping (rule 6 backstop) ===\n")

for (input, expected) in [
    ("Geceler (feat. Murda)", "Geceler"),
    ("Motion Sickness - Remastered 2021", "Motion Sickness"),
    ("Suspus [Live]", "Suspus"),
    ("Archie, Marry Me", "Archie, Marry Me"),
    ("Paul (Radio Edit)", "Paul"),
] {
    let got = PromptParser.stripVersionSuffixes(input)
    check("\"\(input)\" -> \"\(got)\"", got == expected)
}

print("\n=== Artist matching (rejects near-miss credits) ===\n")

check("\"VIZE, Joker Bra & Leony\" does NOT contain artist \"Joker\"",
      !"VIZE, Joker Bra & Leony".artistComponents.contains("Joker".folded))
check("\"VIZE, Joker Bra & Leony\" contains \"Joker Bra\"",
      "VIZE, Joker Bra & Leony".artistComponents.contains("Joker Bra".folded))
check("\"Murda & Ezhel\" contains \"Ezhel\"",
      "Murda & Ezhel".artistComponents.contains("Ezhel".folded))
check("\"Murda & Ezhel\" leads with Murda",
      "Murda & Ezhel".primaryArtistKey == "Murda".folded)
check("Şanışer folds to match Saniser",
      "Şanışer".folded == "Saniser".folded)

print("\n=== Rejections (must throw) ===\n")

for (label, raw) in [
    ("prose with no JSON", "I'm sorry, I can't help with that."),
    ("truncated JSON", #"[{"artist":"Ezhel","tra"#),
    ("empty string", ""),
    ("array of empty objects", #"[{},{}]"#),
] {
    do {
        _ = try PromptParser.decodeSuggestions(from: raw)
        check("\(label) rejected", false)
    } catch {
        check("\(label) rejected (\(error))", true)
    }
}

// MARK: - Live call

print("\n=== Live suggestions ===\n")
if Secrets.anthropicAPIKey.isEmpty {
    print("  SKIPPED — no key in Swipelist/Config.swift or ANTHROPIC_API_KEY.")
} else {
    let brief = CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "Motive type turkish hiphop songs"
    let energy = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Intense"
    let occasion = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "Workout"
    let refinements = [
        "Energy level: \(energy.lowercased())",
        "Listening context: \(occasion.lowercased())",
    ]

    print("  Brief: \"\(brief)\"  chips: \(energy) / \(occasion)\n")
    do {
        let songs = try await PromptParser.suggestSongs(
            text: brief, refinements: refinements, count: 15
        )
        for song in songs { print("    \(song.artist) — \(song.title)") }
        check("returned suggestions", !songs.isEmpty)

        let counts = Dictionary(grouping: songs, by: { $0.artist.primaryArtistKey })
        let withinCaps = counts.allSatisfy { artist, entries in
            let named = " \(brief.folded) ".contains(" \(artist) ")
            return entries.count <= (named ? 5 : 2)
        }
        check("artist caps: 5 for a named artist, 2 otherwise", withinCaps)
        check("no duplicate songs", Set(songs.map(\.dedupeKey)).count == songs.count)
    } catch {
        check("live call succeeded", false)
        print("    error: \(error)")
    }
}

print("\n\(failures == 0 ? "All checks passed." : "\(failures) check(s) FAILED.")")
exit(failures == 0 ? 0 : 1)
