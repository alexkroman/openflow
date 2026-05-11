import SwiftUI

struct OverlayState: Equatable {
  enum Phase: Equatable {
    case idle
    case recording
    case transcribing
    case styling
  }
  let phase: Phase
  let hotkeyLabel: String

  init(phase: Phase, hotkeyLabel: String = "") {
    self.phase = phase
    self.hotkeyLabel = hotkeyLabel
  }
}

struct OverlayView: View {
  let state: OverlayState

  var body: some View {
    HStack(spacing: 10) {
      icon
      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 14).padding(.vertical, 10)
    .frame(width: 260, height: 36)
    .modifier(OverlayCapsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  @ViewBuilder
  private var icon: some View {
    switch state.phase {
    case .idle:
      Image(systemName: "mic").foregroundStyle(.secondary)
    case .recording:
      Image(systemName: "mic.fill")
        .foregroundStyle(.red)
        .symbolEffect(.pulse, options: .repeating)
    case .transcribing:
      Image(systemName: "waveform").foregroundStyle(.orange)
    case .styling:
      Image(systemName: "sparkles").foregroundStyle(.blue)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch state.phase {
    case .idle:
      HStack(spacing: 6) {
        Text("Hold").foregroundStyle(.secondary)
        Text(state.hotkeyLabel).monospaced().fontWeight(.semibold)
        Text("to dictate").foregroundStyle(.secondary)
      }
      .font(.callout)
    case .recording:
      Text("Listening…").font(.callout)
    case .transcribing:
      Text("Transcribing…").font(.callout)
    case .styling:
      Text("Refining…").font(.callout)
    }
  }

  private var accessibilityLabel: String {
    switch state.phase {
    case .idle: return "OpenFlow ready. Hold \(state.hotkeyLabel) to dictate."
    case .recording: return "Recording."
    case .transcribing: return "Transcribing."
    case .styling: return "Refining."
    }
  }
}

private struct OverlayCapsule: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(in: Capsule())
    } else {
      content
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
  }
}
