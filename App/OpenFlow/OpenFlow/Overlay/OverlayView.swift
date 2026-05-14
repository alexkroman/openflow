import SwiftUI

enum OverlayUIState: Equatable {
  case idle
  case recording
  case processing
}

struct OverlayView: View {
  let state: OverlayUIState
  let levels: [Float]
  let hotkeyLabel: String

  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let expandedWidth: CGFloat = 120
  private let expandedHeight: CGFloat = 28
  private let collapsedWidth: CGFloat = 32
  private let collapsedHeight: CGFloat = 8

  private var isExpanded: Bool {
    switch state {
    case .recording, .processing: return true
    case .idle: return isHovered
    }
  }

  var body: some View {
    capsule
      .frame(
        width: isExpanded ? expandedWidth : collapsedWidth,
        height: isExpanded ? expandedHeight : collapsedHeight
      )
      .animation(
        reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.85),
        value: isExpanded
      )
      .overlay(content)
      .frame(width: expandedWidth, height: expandedHeight)
      .contentShape(Rectangle())
      .onHover { isHovered = $0 }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel)
  }

  private var capsule: some View {
    Capsule()
      .fill(Color.black)
      .overlay(
        Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
  }

  @ViewBuilder
  private var content: some View {
    if isExpanded {
      switch state {
      case .idle:
        HStack(spacing: 6) {
          Image(systemName: "mic.fill")
            .font(.callout)
            .foregroundStyle(Color.white.opacity(0.7))
          Text(hotkeyLabel)
            .font(.callout.monospaced().weight(.semibold))
            .foregroundStyle(Color.white)
        }
        .transition(.opacity)
      case .recording:
        WaveformBars(levels: levels)
          .transition(.opacity)
      case .processing:
        ProgressView()
          .controlSize(.small)
          .tint(Color.white)
          .transition(.opacity)
      }
    }
  }

  private var accessibilityLabel: String {
    switch state {
    case .idle: return "OpenFlow ready. Hold \(hotkeyLabel) to dictate."
    case .recording: return "Recording."
    case .processing: return "Processing."
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
    let raw = index < levels.count ? CGFloat(levels[index]) : 0
    // sqrt response: RMS of normal speech is ~0.02–0.15 and feels too compressed
    // under linear scaling. Square-root expands the bottom of the range so quiet
    // syllables still visibly move the bars.
    let scaled = min(1, sqrt(raw * 4))
    let fraction = max(minBarHeightFraction, scaled)
    return maxBarHeight * fraction
  }
}
