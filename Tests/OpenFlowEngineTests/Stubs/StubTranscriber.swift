import Foundation

@testable import OpenFlowEngine

actor StubTranscriber: TranscriberProtocol {
  enum Mode {
    case yieldChunks([String])
    case throwError(any Error & Sendable)
    case stallForever
  }
  private var mode: Mode

  init(mode: Mode) { self.mode = mode }

  nonisolated func transcribeStream(samples: [Float], sampleRate: Int) -> AsyncThrowingStream<
    String, Error
  > {
    AsyncThrowingStream { continuation in
      let task = Task {
        // Catch-all in case we're cancelled at `await self.mode` before
        // reaching any explicit finish() — otherwise the continuation leaks
        // when a test scope drops the iterator early. Repeat finish() calls
        // are no-ops, so the per-case finishes below remain safe.
        defer { continuation.finish() }
        let mode = await self.mode
        switch mode {
        case .yieldChunks(let chunks):
          for chunk in chunks { continuation.yield(chunk) }
          continuation.finish()
        case .throwError(let err):
          continuation.finish(throwing: err)
        case .stallForever:
          // Stall until the task itself is cancelled. Task.sleep throws on
          // cancel, exiting the loop; the deferred finish() above cleans up.
          while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
          }
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
