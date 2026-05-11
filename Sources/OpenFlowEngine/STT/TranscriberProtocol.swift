import Foundation

public protocol TranscriberProtocol: Sendable {
  /// Transcribe captured audio samples (mono Float32, 16 kHz) into text token deltas.
  /// Each yielded String is an *additive* delta — concatenate them in order to form the full transcript.
  func transcribeStream(samples: [Float], sampleRate: Int) -> AsyncThrowingStream<String, Error>
}
