import OpenFlowEngine
import SwiftUI

struct PermissionsStepView: View {
  @ObservedObject var controller: WizardController

  var body: some View {
    VStack(spacing: 0) {
      WizardStepHeader(
        title: "Welcome to OpenFlow",
        subtitle: "Hold \(DictateHotkey.label) anywhere to dictate. "
          + "Your voice is transcribed on-device and typed into the app you're using."
      )
      Divider()
      Form {
        microphoneSection
        accessibilitySection
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
    }
  }

  private var microphoneSection: some View {
    Section {
      permissionRow(
        label: "Microphone",
        symbol: "mic.fill",
        granted: controller.permissions.microphone,
        buttonLabel: "Allow Microphone Access",
        isPrimaryAction: !controller.permissions.microphone,
        action: {
          Task {
            _ = await PermissionsChecker.requestMicrophone()
            controller.continueFromPermissions()
          }
        }
      )
    } header: {
      Text("Microphone")
    } footer: {
      Text(
        "OpenFlow needs to hear you while you dictate. "
          + "Recording only happens while you're holding \(DictateHotkey.label)."
      )
    }
  }

  private var accessibilitySection: some View {
    Section {
      permissionRow(
        label: "Accessibility",
        symbol: "accessibility",
        granted: controller.permissions.accessibility,
        buttonLabel: "Open Accessibility Settings…",
        isPrimaryAction: controller.permissions.microphone
          && !controller.permissions.accessibility,
        action: { PermissionsChecker.openAccessibilitySettings() }
      )
    } header: {
      Text("Accessibility")
    } footer: {
      Text(
        "OpenFlow types the transcribed text into the app you're using. "
          + "This opens System Settings — turn on OpenFlow in the Accessibility list, "
          + "then come back here."
      )
    }
  }

  @ViewBuilder
  private func permissionRow(
    label: String,
    symbol: String,
    granted: Bool,
    buttonLabel: String,
    isPrimaryAction: Bool,
    action: @escaping () -> Void
  ) -> some View {
    LabeledContent {
      if granted {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
          Text("Granted").foregroundStyle(.secondary)
        }
      } else if isPrimaryAction {
        Button(buttonLabel, action: action).keyboardShortcut(.defaultAction)
      } else {
        Button(buttonLabel, action: action)
      }
    } label: {
      Label(label, systemImage: symbol)
    }
  }
}
