import SwiftUI

enum OverlayUIState: Equatable {
  case idle
  case recording
  case processing
}

/// Which hotkey started the current (or most recent) recording session.
/// Drives the stop-hint copy on the recording card.
enum RecordingMode: Equatable {
  case pushToTalk
  case handsFree
}

struct OverlayView: View {
  let state: OverlayUIState
  let recordingMode: RecordingMode
  let levels: [Float]
  let holdHotkeySpelled: String
  let tapHotkeySpelled: String

  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // Idle-not-hovered: a small empty capsule. Acts as an unobtrusive cursor
  // target — the surrounding hit area expands the pill on hover.
  private let collapsedWidth: CGFloat = 32
  private let collapsedHeight: CGFloat = 8
  // Expanded info card: mode-name labels and spelled-out hotkeys, or the
  // waveform + a mode-specific stop hint during recording.
  private let expandedWidth: CGFloat = 300
  private let expandedHeight: CGFloat = 52

  private var isExpanded: Bool {
    switch state {
    case .recording, .processing: return true
    case .idle: return isHovered
    }
  }

  private var currentSize: CGSize {
    isExpanded
      ? CGSize(width: expandedWidth, height: expandedHeight)
      : CGSize(width: collapsedWidth, height: collapsedHeight)
  }

  var body: some View {
    capsule
      .frame(width: currentSize.width, height: currentSize.height)
      .animation(
        reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.85),
        value: currentSize
      )
      .overlay(content)
      // Outer frame holds the largest possible footprint so the panel doesn't
      // need to resize when the pill grows/shrinks. shadowMargin in
      // OverlayWindowController matches expandedWidth × expandedHeight.
      .frame(width: expandedWidth, height: expandedHeight)
      .contentShape(Rectangle())
      .onHover { isHovered = $0 }
      .padding(OverlayWindowController.shadowMargin)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel)
  }

  private var capsule: some View {
    Capsule()
      .fill(Color.black)
      .overlay(
        Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
  }

  @ViewBuilder
  private var content: some View {
    switch state {
    case .idle:
      if isHovered {
        expandedIdleCard.transition(.opacity)
      }
      // Idle and not hovered: render nothing — the capsule itself is the
      // entire visual, a small empty dot.
    case .recording:
      recordingCard.transition(.opacity)
    case .processing:
      ProgressView()
        .controlSize(.small)
        .tint(Color.white)
        .transition(.opacity)
    }
  }

  private var expandedIdleCard: some View {
    VStack(alignment: .leading, spacing: 3) {
      hotkeyRow(mode: "Push to talk", value: holdHotkeySpelled)
      hotkeyRow(mode: "Hands-free", value: tapHotkeySpelled)
    }
    .padding(.horizontal, 16)
  }

  private var recordingCard: some View {
    VStack(spacing: 2) {
      WaveformBars(levels: levels)
      Text(stopHint)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.75))
        .lineLimit(1)
    }
  }

  private var stopHint: String {
    switch recordingMode {
    case .pushToTalk: return "Release to stop"
    case .handsFree: return "Tap \(tapHotkeySpelled) to stop"
    }
  }

  private func hotkeyRow(mode: String, value: String) -> some View {
    HStack(spacing: 8) {
      Text(mode)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.white)
      Text("·")
        .font(.system(size: 11))
        .foregroundStyle(Color.white.opacity(0.4))
      Text(value)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.75))
    }
  }

  private var accessibilityLabel: String {
    switch state {
    case .idle:
      return "OpenFlow ready. Push to talk with \(holdHotkeySpelled), or hands-free with \(tapHotkeySpelled)."
    case .recording:
      switch recordingMode {
      case .pushToTalk: return "Recording. Release \(holdHotkeySpelled) to stop."
      case .handsFree: return "Recording. Tap \(tapHotkeySpelled) to stop."
      }
    case .processing:
      return "Processing."
    }
  }
}

private struct WaveformBars: View {
  let levels: [Float]

  private let barWidth: CGFloat = 2
  private let barSpacing: CGFloat = 3
  private let maxBarHeight: CGFloat = 18
  private let minBarHeightFraction: CGFloat = 0.10

  var body: some View {
    HStack(spacing: barSpacing) {
      ForEach(0..<OverlayBridge.waveformBarCount, id: \.self) { idx in
        Capsule()
          .fill(Color.white)
          .frame(width: barWidth, height: barHeight(at: idx))
      }
    }
    .frame(height: maxBarHeight)
    .animation(.linear(duration: 0.06), value: levels)
  }

  private func barHeight(at index: Int) -> CGFloat {
    // Mirror around the center bar so the waveform reads as a symmetric wave
    // expanding from the middle (matches Wispr Flow's overlay), instead of a
    // ticker-tape drifting left-to-right. levels is oldest→newest; the center
    // bar shows the newest sample and each pair on either side shows
    // progressively older samples.
    let count = OverlayBridge.waveformBarCount
    let mid = count / 2
    let distanceFromCenter = abs(index - mid)
    let sourceIndex = (levels.count - 1) - distanceFromCenter
    let raw = (sourceIndex >= 0 && sourceIndex < levels.count) ? CGFloat(levels[sourceIndex]) : 0
    // sqrt response: RMS of normal speech is ~0.02–0.15 and feels too compressed
    // under linear scaling. Square-root expands the bottom of the range so quiet
    // syllables still visibly move the bars.
    let scaled = min(1, sqrt(raw * 4))
    let fraction = max(minBarHeightFraction, scaled)
    return maxBarHeight * fraction
  }
}
