// Song suggestions, server-side.
//
// The whole point of this function is that GEMINI_API_KEY lives in Supabase secrets
// rather than inside the app binary, where anyone who downloads the IPA can extract
// it. It also means the model can be swapped without shipping an app update.
//
// Deploy:  supabase functions deploy suggest-songs
// Secret:  supabase secrets set GEMINI_API_KEY=...

interface Candidate {
  artist: string;
  track: string;
  /** Swipe history only: seconds of preview heard before the verdict. */
  listen_seconds?: number | null;
}

interface RequestBody {
  text: string;
  energy?: string | null;
  occasion?: string | null;
  count?: number;
  refinements?: string[];
  liked?: Candidate[];
  skipped?: Candidate[];
  excludeArtists?: string[];
}

// Google retires these faster than an app ships, so try current models in order
// and remember the first that answers.
const MODEL_CANDIDATES = [
  "gemini-3-flash-preview",
  "gemini-flash-latest",
  "gemini-2.5-flash",
  "gemini-2.0-flash",
];
let workingModel: string | null = null;

// Mirrors GeminiService.systemInstruction in the app. Keep the two in sync:
// this prompt plus Spotify's forgiving search is what produces the decks, and a
// stale copy here means flipping to the server silently degrades them.
const systemInstruction = (count: number) => `
You are a music curator AI. Your ONLY job is to suggest real, existing songs that match exactly what the user describes.

CRITICAL RULES — you MUST follow these without exception:
1. You MUST respect the genre, language, and style the user specifies. If they say "Turkish hip-hop", ALL suggestions must be Turkish hip-hop songs. Never substitute a different genre.
2. If the user mentions an artist name as a reference (e.g. "Motive type"), treat that artist as a style guide and suggest songs from that artist OR artists with a very similar style.
3. If a specific language is implied (e.g. "Turkish", "Spanish", "French"), the songs MUST be in that language unless the user said otherwise.
4. You MUST return exactly ${count} suggestions.
5. Return ONLY a raw JSON array — no markdown, no explanation, no code fences.
6. Format: [{"artist": "Artist Name", "track": "Track Name"}, ...]
7. All suggested songs must be real and available on Spotify.
8. Do NOT repeat the same artist more than 2 times — WITH ONE EXCEPTION: any artist the listener named in their request may appear up to 5 times. If they ask for "Travis Scott type songs" they want a good number of actual Travis Scott songs, alongside similar artists. If they name several artists, spread that allowance across all of them.
9. CRITICAL: Provide ONLY the pure track name and pure primary artist name. Do NOT include "(feat...)", "(Remastered...)", or "- Live" in the track name.
10. BREADTH IS CRITICAL. Use at least ${Math.max(8, Math.floor(count * 2 / 3))} DIFFERENT artists. Do not fill the list with the four or five most obvious names in the genre — that makes the result feel repetitive. Mix the well-known artists with genuinely lesser-known ones from the same scene, and include deeper album cuts, not only the biggest singles.
`.trim();

/** Groups by lead artist so the taste signal is explicit rather than buried in titles. */
function rankArtists(items: Candidate[]): { name: string; count: number }[] {
  const counts = new Map<string, { name: string; count: number }>();
  for (const item of items) {
    // Lead artist only: "Murda & Ezhel" counts as Murda.
    const lead = item.artist.split(/ & |, | feat\.? | ft\.? /i)[0].trim();
    const key = lead.toLowerCase();
    const existing = counts.get(key);
    counts.set(key, { name: existing?.name ?? lead, count: (existing?.count ?? 0) + 1 });
  }
  return [...counts.values()].sort((a, b) => b.count - a.count);
}

