import Foundation

/// Wraps any `StylerProtocol` with timeout, length-guard, and empty-guard safeguards.
///
/// - Timeout: if the inner stream doesn't finish within `timeoutSeconds`, cancel the inner
///   work, emit `.replaceAll(raw)`, then throw `OpenFlowError.stylerTimedOut`.
/// - Length guard: after streaming, if accumulated styled text length > `lengthMultiple * raw.count`
///   (floor 8), emit `.replaceAll(raw)` and finish normally.
/// - Empty guard: after streaming, if styled (trimmed) is empty AND raw has > `emptyGuardMinWords`
///   words, emit `.replaceAll(raw)` and finish normally.
public actor SafeguardedStyler: StylerProtocol {

  private let inner: StylerProtocol
  private let timeoutSeconds: Double
  private let lengthMultiple: Double
  private let emptyGuardMinWords: Int

  public init(
    inner: StylerProtocol,
    timeoutSeconds: Double = 8.0,
    lengthMultiple: Double = 2.0,
    emptyGuardMinWords: Int = 3
  ) {
    self.inner = inner
    self.timeoutSeconds = timeoutSeconds
    self.lengthMultiple = lengthMultiple
    self.emptyGuardMinWords = emptyGuardMinWords
  }

  public nonisolated func style(_ raw: String) -> AsyncThrowingStream<StylerEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        let timeout = self.timeoutSeconds
        let lenMul = self.lengthMultiple
        let minWords = self.emptyGuardMinWords
        let inner = self.inner

        await withTaskGroup(of: Outcome.self) { group in
          group.addTask {
            var styled = ""
            do {
              for try await event in inner.style(raw) {
                if Task.isCancelled { return .cancelled }
                if case .delta(let chunk) = event {
                  styled += chunk
                }
                continuation.yield(event)
              }
              return .completed(styled: styled)
            } catch {
              return .innerFailed(error)
            }
          }
          group.addTask {
            try? await Task.sleep(for: .seconds(timeout))
            return .timedOut
          }

          let outcome = await group.next() ?? .cancelled
          group.cancelAll()
          _ = await group.next()  // drain second result

          switch outcome {
          case .completed(let styled):
            let cap = max(8, Int(Double(raw.count) * lenMul))
            if styled.count > cap {
              continuation.yield(.replaceAll(raw))
              continuation.finish()
              return
            }
            let trimmed = styled.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawWords = raw.split(whereSeparator: { $0.isWhitespace }).count
            if trimmed.isEmpty && rawWords > minWords {
              continuation.yield(.replaceAll(raw))
              continuation.finish()
              return
            }
            continuation.finish()
          case .innerFailed(let error):
            continuation.finish(throwing: error)
          case .timedOut:
            continuation.yield(.replaceAll(raw))
            continuation.finish(throwing: OpenFlowError.stylerTimedOut)
          case .cancelled:
            continuation.finish()
          }
        }
      }
    }
  }

  private enum Outcome: Sendable {
    case completed(styled: String)
    case innerFailed(any Error & Sendable)
    case timedOut
    case cancelled
  }
}
