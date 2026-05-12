import Foundation
import OpenFlowEngine
import TinyAudio

struct ModelLoadState: Sendable, Equatable, ModelReadiness {
  var stt: ChannelStatus = .progress(.checking)
  var llm: ChannelStatus = .progress(.checking)

  var isReady: Bool { stt == .loaded && llm == .loaded }
}

enum ChannelStatus: Sendable, Equatable {
  /// Mirrors `TinyAudio.LoadProgress`: `.checking`, `.downloading`, `.loading`.
  case progress(TinyAudio.LoadProgress)
  case loaded
  case failed(message: String)
}

extension TinyAudio.LoadProgress: @retroactive Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.checking, .checking): return true
    case (.loading, .loading): return true
    case (.downloading(let l), .downloading(let r)): return l == r
    default: return false
    }
  }
}
