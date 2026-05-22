import KeyboardShortcuts
import SwiftUI

struct HotkeyStepView: View {
  var body: some View {
    VStack(spacing: 0) {
      WizardStepHeader(
        title: "OpenFlow",
        subtitle: "Hold a shortcut to dictate, or use the hands-free toggle to tap on and off."
      )
      Divider()
      Form {
        shortcutSection
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
      .padding(.bottom, 12)
    }
  }

  private var shortcutSection: some View {
    Section {
      LabeledContent {
        KeyboardShortcuts.Recorder(for: .dictate)
      } label: {
        Label("Push to talk", systemImage: "keyboard")
      }
      LabeledContent {
        KeyboardShortcuts.Recorder(for: .handsFree)
      } label: {
        Label("Hands-free (tap on/off)", systemImage: "hand.raised")
      }
    } header: {
      Text("Shortcuts")
    } footer: {
      Text("Defaults: Push to talk is Ctrl + Option + D · Hands-free is Ctrl + Option + H. Either can be any key+modifier combo.")
    }
  }
}
