import Foundation
import TinyAudio

/// Coarse-grained model load lifecycle surfaced from `AppCoordinator` to the
/// UI. `loading` carries the per-model progress so SetupView can render
/// two progress rows.
public enum ModelLoadState: Sendable {
  case idle
  case loading(stt: TinyAudio.LoadProgress, llm: TinyAudio.LoadProgress)
  case ready
  case failed(stt: Error?, llm: Error?)

  public var isReady: Bool {
    if case .ready = self { return true } else { return false }
  }
}
