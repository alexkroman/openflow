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

  @ViewBuilder
  private var capsule: some View {
    if #available(macOS 26.0, *) {
      Capsule().fill(.clear).glassEffect(in: Capsule())
    } else {
      Capsule()
        .fill(.regularMaterial)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
  }

  @ViewBuilder
  private var content: some View {
    if isExpanded {
      switch state {
      case .idle:
        Text(hotkeyLabel)
          .font(.callout.monospaced().weight(.semibold))
          .foregroundStyle(.primary)
          .transition(.opacity)
      case .recording:
        WaveformBars(levels: levels)
          .transition(.opacity)
      case .processing:
        ProgressView()
          .controlSize(.small)
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
          .fill(Color.primary)
          .frame(width: barWidth, height: barHeight(at: idx))
      }
    }
    .frame(height: maxBarHeight)
    .animation(.linear(duration: 0.06), value: levels)
  }

  private func barHeight(at index: Int) -> CGFloat {
    let raw = index < levels.count ? CGFloat(levels[index]) : 0
    // RMS of speech rarely exceeds ~0.3 — scale generously so quiet speech still reads.
    let scaled = min(1, raw * 3.0)
    let fraction = max(minBarHeightFraction, scaled)
    return maxBarHeight * fraction
  }
}
