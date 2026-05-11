import Foundation

@testable import OpenFlowEngine

actor StubStyler: StylerProtocol {
  enum Mode {
    case yieldChunks([StylerEvent])
    case throwError(any Error & Sendable)
    case stallForever
  }
  private var mode: Mode

  init(mode: Mode) { self.mode = mode }

  nonisolated func style(_ raw: String) -> AsyncThrowingStream<StylerEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        let mode = await self.mode
        switch mode {
        case .yieldChunks(let events):
          for ev in events { continuation.yield(ev) }
          continuation.finish()
        case .throwError(let err):
          continuation.finish(throwing: err)
        case .stallForever:
          await withTaskCancellationHandler {
            while !Task.isCancelled {
              try? await Task.sleep(for: .milliseconds(50))
            }
            continuation.finish()
          } onCancel: {
            continuation.finish()
          }
        }
      }
    }
  }
}
