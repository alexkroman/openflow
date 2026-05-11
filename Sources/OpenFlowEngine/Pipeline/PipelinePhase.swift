import Foundation

public enum PipelinePhase: Equatable, Sendable {
  case idle
  case recording
  case transcribing(rawSoFar: String)
  case styling(styledSoFar: String)
  case injecting(text: String)
  case failed(OpenFlowError)
  case cancelled

  public var isTerminal: Bool {
    switch self {
    case .idle, .failed, .cancelled: true
    default: false
    }
  }

  public var isRecording: Bool {
    if case .recording = self { true } else { false }
  }
}

extension OpenFlowError: Equatable {
  public static func == (lhs: OpenFlowError, rhs: OpenFlowError) -> Bool {
    switch (lhs, rhs) {
    case (.microphonePermissionDenied, .microphonePermissionDenied),
      (.accessibilityPermissionMissing, .accessibilityPermissionMissing),
      (.stylerTimedOut, .stylerTimedOut),
      (.targetAppLost, .targetAppLost):
      return true
    case (.modelDownloadFailed(let a), .modelDownloadFailed(let b)),
      (.modelLoadFailed(let a), .modelLoadFailed(let b)),
      (.sttFailed(let a), .sttFailed(let b)),
      (.stylerFailed(let a), .stylerFailed(let b)),
      (.audioCaptureFailed(let a), .audioCaptureFailed(let b)):
      return a.localizedDescription == b.localizedDescription
    default:
      return false
    }
  }
}
