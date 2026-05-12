import SwiftUI

struct SettingUpStepView: View {
  let state: ModelLoadState
  let retrySTT: () -> Void
  let retryLLM: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
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

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Setting up OpenFlow").font(.title).bold()
      Text("We're downloading the on-device models. This happens once.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(28)
  }
}
