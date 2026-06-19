import Foundation
import GardenCore

/// "Talk to your flowers" — turns a gardener's plain-English wish into growth
/// rules, using the Google **Gemini API** with structured (JSON-schema) output.
///
/// This is the game's Google-AI integration: the fantasy is "if flowers could
/// think, how would they talk to each other?", so the player simply *tells* the
/// garden what to do and Gemini translates that into the deterministic rule
/// grammar the engine already understands (directions / avoid / need / cluster).
///
/// The engine stays the sole judge of win/lose — Gemini only proposes rules, so a
/// hallucination can never corrupt the puzzle; at worst the player presses Sunrise
/// and sees it didn't match. The feature is optional: with no API key the rest of
/// the game plays exactly as before.
enum GeminiClient {

    struct Suggestion {
        let rules: RuleSet
        let explanation: String
    }

    enum GeminiError: LocalizedError {
        case missingKey
        case http(Int, String)
        case empty
        case badJSON

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Set GEMINI_API_KEY to talk to your flowers (see README)."
            case .http(let code, _):
                return "Gemini request failed (HTTP \(code))."
            case .empty:
                return "Gemini returned nothing — try rephrasing."
            case .badJSON:
                return "Couldn't understand Gemini's reply — try rephrasing."
            }
        }
    }

    // gemini-2.0-flash was deprecated 2026-03-03 and now returns persistent 429s;
    // 2.5-flash is the current free-tier model with structured-output support.
    private static let model = "gemini-2.5-flash"

    /// Ask Gemini to translate `prompt` into rules for the `settable` plants,
    /// allowed to reference any color in `settable` + `seeds` for avoid/need.
    static func suggestRules(prompt: String,
                             settable: [Character],
                             seeds: [Character]) async throws -> Suggestion {
        guard let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
              !key.isEmpty else { throw GeminiError.missingKey }

        let allColors = (settable + seeds).map(String.init)
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")!

        let system = """
        You translate a gardener's plain-English wish into growth rules for a \
        cellular-automaton garden that honors Alan Turing's work on morphogenesis.

        You may assign a rule to each of these plants: \(settable.map(String.init).joined(separator: ", ")).
        You may also reference these fixed seed plants in avoid/need: \(seeds.isEmpty ? "(none)" : seeds.map(String.init).joined(separator: ", ")).
        Valid colors are exactly: \(allColors.joined(separator: ", ")).

        Each rule has:
        - directions: a subset of N, S, E, W — which way the plant spreads each step. \
        Use all four for "spread everywhere" / "flood" / "fill".
        - avoid: a color this plant refuses to grow next to (inhibition), or "none".
        - need: a color this plant may grow next to only (activation), or "none".
        - cluster: 0, 2, or 3 — grow into a cell only if it already touches at least \
        this many of the plant's own color (0 = off). Use 2 for "fill without spilling" \
        or "only where well-supported".

        Constraints:
        - avoid and need are mutually exclusive: at most one of them may be non-"none".
        - Only use the valid colors above. Never invent a color.
        - Return one entry per plant you actually want to set.
        - explanation: one short, plain sentence describing what you set.
        """

        let schema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "rules": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "color": ["type": "STRING"],
                            "directions": ["type": "ARRAY",
                                           "items": ["type": "STRING", "enum": ["N", "E", "S", "W"]]],
                            "avoid": ["type": "STRING"],
                            "need": ["type": "STRING"],
                            "cluster": ["type": "INTEGER"],
                        ],
                        "required": ["color", "directions", "avoid", "need", "cluster"],
                        "propertyOrdering": ["color", "directions", "avoid", "need", "cluster"],
                    ],
                ],
                "explanation": ["type": "STRING"],
            ],
            "required": ["rules", "explanation"],
        ]

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json",
                "responseSchema": schema,
            ],
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 20

        // Send, retrying transient rate-limit / capacity errors with backoff.
        var data = Data()
        var attempt = 0
        while true {
            let (d, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw GeminiError.empty }
            if (200..<300).contains(http.statusCode) { data = d; break }
            if (http.statusCode == 429 || http.statusCode == 503), attempt < 2 {
                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_200_000_000)
                continue
            }
            throw GeminiError.http(http.statusCode, String(data: d, encoding: .utf8) ?? "")
        }

        let envelope = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
        guard let text = envelope.candidates?.first?.content?.parts?.first?.text,
              let payload = text.data(using: .utf8) else { throw GeminiError.empty }

        let out: LLMOut
        do { out = try JSONDecoder().decode(LLMOut.self, from: payload) }
        catch { throw GeminiError.badJSON }

        return Suggestion(rules: mapRules(out, settable: settable, allColors: settable + seeds),
                          explanation: out.explanation ?? "Rules set.")
    }

    // MARK: Mapping LLM output -> engine RuleSet (defensive)

    private static func mapRules(_ out: LLMOut, settable: [Character], allColors: [Character]) -> RuleSet {
        var rules: RuleSet = [:]
        for r in out.rules {
            guard let color = r.color.first, settable.contains(color) else { continue }

            let dirs = Set(r.directions.compactMap { Direction.from(code: Character($0)) })

            func colorRef(_ s: String?) -> Character? {
                guard let c = s?.trimmingCharacters(in: .whitespaces).first,
                      c != "n", c != "N",  // tolerate "none"/"None"
                      allColors.contains(c) else { return nil }
                return c
            }
            var avoid = colorRef(r.avoid)
            var need = colorRef(r.need)
            // Mutually exclusive: if the model set both, keep avoid, drop need.
            if avoid != nil { need = nil }
            // A plant can't avoid/need itself.
            if avoid == color { avoid = nil }
            if need == color { need = nil }

            let cluster = max(0, r.cluster ?? 0)
            rules[color] = Rule(dirs, avoid: avoid, need: need, min: cluster)
        }
        return rules
    }
}

// MARK: - Decodable DTOs

private struct GeminiEnvelope: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}

private struct LLMOut: Decodable {
    struct LLMRule: Decodable {
        let color: String
        let directions: [String]
        let avoid: String?
        let need: String?
        let cluster: Int?
    }
    let rules: [LLMRule]
    let explanation: String?
}
