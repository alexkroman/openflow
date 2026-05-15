import SwiftUI

struct SettingUpStepView: View {
  let state: ModelLoadState
  let retrySTT: () -> Void
  let retryLLM: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      WizardStepHeader(
        title: "Setting up OpenFlow",
        subtitle: "We're downloading the on-device models. This happens once."
      )
      Divider()
      Form {
        ModelLoadSection(
          state: state,
          retrySTT: retrySTT,
          retryLLM: retryLLM
        )
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
    }
  }
}
