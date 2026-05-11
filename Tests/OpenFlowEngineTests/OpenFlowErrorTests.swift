import Foundation
import Testing

@testable import OpenFlowEngine

@Suite("OpenFlowError")
struct OpenFlowErrorTests {
  @Test("each non-wrapping case has a non-empty errorDescription")
  func descriptionsExist() {
    let cases: [OpenFlowError] = [
      .microphonePermissionDenied,
      .accessibilityPermissionMissing,
      .stylerTimedOut,
      .targetAppLost
    ]
    for c in cases {
      #expect(!(c.errorDescription ?? "").isEmpty)
    }
  }

  @Test("wrapping cases include the underlying error description")
  func wrappingCasesIncludeUnderlying() {
    let underlying = NSError(domain: "Test", code: 1, userInfo: [
      NSLocalizedDescriptionKey: "boom-marker-42"
    ])
    let wrapped: [OpenFlowError] = [
      .modelDownloadFailed(underlying: underlying),
      .modelLoadFailed(underlying: underlying),
      .sttFailed(underlying: underlying),
      .stylerFailed(underlying: underlying),
      .audioCaptureFailed(underlying: underlying)
    ]
    for w in wrapped {
      #expect(w.errorDescription?.contains("boom-marker-42") == true)
    }
  }

  @Test("equal singleton cases compare equal")
  func equalSingletons() {
    #expect(OpenFlowError.stylerTimedOut == .stylerTimedOut)
    #expect(OpenFlowError.targetAppLost == .targetAppLost)
    #expect(OpenFlowError.microphonePermissionDenied == .microphonePermissionDenied)
    #expect(OpenFlowError.accessibilityPermissionMissing == .accessibilityPermissionMissing)
  }

  @Test("different singleton cases compare unequal")
  func unequalSingletons() {
    #expect(OpenFlowError.stylerTimedOut != .targetAppLost)
    #expect(OpenFlowError.microphonePermissionDenied != .accessibilityPermissionMissing)
  }

  @Test("wrapping cases compare by underlying localizedDescription")
  func wrappedEquality() {
    let a = NSError(domain: "X", code: 1, userInfo: [NSLocalizedDescriptionKey: "same"])
    let b = NSError(domain: "Y", code: 99, userInfo: [NSLocalizedDescriptionKey: "same"])
    let c = NSError(domain: "X", code: 1, userInfo: [NSLocalizedDescriptionKey: "different"])
    #expect(OpenFlowError.sttFailed(underlying: a) == .sttFailed(underlying: b))
    #expect(OpenFlowError.sttFailed(underlying: a) != .sttFailed(underlying: c))
  }

  @Test("wrapping cases of different kinds never compare equal")
  func crossKindInequality() {
    let e = NSError(domain: "X", code: 1, userInfo: [NSLocalizedDescriptionKey: "same"])
    #expect(OpenFlowError.sttFailed(underlying: e) != .stylerFailed(underlying: e))
    #expect(OpenFlowError.modelLoadFailed(underlying: e) != .modelDownloadFailed(underlying: e))
  }
}
