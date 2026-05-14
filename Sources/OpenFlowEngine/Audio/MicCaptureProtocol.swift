import Foundation

public protocol MicCaptureProtocol: Sendable {
  /// Begin capturing mono Float32 samples at 16 kHz. Throws on permission/device failure.
  func start() async throws
  /// Stop capture and return all captured samples in order.
  func stop() async -> [Float]
  /// Per-buffer RMS samples emitted on the capture thread while `start()` is active.
  /// One value per native tap buffer (~10–20 Hz at typical hardware rates). Silent
  /// between stop and the next start.
  nonisolated var levels: AsyncStream<Float> { get }
}
