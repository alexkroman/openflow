import Foundation

public protocol MicCaptureProtocol: Sendable {
  /// Begin capturing mono Float32 samples at 16 kHz. Throws on permission/device failure.
  func start() async throws
  /// Stop capture and return all captured samples in order.
  /// Throws if the captured audio cannot be resampled to 16 kHz mono Float32.
  func stop() async throws -> [Float]
}
