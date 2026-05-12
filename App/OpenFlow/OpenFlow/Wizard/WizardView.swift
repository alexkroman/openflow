import OpenFlowEngine
import SwiftUI

struct WizardView: View {
  @ObservedObject var controller: WizardController
  @ObservedObject var coordinator: AppCoordinator

  var body: some View {
    content
      .frame(width: 500)
  }

  @ViewBuilder
  private var content: some View {
    switch controller.step {
    case .permissions:
      PermissionsStepView(controller: controller)
    case .settingUp:
      SettingUpStepView(
        state: coordinator.modelLoadState,
        retrySTT: { Task { await coordinator.retrySTTWarmUp() } },
        retryLLM: { Task { await coordinator.retryLLMWarmUp() } }
      )
    case .hotkey:
      HotkeyStepView()
    }
  }
}
