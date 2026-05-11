import Foundation

/// Append-only JSONL log of (raw STT, polished) pairs at
/// `~/Library/Logs/OpenFlow/dictations.jsonl`. Used to build a real-world
/// corpus for prompt iteration.
public enum DictationLog {
  struct Entry: Encodable {
    let polished: String
    let raw: String
    let ts: String
  }

  static let defaultURL: URL = {
    let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs/OpenFlow", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("dictations.jsonl")
  }()

  // .sortedKeys keeps the on-disk JSONL deterministic (stable diff for tests
  // and post-hoc grep). The encoder is reused across appends for cheaper
  // hot-path encoding.
  static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return e
  }()

  static let timestampFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

  public static func append(raw: String, polished: String) {
    #if DEBUG
      append(raw: raw, polished: polished, to: defaultURL, now: Date())
    #endif
  }

  static func append(raw: String, polished: String, to url: URL, now: Date) {
    let entry = Entry(polished: polished, raw: raw, ts: now.formatted(timestampFormat))
    guard var line = try? encoder.encode(entry) else { return }
    line.append(0x0A)  // '\n'

    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: line)
  }
}
