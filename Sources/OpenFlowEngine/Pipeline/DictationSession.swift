import AppKit
import Foundation

public actor DictationSession {
  public private(set) var phase: PipelinePhase = .idle
  /// Phase-change stream. Yields the current phase plus every subsequent
  /// transition. Single-consumer: the production app's AppCoordinator iterates
  /// it for rendering, and tests' `waitForIdle` iterates it to await terminal
  /// states. Don't subscribe from two places on the same session.
  public nonisolated let phases: AsyncStream<PipelinePhase>

  private let phaseContinuation: AsyncStream<PipelinePhase>.Continuation
  private let mic: MicCaptureProtocol
  private let transcriber: TranscriberProtocol
  private let styler: StylerProtocol
  private let injector: InjectorProtocol
  private let stylingEnabled: Bool
  private let maxRecordingSeconds: Double

  private var pipelineTask: Task<Void, Never>?

  public init(
    mic: MicCaptureProtocol,
    transcriber: TranscriberProtocol,
    styler: StylerProtocol,
    injector: InjectorProtocol,
    stylingEnabled: Bool,
    maxRecordingSeconds: Double = 60.0
  ) {
    let (stream, continuation) = AsyncStream.makeStream(of: PipelinePhase.self)
    self.phases = stream
    self.phaseContinuation = continuation
    self.mic = mic
    self.transcriber = transcriber
    self.styler = styler
    self.injector = injector
    self.stylingEnabled = stylingEnabled
    self.maxRecordingSeconds = maxRecordingSeconds
  }

  public func press() async {
    guard phase.isTerminal else { return }
    do {
      // Capture the frontmost app concurrently with mic startup. The phase
      // still flips to .recording only after mic.start succeeds, so the UI
      // never lies about whether audio is being captured.
      async let captured = captureFrontmostApp()
      try await mic.start()
      await injector.setTargetApp(captured)
      setPhase(.recording)
      let timeout = maxRecordingSeconds
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(timeout))
        guard let self else { return }
        if await self.phase == .recording {
          await self.release()
        }
      }
    } catch {
      setPhase(.failed(.audioCaptureFailed(underlying: error)))
    }
  }

  public func cancel() async {
    switch phase {
    case .idle, .failed, .cancelled:
      return
    case .recording:
      _ = await mic.stop()
    default:
      pipelineTask?.cancel()
      await pipelineTask?.value  // wait for the task to actually finish before transitioning
    }
    pipelineTask = nil
    setPhase(.cancelled)
  }

  public func release() async {
    guard phase == .recording else { return }
    let samples = await mic.stop()
    setPhase(.transcribing(rawSoFar: ""))
    pipelineTask = Task { [weak self] in
      await self?.runTranscribeStyleInject(samples: samples)
    }
  }

  /// Test helper — completes when phase is terminal (idle/failed/cancelled).
  public func waitForIdle() async {
    if phase.isTerminal { return }
    for await p in phases where p.isTerminal { return }
  }

  private func runTranscribeStyleInject(samples: [Float]) async {
    var raw = ""
    do {
      for try await delta in transcriber.transcribeStream(samples: samples, sampleRate: 16_000) {
        if Task.isCancelled { return }
        raw += delta
        setPhase(.transcribing(rawSoFar: raw))
      }
    } catch {
      setPhase(.failed(.sttFailed(underlying: error)))
      return
    }

    if Task.isCancelled { return }

    if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      setPhase(.idle)
      return
    }

    let finalText: String
    if stylingEnabled {
      setPhase(.styling(styledSoFar: ""))
      var styled = ""
      do {
        for try await event in styler.style(raw) {
          if Task.isCancelled { return }
          switch event {
          case .delta(let chunk):
            styled += chunk
          case .replaceAll(let text):
            styled = text
          }
          setPhase(.styling(styledSoFar: styled))
        }
      } catch let err as OpenFlowError where err == .stylerTimedOut {
        // Fallback already streamed via marker+raw; styled == raw. Continue.
      } catch {
        setPhase(.failed(.stylerFailed(underlying: error)))
        return
      }
      if Task.isCancelled { return }
      finalText = styled
    } else {
      finalText = raw
    }

    if Task.isCancelled { return }
    DictationLog.append(raw: raw, polished: finalText)
    setPhase(.injecting(text: finalText))
    do {
      try await injector.insert(finalText)
    } catch {
      setPhase(.failed(.targetAppLost))
      return
    }

    setPhase(.idle)
  }

  private func captureFrontmostApp() async -> NSRunningApplication? {
    let captured = await MainActor.run { () -> CapturedFocus? in
      FocusCapture.captureFrontmost()
    }
    guard let captured else { return nil }
    return FocusCapture.runningApp(for: captured)
  }

  private func setPhase(_ newPhase: PipelinePhase) {
    phase = newPhase
    phaseContinuation.yield(newPhase)
  }
}
