import Testing

@testable import OpenFlowEngine

@Suite("KeyInjector.withTrailingSpace")
struct KeyInjectorTrailingSpaceTests {
  @Test("appends space when text does not end in whitespace")
  func appendsSpace() {
    #expect(KeyInjector.withTrailingSpace("hello") == "hello ")
  }

  @Test("leaves text unchanged when it already ends in a space")
  func leavesSpaceAlone() {
    #expect(KeyInjector.withTrailingSpace("hello ") == "hello ")
  }

  @Test("leaves text unchanged when it ends in a newline")
  func leavesNewlineAlone() {
    #expect(KeyInjector.withTrailingSpace("hello\n") == "hello\n")
  }

  @Test("leaves text unchanged when it ends in a tab")
  func leavesTabAlone() {
    #expect(KeyInjector.withTrailingSpace("hello\t") == "hello\t")
  }

  @Test("appends space to single-character text")
  func appendsToSingleChar() {
    #expect(KeyInjector.withTrailingSpace("x") == "x ")
  }
}
