import Foundation

public protocol MicCaptureProtocol: Sendable {
  /// Begin capturing mono Float32 samples at 16 kHz. Throws on permission/device failure.
  func start() async throws
  /// Stop capture and return all captured samples in order.
  func stop() async -> [Float]
}
