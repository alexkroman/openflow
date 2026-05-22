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
  private var levelsObserver: Task<Void, Never>?
  private var pendingRelease: Task<Void, Never>?
  private static let releaseDebounce: Duration = .milliseconds(130)

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
        // Carbon's kEventHotKeyReleased fires spuriously while the user is
        // still holding (focus jitter, HID glitches). A keyDown inside the
        // debounce window means the prior keyUp was phantom — keep recording.
        if let pending = self.pendingRelease {
          pending.cancel()
          self.pendingRelease = nil
          return
        }
        guard self.modelLoadState.isReady else {
          self.toast.show("Still preparing models — please wait")
          return
        }
        await self.session.press()
      }
    }
    KeyboardShortcuts.onKeyUp(for: .dictate) { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        self.pendingRelease?.cancel()
        self.pendingRelease = Task { @MainActor [weak self] in
          try? await Task.sleep(for: Self.releaseDebounce)
          guard let self, !Task.isCancelled else { return }
          self.pendingRelease = nil
          await self.session.release()
        }
      }
    }

    let phases = session.phases
    phaseObserver = Task { @MainActor [weak self] in
      for await phase in phases {
        guard let self else { return }
        if Task.isCancelled { return }
        self.render(phase)
      }
    }

    let levels = mic.levels
    levelsObserver = Task { @MainActor [weak self] in
      for await level in levels {
        guard let self else { return }
        if Task.isCancelled { return }
        self.overlay.pushLevel(level)
      }
    }
  }

  /// Renders the overlay pill in idle state. Called by the wizard once the
  /// app is fully configured; before that, no overlay is shown.
  func showOverlay() {
    overlay.show(state: .idle)
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
  private let recordStartSound = NSSound(named: "Purr")
  private let recordStopSound = NSSound(named: "Purr")

  private func render(_ phase: PipelinePhase) {
    let isRecording: Bool
    if case .recording = phase { isRecording = true } else { isRecording = false }
    if isRecording && !wasRecording {
      recordStartSound?.play()
    } else if !isRecording && wasRecording {
      recordStopSound?.play()
    }
    wasRecording = isRecording

    let ui: OverlayUIState
    switch phase {
    case .idle, .cancelled, .injecting:
      ui = .idle
    case .recording:
      ui = .recording
    case .transcribing, .styling:
      ui = .processing
    case .failed(let err):
      ui = .idle
      toast.show(err.errorDescription ?? "Error")
    }
    overlay.show(state: ui)
  }
}
