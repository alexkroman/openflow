import Testing
import TinyAudio

@testable import OpenFlowEngine

@Suite("ModelLoadState")
struct ModelLoadStateTests {
  @Test("idle is not ready")
  func idleNotReady() {
    #expect(ModelLoadState.idle.isReady == false)
  }

  @Test("ready is ready")
  func readyIsReady() {
    #expect(ModelLoadState.ready.isReady == true)
  }

  @Test("loading is not ready")
  func loadingNotReady() {
    let s = ModelLoadState.loading(stt: .checking, llm: .checking)
    #expect(s.isReady == false)
  }
}
