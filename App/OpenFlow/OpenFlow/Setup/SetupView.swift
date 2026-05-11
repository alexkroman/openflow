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
}

private enum SetupPhase {
  case permissions, loading, main

  static func from(allGranted: Bool, modelReady: Bool) -> SetupPhase {
    if !allGranted { return .permissions }
    if !modelReady { return .loading }
    return .main
  }

  var height: CGFloat {
    switch self {
    case .permissions: 400
    case .loading: 300
    case .main: 250
    }
  }
}

struct SetupView: View {
  @StateObject var vm = SetupViewModel()
  @ObservedObject var coordinator: AppCoordinator
  var onHeightChange: (CGFloat) -> Void = { _ in }

  private var hotkeyLabel: String { DictateHotkey.label }

  /// Permissions are the gate — always show the permissions step if any
  /// grant is missing, including after revocation. Once permissions are
  /// in place, the model-load step runs (cache delete also re-enters
  /// it). Otherwise we're in the steady-state "main" view.
  private var phase: SetupPhase {
    .from(allGranted: vm.status.allGranted, modelReady: coordinator.modelLoadState.isReady)
  }

  static func targetHeight(modelReady: Bool, allGranted: Bool) -> CGFloat {
    SetupPhase.from(allGranted: allGranted, modelReady: modelReady).height
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      Form {
        switch phase {
        case .permissions:
          microphoneSection
          accessibilitySection
        case .loading:
          ModelLoadSection(
            state: coordinator.modelLoadState,
            retrySTT: { Task { await coordinator.retrySTTWarmUp() } },
            retryLLM: { Task { await coordinator.retryLLMWarmUp() } }
          )
        case .main:
          hotkeySection
        }
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
    }
    .frame(width: 500)
    .onChange(of: phase) { _, newPhase in
      onHeightChange(newPhase.height)
    }
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
        Text("OpenFlow").font(.title).bold()
        Text("Hold \(hotkeyLabel) in any app to dictate. Transcription stays on this device.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(20)
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
      Text("Default: ⌃⌥D.")
    }
  }

  private var microphoneSection: some View {
    Section {
      permissionRow(
        rowLabel: "Microphone",
        symbol: "mic.fill",
        granted: vm.status.microphone,
        buttonLabel: "Allow Microphone Access",
        isPrimaryAction: !vm.status.microphone,
        action: { Task { await vm.requestMic() } }
      )
    } header: {
      Text("Microphone")
    } footer: {
      Text("OpenFlow only records while you hold the shortcut.")
    }
  }

  private var accessibilitySection: some View {
    Section {
      permissionRow(
        rowLabel: "Accessibility",
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
        "Required to type into other apps. "
          + "Add OpenFlow in System Settings → Privacy & Security → Accessibility, "
          + "then turn it on."
      )
    }
  }

  @ViewBuilder
  private func permissionRow(
    rowLabel: String,
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
      Label(rowLabel, systemImage: symbol)
    }
  }
}
