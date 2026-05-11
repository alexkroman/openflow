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

  /// Loads the underlying TinyAudio chat session (downloads from HF on first run).
  @discardableResult
  public func warmUp(
    progress: (@Sendable (TinyAudio.LoadProgress) -> Void)? = nil
  ) async throws -> TinyAudio.ChatSession {
    if let session { return session }
    do {
      let new = try await TinyAudio.ChatSession.load(
        systemPrompt: StylingPrompt.system,
        generation: .init(maxTokens: config.maxTokens, temperature: config.temperature),
        progress: progress
      )
      session = new
      return new
    } catch {
      throw OpenFlowError.modelLoadFailed(underlying: error)
    }
  }

  public nonisolated func style(_ raw: String) -> AsyncThrowingStream<StylerEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          let session = try await self.warmUp()
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