function buildUserMessage(body: RequestBody, count: number): string {
  let message = `USER VIBE REQUEST: "${body.text}"

Analyze this request carefully:
- What genre did they specify? Stick strictly to that genre.
- What language/region did they imply? Only suggest songs from that region/language.
- What energy level? (hype, chill, sad, aggressive, etc.)
- Did they name an artist as a style reference? Include that artist's songs and very similar artists.
`;

  if (body.energy) message += `\nRequested energy: ${body.energy}\n`;
  if (body.occasion) message += `Listening context: ${body.occasion}\n`;

  const refinements = body.refinements ?? [];
  if (refinements.length) {
    message += `\nThe user also pinned these down — every one of them applies:\n` +
      refinements.map((r) => `- ${r}`).join("\n") + "\n";
  }

  const liked = body.liked ?? [];
  const skipped = body.skipped ?? [];

  if (liked.length) {
    message += `\n\nSongs the user LIKED — suggest MORE like these (same genre, energy, vibe):\n` +
      liked.map((s) => `• ${s.artist} - ${s.track}`).join("\n") + "\n";
  }
  if (skipped.length) {
    // The timing is the strength of the signal — see GeminiService.
    const line = (s: Candidate) =>
      `• ${s.artist} - ${s.track}` +
      (s.listen_seconds != null ? ` (skipped after ${s.listen_seconds}s)` : "");
    message += `\n\nSongs the user SKIPPED — do NOT suggest anything in this style:\n` +
      skipped.map(line).join("\n") + "\n" +
      "Skip timing matters: a skip in the first few seconds strongly rejects that sound; " +
      "a skip after 20s+ was a near-miss, so its style is not entirely wrong.\n";
  }

  const kept = rankArtists(liked);
  const rejected = rankArtists(skipped).filter(
    (r) => !kept.some((k) => k.name.toLowerCase() === r.name.toLowerCase()),
  );
  if (kept.length || rejected.length) {
    message += "\n\nTASTE SO FAR — weight this above the original request where they conflict:";
    if (kept.length) {
      message += `\n• KEEPING: ${kept.map((a) => `${a.name} (kept ${a.count})`).join(", ")}. ` +
        `Lean into these artists and ones that genuinely sound like them.`;
    }
    if (rejected.length) {
      message += `\n• REJECTING: ${rejected.map((a) => `${a.name} (skipped ${a.count})`).join(", ")}. ` +
        `Do not suggest these artists again, and avoid that sound.`;
    }
  }

  const excludeArtists = body.excludeArtists ?? [];
  if (excludeArtists.length) {
    // Without this a refill happily returns the same obvious names again.
    message += `\n\nARTISTS ALREADY IN THE DECK — do NOT suggest any of these again. ` +
      `Find different artists in the same style:\n` +
      excludeArtists.slice(0, 40).join(", ");
  }

  message += `\n\nNow return exactly ${count} song suggestions as a raw JSON array.`;
  return message;
}

/** Tolerates fences and surrounding prose — the model is told to return bare JSON but doesn't always. */
function parseSuggestions(raw: string): Candidate[] {
  const start = raw.indexOf("[");
  const end = raw.lastIndexOf("]");
  if (start === -1 || end === -1 || end <= start) return [];

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw.slice(start, end + 1));
  } catch {
    return [];
  }
  if (!Array.isArray(parsed)) return [];

  const seen = new Set<string>();
  const out: Candidate[] = [];
  for (const item of parsed) {
    const artist = typeof item?.artist === "string" ? item.artist.trim() : "";
    const track = typeof item?.track === "string" ? item.track.trim() : "";
    if (!artist || !track) continue;
    const key = `${artist.toLowerCase()}|${track.toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ artist, track });
  }
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), {
      status: 405,
      headers: { "content-type": "application/json" },
    });
  }

  // Supabase verifies the caller's JWT before this runs, so an unauthenticated
  // client never reaches the Gemini key.
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "GEMINI_API_KEY is not set" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }
  if (!body.text?.trim()) {
    return new Response(JSON.stringify({ error: "text is required" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const count = Math.min(Math.max(body.count ?? 26, 1), 40);
  const payload = {
    system_instruction: { parts: [{ text: systemInstruction(count) }] },
    contents: [{ parts: [{ text: buildUserMessage(body, count) }] }],
  };

  const models = workingModel ? [workingModel] : MODEL_CANDIDATES;
  let lastError = "no model responded";

  for (const model of models) {
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        lastError = `${model}: HTTP ${response.status} ${(await response.text()).slice(0, 200)}`;
        continue;
      }

      const data = await response.json();
      const text: string = (data?.candidates?.[0]?.content?.parts ?? [])
        .map((p: { text?: string }) => p.text ?? "")
        .join("");

      const songs = parseSuggestions(text);
      if (!songs.length) {
        lastError = `${model}: response contained no usable suggestions`;
        continue;
      }

      workingModel = model;
      return new Response(JSON.stringify({ model, songs }), {
        headers: { "content-type": "application/json" },
      });
    } catch (error) {
      lastError = `${model}: ${error instanceof Error ? error.message : String(error)}`;
    }
  }

  return new Response(JSON.stringify({ error: lastError }), {
    status: 502,
    headers: { "content-type": "application/json" },
  });
});
