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

  @Published private(set) var modelLoadState: ModelLoadState = .idle

  private var latestSTTProgress: TinyAudio.LoadProgress = .checking
  private var latestLLMProgress: TinyAudio.LoadProgress = .checking
  private var sttReady = false
  private var llmReady = false
  private var sttError: Error?
  private var llmError: Error?

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

    // Kick off model downloads + audio engine warm-up in parallel. While
    // models are loading, the hotkey is gated below. AVAudioEngine warm-up
    // can race with model loading; it's small and independent.
    Task { @MainActor in
      modelLoadState = .loading(stt: .checking, llm: .checking)

      async let stt: Void = self.warmUpSTT()
      async let llm: Void = self.warmUpLLM()
      async let audio: Void = self.mic.warmUp()
      _ = await (stt, llm, audio)
    }

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

  // MARK: - Model load orchestration

  func retrySTTWarmUp() async {
    sttError = nil
    sttReady = false
    latestSTTProgress = .checking
    recomputeLoadState()
    await warmUpSTT()
  }

  func retryLLMWarmUp() async {
    llmError = nil
    llmReady = false
    latestLLMProgress = .checking
    recomputeLoadState()
    await warmUpLLM()
  }

  private func warmUpSTT() async {
    do {
      try await transcriber.warmUp { [weak self] p in
        Task { @MainActor in
          self?.latestSTTProgress = p
          self?.recomputeLoadState()
        }
      }
      sttReady = true
    } catch {
      sttError = error
    }
    recomputeLoadState()
  }

  private func warmUpLLM() async {
    do {
      try await mlxStyler.warmUp { [weak self] p in
        Task { @MainActor in
          self?.latestLLMProgress = p
          self?.recomputeLoadState()
        }
      }
      llmReady = true
    } catch {
      llmError = error
    }
    recomputeLoadState()
  }

  private func recomputeLoadState() {
    if sttError != nil || llmError != nil {
      modelLoadState = .failed(stt: sttError, llm: llmError)
      return
    }
    if sttReady && llmReady {
      modelLoadState = .ready
      return
    }
    modelLoadState = .loading(stt: latestSTTProgress, llm: latestLLMProgress)
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
