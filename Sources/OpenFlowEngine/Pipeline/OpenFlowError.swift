import Foundation

public enum OpenFlowError: Error, Sendable {
  case microphonePermissionDenied
  case accessibilityPermissionMissing
  case modelDownloadFailed(underlying: Error)
  case modelLoadFailed(underlying: Error)
  case sttFailed(underlying: Error)
  case stylerTimedOut
  case stylerFailed(underlying: Error)
  case targetAppLost
  case audioCaptureFailed(underlying: Error)
}

extension OpenFlowError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .microphonePermissionDenied: "Microphone access is required."
    case .accessibilityPermissionMissing: "Accessibility access is required."
    case .modelDownloadFailed(let e): "Couldn't download model. \(e.localizedDescription)"
    case .modelLoadFailed(let e): "Couldn't load model. \(e.localizedDescription)"
    case .sttFailed(let e): "Couldn't transcribe. \(e.localizedDescription)"
    case .stylerTimedOut: "Couldn't refine in time. Inserted the raw transcript."
    case .stylerFailed(let e): "Couldn't refine transcript. \(e.localizedDescription)"
    case .targetAppLost: "Couldn't reach the target app."
    case .audioCaptureFailed(let e): "Couldn't capture audio. \(e.localizedDescription)"
    }
  }
}
