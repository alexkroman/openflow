import AppKit
import Foundation

@testable import OpenFlowEngine

actor StubInjector: InjectorProtocol {
  var inserted: [String] = []
  var targetAppPids: [pid_t?] = []
  var error: (any Error & Sendable)?

  nonisolated func insert(_ text: String) async throws {
    if let e = await self.error { throw e }
    await record(text)
  }
  nonisolated func setTargetApp(_ app: NSRunningApplication?) async {
    await recordTarget(app?.processIdentifier)
  }
  private func record(_ s: String) { inserted.append(s) }
  private func recordTarget(_ p: pid_t?) { targetAppPids.append(p) }
}
