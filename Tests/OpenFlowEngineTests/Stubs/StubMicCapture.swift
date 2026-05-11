import Foundation

@testable import OpenFlowEngine

actor StubMicCapture: MicCaptureProtocol {
  var startCalls = 0
  var stopCalls = 0
  var samplesToReturn: [Float] = [0.0, 0.1, 0.2]
  var startError: (any Error & Sendable)?

  nonisolated func start() async throws {
    await incStart()
    if let e = await self.startError { throw e }
  }
  nonisolated func stop() async -> [Float] {
    await incStop()
    return await samplesToReturn
  }
  private func incStart() { startCalls += 1 }
  private func incStop() { stopCalls += 1 }
}
