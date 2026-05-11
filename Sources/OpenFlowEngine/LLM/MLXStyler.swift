import Foundation
import TinyAudio

public actor MLXStyler: StylerProtocol {
  public struct Config: Sendable {
    public let maxTokens: Int
    public let temperature: Float
    public init(maxTokens: Int = 512, temperature: Float = 0.2) {
      self.maxTokens = maxTokens
      self.temperature = temperature
    }
  }

  private let config: Config
  private var session: TinyAudio.ChatSession?

  public init(config: Config = Config()) {
    self.config = config
  }

  /// Load the underlying TinyAudio chat session (downloads from HF on first run).
  /// Idempotent — second call is a no-op.
  public func warmUp(
    progress: (@Sendable (TinyAudio.LoadProgress) -> Void)? = nil
  ) async throws {
    if session != nil { return }
    do {
      session = try await TinyAudio.ChatSession.load(
        systemPrompt: StylingPrompt.system,
        generation: .init(maxTokens: config.maxTokens, temperature: config.temperature),
        progress: progress
      )
    } catch {
      throw OpenFlowError.modelLoadFailed(underlying: error)
    }
  }

  public nonisolated func style(_ raw: String) -> AsyncThrowingStream<StylerEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          try await self.warmUp()
          guard let session = await self.session else {
            continuation.finish(
              throwing: OpenFlowError.modelLoadFailed(
                underlying: NSError(
                  domain: "OpenFlow", code: -1,
                  userInfo: [
                    NSLocalizedDescriptionKey: "ChatSession unavailable after warmUp"
                  ])))
            return
          }
          let userText = StylingPrompt.userMessage(for: raw)
          for try await chunk in session.respond(to: userText) {
            if Task.isCancelled {
              continuation.finish()
              return
            }
            continuation.yield(.delta(chunk))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: OpenFlowError.stylerFailed(underlying: error))
        }
      }
    }
  }
}
