import Foundation
import Testing

@testable import OpenFlowEngine

@Suite("SafeguardedStyler")
struct MLXStylerSafeguardsTests {

  @Test("happy path streams through untouched")
  func happyPath() async throws {
    let inner = StubStyler(mode: .yieldChunks([.delta("Hello "), .delta("world.")]))
    let safe = SafeguardedStyler(inner: inner, timeoutSeconds: 5.0)
    var collected: [StylerEvent] = []
    for try await event in safe.style("hello world") {
      collected.append(event)
    }
    #expect(collected == [.delta("Hello "), .delta("world.")])
  }

  @Test("length guard: styled > 2x raw triggers fallback to raw")
  func lengthGuard() async throws {
    let raw = "hi"
    let huge = String(repeating: "x", count: 100)
    let inner = StubStyler(mode: .yieldChunks([.delta(huge)]))
    let safe = SafeguardedStyler(inner: inner, timeoutSeconds: 5.0)
    var events: [StylerEvent] = []
    for try await e in safe.style(raw) { events.append(e) }
    #expect(events.last == .replaceAll(raw))
  }

  @Test("empty guard: empty styled with >3-word raw falls back to raw")
  func emptyGuard() async throws {
    let raw = "this is more than three words"
    let inner = StubStyler(mode: .yieldChunks([.delta("")]))
    let safe = SafeguardedStyler(inner: inner, timeoutSeconds: 5.0)
    var events: [StylerEvent] = []
    for try await e in safe.style(raw) { events.append(e) }
    #expect(events.last == .replaceAll(raw))
  }

  @Test("empty guard does NOT trigger for short input")
  func emptyGuardShortInput() async throws {
    let raw = "uh"
    let inner = StubStyler(mode: .yieldChunks([.delta("")]))
    let safe = SafeguardedStyler(inner: inner, timeoutSeconds: 5.0)
    var events: [StylerEvent] = []
    for try await e in safe.style(raw) { events.append(e) }
    #expect(!events.contains(.replaceAll(raw)))
  }

  @Test("timeout: throws stylerTimedOut after raw fallback")
  func timeoutFallback() async throws {
    let inner = StubStyler(mode: .stallForever)
    let safe = SafeguardedStyler(inner: inner, timeoutSeconds: 0.1)
    var events: [StylerEvent] = []
    do {
      for try await e in safe.style("some words") { events.append(e) }
      Issue.record("expected throw")
    } catch let e as OpenFlowError {
      #expect(e == .stylerTimedOut)
    }
    #expect(events == [.replaceAll("some words")])
  }
}
