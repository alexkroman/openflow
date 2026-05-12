import KeyboardShortcuts
import SwiftUI

struct HotkeyStepView: View {
  var body: some View {
    VStack(spacing: 0) {
      WizardStepHeader(
        title: "OpenFlow",
        subtitle: "Hold the shortcut anywhere on your Mac and start dictating."
      )
      Divider()
      Form {
        shortcutSection
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
    }
  }

  private var shortcutSection: some View {
    Section {
      LabeledContent {
        KeyboardShortcuts.Recorder(for: .dictate)
      } label: {
        Label("Hold to dictate", systemImage: "keyboard")
      }
    } header: {
      Text("Shortcut")
    } footer: {
      Text("Pick any key+modifier combo. Defaults to ⌃⌥D.")
    }
  }

}
