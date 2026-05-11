import AppKit
import KeyboardShortcuts
import OpenFlowEngine
import SwiftUI

@MainActor
final class SetupViewModel: ObservableObject {
  @Published var status: PermissionStatus = PermissionsChecker.check()

  func recheck() {
    status = PermissionsChecker.check()
  }

  func requestMic() async {
    _ = await PermissionsChecker.requestMicrophone()
    recheck()
  }

  func openAccessibility() {
    PermissionsChecker.openAccessibilitySettings()
  }

  func relaunch() {
    let url = Bundle.main.bundleURL
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
      Task { @MainActor in NSApp.terminate(nil) }
    }
  }
}

struct SetupView: View {
  @StateObject var vm = SetupViewModel()
  @ObservedObject var coordinator: AppCoordinator

  private var hotkeyLabel: String { DictateHotkey.label }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      Form {
        if !coordinator.modelLoadState.isReady {
          ModelLoadSection(
            state: coordinator.modelLoadState,
            retrySTT: { Task { await coordinator.retrySTTWarmUp() } },
            retryLLM: { Task { await coordinator.retryLLMWarmUp() } }
          )
        }
        hotkeySection
        if vm.status.allGranted {
          successSection
        } else {
          microphoneSection
          accessibilitySection
          recheckSection
        }
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
    }
    .frame(width: 500)
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        vm.recheck()
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage ?? NSImage())
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text("Welcome to OpenFlow").font(.title).bold()
        Text(
          "Hold \(hotkeyLabel) anywhere to dictate. "
            + "Your voice is transcribed on-device and typed into the app you're using."
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(28)
  }

  private var hotkeySection: some View {
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

  private var successSection: some View {
    Section {
      LabeledContent {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
          Text("All set").foregroundStyle(.secondary)
        }
      } label: {
        Label("Permissions", systemImage: "lock.shield")
      }
      Button("Restart OpenFlow") { vm.relaunch() }
        .keyboardShortcut(.defaultAction)
    } footer: {
      Text("OpenFlow needs to restart so the new permissions take effect.")
    }
  }

  private var microphoneSection: some View {
    Section {
      permissionRow(
        symbol: "mic.fill",
        granted: vm.status.microphone,
        buttonLabel: "Allow Microphone Access",
        isPrimaryAction: !vm.status.microphone,
        action: { Task { await vm.requestMic() } }
      )
    } header: {
      Text("Microphone")
    } footer: {
      Text(
        "OpenFlow needs to hear you while you dictate. "
          + "Recording only happens while you're holding \(hotkeyLabel)."
      )
    }
  }

  private var accessibilitySection: some View {
    Section {
      permissionRow(
        symbol: "accessibility",
        granted: vm.status.accessibility,
        buttonLabel: "Open Accessibility Settings…",
        isPrimaryAction: vm.status.microphone && !vm.status.accessibility,
        action: { vm.openAccessibility() }
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

  private var recheckSection: some View {
    Section {
      HStack {
        Spacer()
        Button("Recheck Status") { vm.recheck() }
      }
    }
  }

  @ViewBuilder
  private func permissionRow(
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
      Label("Status", systemImage: symbol)
    }
  }
}
