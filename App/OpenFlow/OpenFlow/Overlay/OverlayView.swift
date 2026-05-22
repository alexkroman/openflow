import SwiftUI

enum OverlayUIState: Equatable {
  case idle
  case recording
  case processing
}

struct OverlayView: View {
  let state: OverlayUIState
  let levels: [Float]
  let holdHotkeyGlyph: String
  let holdHotkeySpelled: String
  let tapHotkeySpelled: String

  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // Compact idle pill: mic glyph + hold label.
  private let compactWidth: CGFloat = 120
  private let compactHeight: CGFloat = 28
  // Expanded info card: fits two rows ("Hold: Ctrl+Opt+D" / "Tap: Ctrl+Opt+H")
  // or waveform + tap hint during recording.
  private let expandedWidth: CGFloat = 240
  private let expandedHeight: CGFloat = 48

  private var isExpanded: Bool {
    switch state {
    case .recording, .processing: return true
    case .idle: return isHovered
    }
  }

  private var currentSize: CGSize {
    isExpanded
      ? CGSize(width: expandedWidth, height: expandedHeight)
      : CGSize(width: compactWidth, height: compactHeight)
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
      } else {
        compactIdlePill.transition(.opacity)
      }
    case .recording:
      recordingCard.transition(.opacity)
    case .processing:
      ProgressView()
        .controlSize(.small)
        .tint(Color.white)
        .transition(.opacity)
    }
  }

  private var compactIdlePill: some View {
    HStack(spacing: 6) {
      Image(systemName: "mic.fill")
        .font(.callout)
        .foregroundStyle(Color.white.opacity(0.7))
      Text(holdHotkeyGlyph)
        .font(.callout.monospaced().weight(.semibold))
        .foregroundStyle(Color.white)
    }
  }

  private var expandedIdleCard: some View {
    VStack(alignment: .leading, spacing: 2) {
      hotkeyRow(prefix: "Hold:", value: holdHotkeySpelled)
      hotkeyRow(prefix: "Tap:", value: tapHotkeySpelled)
    }
    .padding(.horizontal, 14)
  }

  private var recordingCard: some View {
    VStack(spacing: 2) {
      WaveformBars(levels: levels)
      Text("Release · Tap \(tapHotkeySpelled) to stop")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.75))
        .lineLimit(1)
    }
  }

  private func hotkeyRow(prefix: String, value: String) -> some View {
    HStack(spacing: 6) {
      Text(prefix)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.65))
        .frame(width: 36, alignment: .leading)
      Text(value)
        .font(.system(size: 12, weight: .semibold).monospaced())
        .foregroundStyle(Color.white)
    }
  }

  private var accessibilityLabel: String {
    switch state {
    case .idle:
      return "OpenFlow ready. Hold \(holdHotkeySpelled) or tap \(tapHotkeySpelled) to dictate."
    case .recording:
      return "Recording. Release \(holdHotkeySpelled) or tap \(tapHotkeySpelled) to stop."
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
