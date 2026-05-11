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
    case .modelDownloadFailed(let e): "Model download failed: \(e.localizedDescription)"
    case .modelLoadFailed(let e): "Model load failed: \(e.localizedDescription)"
    case .sttFailed(let e): "Transcription failed: \(e.localizedDescription)"
    case .stylerTimedOut: "Styling timed out — inserted raw transcript."
    case .stylerFailed(let e): "Styling failed: \(e.localizedDescription)"
    case .targetAppLost: "Target app lost focus or quit."
    case .audioCaptureFailed(let e): "Audio capture failed: \(e.localizedDescription)"
    }
  }
}
