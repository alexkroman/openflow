import AppKit
import Foundation
import KeyboardShortcuts
import OpenFlowEngine
import TinyAudio

@MainActor
final class AppCoordinator: ObservableObject {
  private static let stylingEnabled = true
  private static let longTextThreshold = 500

  private let overlay: OverlayWindowController
  private let toast: ToastPresenter
  private let statusItem: StatusItemController

  private let mic: MicCapture
  private let transcriber: TinyAudioTranscriber
  private let mlxStyler: MLXStyler
  private let safeStyler: SafeguardedStyler
  private let injector: KeyInjector
  private let session: DictationSession
  private var phaseObserver: Task<Void, Never>?

  @Published private(set) var modelLoadState = ModelLoadState()

  init(
    overlay: OverlayWindowController,
    toast: ToastPresenter,
    statusItem: StatusItemController
  ) {
    self.overlay = overlay
    self.toast = toast
    self.statusItem = statusItem

    self.mic = MicCapture()
    self.transcriber = TinyAudioTranscriber()
    self.mlxStyler = MLXStyler()
    self.safeStyler = SafeguardedStyler(inner: mlxStyler)
    self.injector = KeyInjector(config: .init(longTextThreshold: Self.longTextThreshold))
    self.session = DictationSession(
      mic: mic,
      transcriber: transcriber,
      styler: safeStyler,
      injector: injector,
      stylingEnabled: Self.stylingEnabled
    )
  }

  func start() {
    render(.idle)

    beginModelLoad()

    KeyboardShortcuts.onKeyDown(for: .dictate) { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        guard self.modelLoadState.isReady else {
          self.toast.show("Still preparing models — please wait")
          return
        }
        await self.session.press()
      }
    }
    KeyboardShortcuts.onKeyUp(for: .dictate) { [weak self] in
      Task { @MainActor in await self?.session.release() }
    }

    let phases = session.phases
    phaseObserver = Task { @MainActor [weak self] in
      for await phase in phases {
        guard let self else { return }
        if Task.isCancelled { return }
        self.render(phase)
      }
    }
  }

  /// Kicks off STT / LLM / audio warm-up. Idempotent in practice — each
  /// warm-up bails out fast if the model is already loaded.
  func beginModelLoad() {
    Task { @MainActor in
      async let stt: Void = self.warmUp(.stt)
      async let llm: Void = self.warmUp(.llm)
      async let audio: Void = self.mic.warmUp()
      _ = await (stt, llm, audio)
    }
  }

  // MARK: - Model load orchestration

  func retrySTTWarmUp() async { await retry(.stt) }
  func retryLLMWarmUp() async { await retry(.llm) }

  private enum Model { case stt, llm }

  private func warmUp(_ model: Model) async {
    let onProgress: @Sendable (TinyAudio.LoadProgress) -> Void = { [weak self] progress in
      // Whole-percent buckets keep Equatable de-dup quiet during downloads.
      let bucketed: TinyAudio.LoadProgress
      if case .downloading(let f) = progress {
        bucketed = .downloading(fractionCompleted: (f * 100).rounded(.down) / 100)
      } else {
        bucketed = progress
      }
      Task { @MainActor in self?.update(model, status: .progress(bucketed)) }
    }
    do {
      switch model {
      case .stt: try await transcriber.warmUp(progress: onProgress)
      case .llm: try await mlxStyler.warmUp(progress: onProgress)
      }
      update(model, status: .loaded)
    } catch {
      update(model, status: .failed(message: error.localizedDescription))
    }
  }

  private func retry(_ model: Model) async {
    update(model, status: .progress(.checking))
    await warmUp(model)
  }

  private func update(_ model: Model, status: ChannelStatus) {
    switch model {
    case .stt:
      guard modelLoadState.stt != status else { return }
      modelLoadState.stt = status
    case .llm:
      guard modelLoadState.llm != status else { return }
      modelLoadState.llm = status
    }
  }

  // MARK: - Dictation render

  private func render(_ phase: PipelinePhase) {
    statusItem.update(phase: phase)
    let label = DictateHotkey.label
    switch phase {
    case .idle, .injecting, .cancelled:
      overlay.show(state: .init(phase: .idle, hotkeyLabel: label))
    case .recording:
      overlay.show(state: .init(phase: .recording, hotkeyLabel: label))
    case .transcribing:
      overlay.show(state: .init(phase: .transcribing, hotkeyLabel: label))
    case .styling:
      overlay.show(state: .init(phase: .styling, hotkeyLabel: label))
    case .failed(let err):
      overlay.show(state: .init(phase: .idle, hotkeyLabel: label))
      toast.show(err.errorDescription ?? "Error")
    }
  }
}
