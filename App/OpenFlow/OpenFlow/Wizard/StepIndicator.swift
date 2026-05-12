import OpenFlowEngine
import SwiftUI

struct StepIndicator: View {
  let step: WizardStep

  var body: some View {
    HStack(spacing: 8) {
      HStack(spacing: 4) {
        dot(filled: true)
        dot(filled: step != .permissions)
        dot(filled: step == .hotkey)
      }
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
  }

  private var label: String {
    switch step {
    case .permissions: return "Step 1 of 3 — Permissions"
    case .settingUp:   return "Step 2 of 3 — Setting up"
    case .hotkey:      return "Step 3 of 3 — Hotkey"
    }
  }

  private func dot(filled: Bool) -> some View {
    Circle()
      .fill(filled ? Color.accentColor : Color.secondary.opacity(0.35))
      .frame(width: 8, height: 8)
  }
}
