@preconcurrency import AVFoundation
import Foundation
import os

public actor MicCapture: MicCaptureProtocol {
  // Subsystem/category make these lines findable via:
  //   log show --predicate 'subsystem == "dev.alex.OpenFlow"' --last 1h
  // Stderr is unreachable for .app bundles launched via Finder/LaunchServices,
  // so go through the unified logging system instead.
  private static let logger = Logger(subsystem: "dev.alex.OpenFlow", category: "MicCapture")

  public nonisolated let levels: AsyncStream<Float>
  private nonisolated let levelsContinuation: AsyncStream<Float>.Continuation

  private let engine = AVAudioEngine()
  private var rawSamples: [Float] = []
  private var inputSampleRate: Double = 0
  private var cachedInputFormat: AVAudioFormat?
  private var prepared = false
  private let targetSampleRate: Double = 16_000

  private final class Counters: @unchecked Sendable {
    var tapFired = 0
  }
  private let counters = Counters()
  private var appendCalls = 0

  public init() {
    let (stream, continuation) = AsyncStream<Float>.makeStream()
    self.levels = stream
    self.levelsContinuation = continuation
  }

  /// Pre-allocate AVAudioEngine resources and cache the input format so the
  /// first `start()` doesn't pay first-time hardware-route discovery and
  /// engine-graph preparation. Does NOT begin capture — no mic indicator.
  /// Safe to call multiple times; failures here just leave start() to do
  /// the work lazily.
  public func warmUp() {
    if prepared { return }
    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    self.cachedInputFormat = inputFormat
    self.inputSampleRate = inputFormat.sampleRate
    engine.prepare()
    prepared = true
    Self.logger.info(
      "warmUp sampleRate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount)")
  }

  public func start() async throws {
    rawSamples.removeAll(keepingCapacity: true)
    let input = engine.inputNode
    let inputFormat = cachedInputFormat ?? input.outputFormat(forBus: 0)
    self.cachedInputFormat = inputFormat
    self.inputSampleRate = inputFormat.sampleRate

    Self.logger.info(
      """
      start sampleRate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount) \
      interleaved=\(inputFormat.isInterleaved)
      """)

    // The tap callback runs on a real-time audio thread (not the actor).
    // Ship a Sendable [Float] chunk to the actor via Task.
    //
    // AVAudioInputNode taps must use the node's native format on macOS — asking
    // for a different format throws "Failed to create tap due to format mismatch."
    // So we capture in native format and do one-shot SRC at stop() time.
    // Per-buffer SRC with endOfStream after each call drops most output frames
    // (the polyphase filter never accumulates enough state).
    let counters = self.counters
    let levelsContinuation = self.levelsContinuation
    input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
      counters.tapFired += 1
      // Take channel 0 as mono (input may be stereo on built-in/USB mics).
      guard let chan = buffer.floatChannelData?[0] else { return }
      let ptr = UnsafeBufferPointer(start: chan, count: Int(buffer.frameLength))
      levelsContinuation.yield(Self.rms(ptr))
      let chunk = Array(ptr)
      Task { [weak self] in await self?.append(chunk) }
    }

    if !prepared {
      engine.prepare()
      prepared = true
    }
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      Self.logger.error("engine.start failed: \(error.localizedDescription)")
      throw error
    }
  }

  public func stop() async -> [Float] {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    let raw = rawSamples
    rawSamples.removeAll(keepingCapacity: false)

    let result = Self.downsample(raw, fromRate: inputSampleRate, toRate: targetSampleRate)

    let durationMs = Int((Double(result.count) / targetSampleRate) * 1000)
    let peak = result.map { abs($0) }.max() ?? 0
    let rms = result.withUnsafeBufferPointer(Self.rms)
    Self.logger.info(
      """
      stop rawSamples=\(raw.count) outSamples=\(result.count) durationMs=\(durationMs) \
      peak=\(peak) rms=\(rms) tap=\(self.counters.tapFired) appended=\(self.appendCalls)
      """)
    counters.tapFired = 0
    appendCalls = 0
    return result
  }

  private func append(_ chunk: [Float]) {
    rawSamples.append(contentsOf: chunk)
    appendCalls += 1
  }

  private static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
    if samples.isEmpty { return 0 }
    var sumSq: Float = 0
    for s in samples { sumSq += s * s }
    return (sumSq / Float(samples.count)).squareRoot()
  }

  private static func downsample(_ raw: [Float], fromRate: Double, toRate: Double) -> [Float] {
    if raw.isEmpty { return [] }
    if abs(fromRate - toRate) < 1 { return raw }
    guard
      let inFmt = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: fromRate,
        channels: 1, interleaved: false),
      let outFmt = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: toRate,
        channels: 1, interleaved: false),
      let conv = AVAudioConverter(from: inFmt, to: outFmt),
      let inBuf = AVAudioPCMBuffer(
        pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(raw.count)),
      let outBuf = AVAudioPCMBuffer(
        pcmFormat: outFmt,
        frameCapacity: AVAudioFrameCount(Double(raw.count) * toRate / fromRate + 1024))
    else {
      logger.error("downsample setup failed")
      return []
    }
    inBuf.frameLength = AVAudioFrameCount(raw.count)
    raw.withUnsafeBufferPointer { src in
      inBuf.floatChannelData![0].update(from: src.baseAddress!, count: raw.count)
    }

    var error: NSError?
    nonisolated(unsafe) var fed = false
    conv.convert(to: outBuf, error: &error) { _, status in
      if fed {
        status.pointee = .endOfStream
        return nil
      }
      fed = true
      status.pointee = .haveData
      return inBuf
    }
    if let error {
      logger.error("downsample convert error: \(error.localizedDescription)")
      return []
    }
    let frames = Int(outBuf.frameLength)
    guard frames > 0, let chan = outBuf.floatChannelData?[0] else { return [] }
    return Array(UnsafeBufferPointer(start: chan, count: frames))
  }
}
