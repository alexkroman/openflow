import AppKit
import Foundation
import KeyboardShortcuts
import OpenFlowEngine

@MainActor
final class AppCoordinator {
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

    // Pre-warm models + audio engine in the background so the first dictation
    // doesn't pay cold-start cost: TinyAudio's weight load, MLX kernel JIT +
    // weight load, the styler's KV-cache primer turn, and AVAudioEngine
    // hardware-route discovery + prepare(). Together that's multiple seconds
    // on a cold launch. Errors are swallowed so a warmup failure doesn't block
    // startup; the same paths run lazily on first use as a fallback.
    let transcriber = self.transcriber
    let styler = self.mlxStyler
    let mic = self.mic
    Task.detached(priority: .utility) {
      async let stt: Void = {
        try? await transcriber.warmUp()
      }()
      async let llm: Void = {
        try? await styler.warmUp()
      }()
      async let audio: Void = {
        await mic.warmUp()
      }()
      _ = await (stt, llm, audio)
    }

    KeyboardShortcuts.onKeyDown(for: .dictate) { [weak self] in
      Task { @MainActor in await self?.session.press() }
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
