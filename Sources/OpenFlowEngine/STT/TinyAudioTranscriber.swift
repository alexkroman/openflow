import Foundation
import TinyAudio

public actor TinyAudioTranscriber: TranscriberProtocol {
  private var transcriber: Transcriber?

  public init() {}

  /// Loads model weights. Call once before first use (e.g. in app warm-up or lazily on first dictation).
  /// First call may trigger an HF download via TinyAudio; subsequent calls hit the local cache.
  public func warmUp(
    progress: (@Sendable (TinyAudio.LoadProgress) -> Void)? = nil
  ) async throws {
    if transcriber == nil {
      transcriber = try await Transcriber.load(progress: progress)
    }
  }

  public nonisolated func transcribeStream(samples: [Float], sampleRate: Int)
    -> AsyncThrowingStream<String, Error>
  {
    AsyncThrowingStream { continuation in
      Task {
        do {
          let t = try await self.ensureLoaded()
          let transcript = try await t.transcribe(.samples(samples, sampleRate: Double(sampleRate)))
          continuation.yield(transcript)
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  private func ensureLoaded() async throws -> Transcriber {
    if let t = transcriber { return t }
    let t = try await Transcriber.load()
    transcriber = t
    return t
  }
}
