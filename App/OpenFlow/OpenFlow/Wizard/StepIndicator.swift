import OpenFlowEngine
import SwiftUI

struct StepIndicator: View {
  let step: WizardStep

  var body: some View {
    HStack(spacing: 4) {
      dot(filled: true)
      dot(filled: step != .permissions)
      dot(filled: step == .hotkey)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
  }

  private func dot(filled: Bool) -> some View {
    Circle()
      .fill(filled ? Color.accentColor : Color.secondary.opacity(0.35))
      .frame(width: 8, height: 8)
  }
}
