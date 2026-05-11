import Testing

@testable import OpenFlowEngine

@Suite("PipelinePhase.isTerminal")
struct PipelinePhaseTests {
  @Test("idle is terminal")
  func idleIsTerminal() {
    #expect(PipelinePhase.idle.isTerminal)
  }

  @Test("cancelled is terminal")
  func cancelledIsTerminal() {
    #expect(PipelinePhase.cancelled.isTerminal)
  }

  @Test("failed is terminal regardless of underlying error")
  func failedIsTerminal() {
    #expect(PipelinePhase.failed(.stylerTimedOut).isTerminal)
    #expect(PipelinePhase.failed(.targetAppLost).isTerminal)
  }

  @Test("active phases are not terminal")
  func activePhasesAreNotTerminal() {
    #expect(!PipelinePhase.recording.isTerminal)
    #expect(!PipelinePhase.transcribing(rawSoFar: "").isTerminal)
    #expect(!PipelinePhase.styling(styledSoFar: "").isTerminal)
    #expect(!PipelinePhase.injecting(text: "anything").isTerminal)
  }
}
