import Foundation
import Testing

@testable import OpenFlowEngine

/// Env-gated because this hits the real AVAudioEngine and the system mic.
/// Set OPENFLOW_LIVE_AUDIO_TESTS=1 in the scheme to enable.
@Suite("MicCapture.levels (live)")
struct MicCaptureLevelsTests {
  @Test func levelsYieldDuringCapture() async throws {
    guard ProcessInfo.processInfo.environment["OPENFLOW_LIVE_AUDIO_TESTS"] == "1" else {
      return
    }
    let mic = MicCapture()

    let collector = Task { () -> [Float] in
      var collected: [Float] = []
      let deadline = Date().addingTimeInterval(0.7)
      for await level in mic.levels {
        collected.append(level)
        if collected.count >= 3 || Date() > deadline || Task.isCancelled { break }
      }
      return collected
    }

    try await mic.start()
    try await Task.sleep(for: .milliseconds(500))
    _ = await mic.stop()
    collector.cancel()

    let levels = await collector.value
    #expect(!levels.isEmpty, "expected at least one RMS sample during 500ms of capture")
    #expect(levels.allSatisfy { $0 >= 0 }, "RMS values must be non-negative")
  }
}
