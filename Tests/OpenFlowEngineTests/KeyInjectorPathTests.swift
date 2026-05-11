import Testing

@testable import OpenFlowEngine

@Suite("InjectionPath.choose")
struct KeyInjectorPathTests {
  @Test("short text uses keystrokes")
  func short() {
    #expect(InjectionPath.choose(for: "hi", longTextThreshold: 500) == .typeKeystrokes)
  }
  @Test("text at threshold still keystrokes")
  func atThreshold() {
    let s = String(repeating: "x", count: 500)
    #expect(InjectionPath.choose(for: s, longTextThreshold: 500) == .typeKeystrokes)
  }
  @Test("text over threshold uses paste")
  func overThreshold() {
    let s = String(repeating: "x", count: 501)
    #expect(InjectionPath.choose(for: s, longTextThreshold: 500) == .clipboardPaste)
  }
}
