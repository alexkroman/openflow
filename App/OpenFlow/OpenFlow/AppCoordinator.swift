import AppKit
import Foundation
import KeyboardShortcuts
import OpenFlowEngine
import TinyAudio

@MainActor
final class AppCoordinator: ObservableObject {
  private static let stylingEnabled = true

  private let overlay: OverlayWindowController
  private let toast: ToastPresenter

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
    toast: ToastPresenter
  ) {
    self.overlay = overlay
    self.toast = toast

    self.mic = MicCapture()
    self.transcriber = TinyAudioTranscriber()
    self.mlxStyler = MLXStyler()
    self.safeStyler = SafeguardedStyler(inner: mlxStyler)
    self.injector = KeyInjector()
    self.session = DictationSession(
      mic: mic,
      transcriber: transcriber,
      styler: safeStyler,
      injector: injector,
      stylingEnabled: Self.stylingEnabled
    )
  }

  func start() {
    // Note: no initial overlay render. The overlay pill stays hidden until
    // the wizard reports the app is fully configured (WizardController calls
    // `showOverlay()` on entering `.hotkey`).
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

  /// Renders the overlay pill in idle state. Called by the wizard once the
  /// app is fully configured; before that, no overlay is shown.
  func showOverlay() {
    render(.idle)
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

  private var wasRecording = false
  private let recordStartSound = NSSound(named: "Pop")
  private let recordStopSound = NSSound(named: "Bottle")

  private func render(_ phase: PipelinePhase) {
    let isRecording: Bool
    if case .recording = phase { isRecording = true } else { isRecording = false }
    if isRecording && !wasRecording {
      recordStartSound?.play()
    } else if !isRecording && wasRecording {
      recordStopSound?.play()
    }
    wasRecording = isRecording

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
