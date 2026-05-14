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

  var body: some View {
    // Minimal placeholder — replaced in Task 4.
    Capsule()
      .fill(Color.secondary.opacity(0.25))
      .frame(width: 32, height: 8)
      .frame(width: 120, height: 28, alignment: .center)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    switch state {
    case .idle: return "OpenFlow ready. Hold \(hotkeyLabel) to dictate."
    case .recording: return "Recording."
    case .processing: return "Processing."
    }
  }
}
