import Foundation
import Testing

@testable import OpenFlowEngine

@Suite("DictationSession")
struct DictationSessionTests {

  @Test("press from idle transitions to recording")
  func pressIdleToRecording() async throws {
    let mic = StubMicCapture()
    let stt = StubTranscriber(mode: .yieldChunks(["hello"]))
    let styler = StubStyler(mode: .yieldChunks([.delta("hello.")]))
    let injector = StubInjector()
    let session = DictationSession(
      mic: mic, transcriber: stt, styler: styler, injector: injector,
      stylingEnabled: true
    )

    await session.press()

    #expect(await session.phase == .recording)
    #expect(await mic.startCalls == 1)
  }
}

extension DictationSessionTests {
  @Test("happy path: press → release → transcribe → style → inject")
  func happyPath() async throws {
    let mic = StubMicCapture()
    let stt = StubTranscriber(mode: .yieldChunks(["hello ", "world"]))
    let styler = StubStyler(mode: .yieldChunks([.delta("Hello "), .delta("world.")]))
    let injector = StubInjector()
    let session = DictationSession(
      mic: mic, transcriber: stt, styler: styler, injector: injector,
      stylingEnabled: true
    )

    await session.press()
    await session.release()
    await session.waitForIdle()

    #expect(await session.phase == .idle)
    #expect(await injector.inserted == ["Hello world."])
  }

  @Test("styling disabled: raw transcript inserted")
  func stylingDisabled() async throws {
    let mic = StubMicCapture()
    let stt = StubTranscriber(mode: .yieldChunks(["hello world"]))
    let styler = StubStyler(mode: .yieldChunks([.delta("SHOULD NOT RUN")]))
    let injector = StubInjector()
    let session = DictationSession(
      mic: mic, transcriber: stt, styler: styler, injector: injector,
      stylingEnabled: false
    )

    await session.press()
    await session.release()
    await session.waitForIdle()

    #expect(await injector.inserted == ["hello world"])
  }
}

extension DictationSessionTests {
  @Test("cancel during recording returns to idle, no insert")
  func cancelDuringRecording() async throws {
    let mic = StubMicCapture()
    let stt = StubTranscriber(mode: .yieldChunks(["x"]))
    let styler = StubStyler(mode: .yieldChunks([.delta("X")]))
    let injector = StubInjector()
    let session = DictationSession(
      mic: mic, transcriber: stt, styler: styler, injector: injector,
      stylingEnabled: true
    )

    await session.press()
    await session.cancel()
    await session.waitForIdle()

    #expect(await session.phase == .cancelled)
    #expect(await injector.inserted.isEmpty)
    #expect(await mic.stopCalls == 1)  // mic stopped on cancel
  }

  @Test("STT failure surfaces .failed and skips injection")
  func sttFailure() async throws {
    struct Boom: Error {}
    let mic = StubMicCapture()
    let stt = StubTranscriber(mode: .throwError(Boom()))
    let styler = StubStyler(mode: .yieldChunks([.delta("never")]))
    let injector = StubInjector()
    let session = DictationSession(
      mic: mic, transcriber: stt, styler: styler, injector: injector,
      stylingEnabled: true
    )

    await session.press()
    await session.release()
    await session.waitForIdle()

    if case .failed(.sttFailed) = await session.phase {
      // ok
    } else {
      Issue.record("expected .failed(.sttFailed), got \(await session.phase)")
    }
    #expect(await injector.inserted.isEmpty)
  }
}

extension DictationSessionTests {
  @Test("cancel during transcribing waits for pipeline and lands in .cancelled")
  func cancelDuringTranscribing() async throws {
    let mic = StubMicCapture()
    // Stall STT to give us time to cancel
    let stt = StubTranscriber(mode: .stallForever)
    let styler = StubStyler(mode: .yieldChunks([.delta("x")]))
    let injector = StubInjector()
    let session = DictationSession(
      mic: mic, transcriber: stt, styler: styler, injector: injector,
      stylingEnabled: true
    )

    await session.press()
    await session.release()
    // give the pipeline task a moment to enter the for-await
    try await Task.sleep(nanoseconds: 20_000_000)
    await session.cancel()
    #expect(await session.phase == .cancelled)
    #expect(await injector.inserted.isEmpty)
  }
}

extension DictationSessionTests {
  @Test("press after .failed succeeds (state recovers)")
  func pressAfterFailure() async throws {
    struct Boom: Error {}
    let mic = StubMicCapture()
    let stt = StubTranscriber(mode: .throwError(Boom()))
    let styler = StubStyler(mode: .yieldChunks([.delta("unused")]))
    let injector = StubInjector()
    let session = DictationSession(
      mic: mic, transcriber: stt, styler: styler, injector: injector,
      stylingEnabled: true
    )

    // First run: fail in STT
    await session.press()
    await session.release()
    await session.waitForIdle()
    if case .failed = await session.phase {
    } else {
      Issue.record("expected .failed after STT throws")
    }

    // Second run: should be allowed; we'll use a fresh transcriber stub via separate session
    // But the bug is the GUARD, not the stubs: just verify press() now changes phase.
    await session.press()
    #expect(await session.phase == .recording)
  }
}

extension DictationSessionTests {
  @Test("auto-release after maxRecordingSeconds")
  func autoRelease() async throws {
    let mic = StubMicCapture()
    let stt = StubTranscriber(mode: .yieldChunks(["timed out text"]))
    let styler = StubStyler(mode: .yieldChunks([.delta("Timed out text.")]))
    let injector = StubInjector()
    let session = DictationSession(
      mic: mic, transcriber: stt, styler: styler, injector: injector,
      stylingEnabled: true,
      maxRecordingSeconds: 0.05
    )

    await session.press()
    await session.waitForIdle()  // auto-release fires release() within 50ms

    #expect(await injector.inserted == ["Timed out text."])
  }
}
