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

  private var isExpanded: Bool {
    switch state {
    case .recording, .processing: return true
    case .idle: return isHovered
    }
  }

  var body: some View {
    ZStack {
      capsule
        .frame(
          width: isExpanded ? 120 : 32,
          height: isExpanded ? 28 : 8
        )
        .animation(
          reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.85),
          value: isExpanded
        )
        .overlay(content)
    }
    .frame(width: 120, height: 28)
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
      Group {
        switch state {
        case .idle:
          Text(hotkeyLabel)
            .font(.callout.monospaced().weight(.semibold))
            .foregroundStyle(.primary)
        case .recording:
          // Placeholder — replaced by waveform in Task 5.
          Circle().fill(.red).frame(width: 8, height: 8)
        case .processing:
          ProgressView()
            .controlSize(.small)
        }
      }
      .transition(.opacity)
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
