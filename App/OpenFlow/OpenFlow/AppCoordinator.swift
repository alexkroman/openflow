import AppKit
import AVFoundation
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
  private let onShowSetup: @MainActor () -> Void

  private let mic: PushToTalkCapture
  private let transcriber: TinyAudioTranscriber
  private let mlxStyler: MLXStyler
  private let safeStyler: SafeguardedStyler
  private let injector: KeyInjector
  private let session: DictationSession
  private var phaseObserver: Task<Void, Never>?
  private var wasRecording = false

  @Published private(set) var modelLoadState = ModelLoadState()

  init(
    overlay: OverlayWindowController,
    toast: ToastPresenter,
    onShowSetup: @MainActor @escaping () -> Void
  ) {
    self.overlay = overlay
    self.toast = toast
    self.onShowSetup = onShowSetup

    self.mic = PushToTalkCapture()
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

    Task { @MainActor in
      async let stt: Void = self.warmUp(.stt)
      async let llm: Void = self.warmUp(.llm)
      async let audio: Void = self.warmUpMicIfAuthorized()
      _ = await (stt, llm, audio)
    }

    KeyboardShortcuts.onKeyDown(for: .dictate) { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        guard self.modelLoadState.isReady else {
          // Surface the Setup window so the user sees download progress
          // directly instead of dismissing a toast that says "wait."
          self.onShowSetup()
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

  /// Pre-warm the mic only when permission is already granted. Calling
  /// `AVAudioEngine.prepare` on an unauthorized app pops macOS's mic prompt,
  /// which we don't want at launch — the Setup window's "Allow Microphone
  /// Access" button is the canonical entry point. First dictation after
  /// permission is granted pays a small warmup cost; subsequent presses
  /// don't.
  private func warmUpMicIfAuthorized() async {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
    await mic.warmUp()
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
    let label = DictateHotkey.label
    let isRecording: Bool = if case .recording = phase { true } else { false }
    if isRecording && !wasRecording {
      NSSound(named: "Pop")?.play()
    } else if !isRecording && wasRecording {
      NSSound(named: "Tink")?.play()
    }
    wasRecording = isRecording
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
