import Foundation
import OpenFlowEngine
import TinyAudio

// CLI for iterating on the cleanup prompt against the Qwen3.5-2B model managed
// by TinyAudio. Reads prompt and test cases from disk so we can edit + re-run
// without recompiling. Model is downloaded from HF on first run, cached
// thereafter under ~/Library/Application Support/TinyAudio/Models/.
//
// Usage:
//   openflow-prompt-test <prompt-file> <cases-file> [--no-think]

@main
struct PromptTestRunner {
  enum Mode: String, Codable {
    case exact, contains
    case notContains = "not_contains"
    case empty, regex, similarity
  }

  struct TestCase: Codable {
    let id: String
    let input: String
    let mode: Mode
    let expected: String?
    let threshold: Double?  // similarity threshold, default 0.85
  }

  static func main() async {
    guard CommandLine.arguments.count >= 3 else {
      FileHandle.standardError.write(
        Data("usage: openflow-prompt-test <prompt-file> <cases-file> [--no-think]\n".utf8))
      exit(2)
    }
    let promptURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let casesURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let noThink = CommandLine.arguments.dropFirst(3).contains("--no-think")

    let prompt: String
    let cases: [TestCase]
    do {
      prompt = try String(contentsOf: promptURL, encoding: .utf8)
      let data = try Data(contentsOf: casesURL)
      cases = try JSONDecoder().decode([TestCase].self, from: data)
    } catch {
      print("Failed to load inputs: \(error)")
      exit(1)
    }

    print("Loading model (first run downloads from HuggingFace)...")
    let session: TinyAudio.ChatSession
    do {
      session = try await TinyAudio.ChatSession.load(
        systemPrompt: prompt,
        generation: TinyAudio.GenerationConfig(maxTokens: 512, temperature: 0.0),
        progress: { p in
          if case .downloading(let f) = p {
            FileHandle.standardError.write(
              Data(String(format: "\rdownloading %.0f%%", f * 100).utf8))
          }
        }
      )
    } catch {
      print("Model load failed: \(error)")
      exit(1)
    }
    print("\nModel loaded. Running \(cases.count) cases...\n")

    var pass = 0
    var fail = 0
    var simScores: [Double] = []
    for tc in cases {
      let raw = await generate(session: session, raw: tc.input, noThink: noThink)
      let output = stripThinkBlocks(raw)
      let (ok, score) = evaluateWithScore(
        mode: tc.mode, expected: tc.expected, threshold: tc.threshold, actual: output)
      let status = ok ? "PASS" : "FAIL"
      if ok { pass += 1 } else { fail += 1 }
      if let score { simScores.append(score) }
      print("[\(status)] \(tc.id)\(score.map { String(format: " sim=%.3f", $0) } ?? "")")
      print("  in:       \(quote(tc.input))")
      print("  expected: \(tc.mode.rawValue)\(tc.expected.map { " " + quote($0) } ?? "")")
      print("  actual:   \(quote(output))")
      print()
    }
    print("Results: \(pass)/\(cases.count) passing")
    if !simScores.isEmpty {
      let avg = simScores.reduce(0, +) / Double(simScores.count)
      print(String(format: "Mean similarity: %.3f over %d cases", avg, simScores.count))
    }
    if fail > 0 { exit(1) }
  }

  static func generate(
    session: TinyAudio.ChatSession, raw: String, noThink: Bool
  ) async -> String {
    let userText = StylingPrompt.userMessage(for: raw) + (noThink ? " /no_think" : "")
    var out = ""
    do {
      for try await chunk in session.respond(to: userText) { out += chunk }
      return out
    } catch {
      return "<<error: \(error)>>"
    }
  }

  static func evaluateWithScore(
    mode: Mode, expected: String?, threshold: Double?, actual: String
  ) -> (Bool, Double?) {
    let trimmed = actual.trimmingCharacters(in: .whitespacesAndNewlines)
    switch mode {
    case .exact:
      return (trimmed == (expected ?? ""), nil)
    case .contains:
      guard let e = expected else { return (false, nil) }
      return (trimmed.localizedCaseInsensitiveContains(e), nil)
    case .notContains:
      guard let e = expected else { return (true, nil) }
      return (!trimmed.localizedCaseInsensitiveContains(e), nil)
    case .empty:
      return (trimmed.isEmpty, nil)
    case .regex:
      guard let e = expected, let regex = try? Regex(e) else { return (false, nil) }
      return (trimmed.contains(regex), nil)
    case .similarity:
      guard let e = expected else { return (false, nil) }
      let score = similarity(trimmed, e)
      return (score >= (threshold ?? 0.85), score)
    }
  }

  /// 1 - normalized Levenshtein distance, computed on lowercased strings.
  /// 1.0 = identical, 0.0 = totally different.
  static func similarity(_ a: String, _ b: String) -> Double {
    let aa = Array(a.lowercased())
    let bb = Array(b.lowercased())
    if aa.isEmpty && bb.isEmpty { return 1.0 }
    let dist = levenshtein(aa, bb)
    let maxLen = max(aa.count, bb.count)
    return 1.0 - Double(dist) / Double(maxLen)
  }

  static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    var curr = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
      curr[0] = i
      for j in 1...b.count {
        let cost = (a[i - 1] == b[j - 1]) ? 0 : 1
        curr[j] = min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
      }
      swap(&prev, &curr)
    }
    return prev[b.count]
  }

  static func stripThinkBlocks(_ s: String) -> String {
    guard let regex = try? Regex("(?s)<think>.*?</think>") else { return s }
    return s.replacing(regex, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func quote(_ s: String) -> String {
    "\"\(s.replacingOccurrences(of: "\n", with: "\\n"))\""
  }
}
