import AppKit
import SwiftUI

@main
struct OpenFlowApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") {
          (NSApp.delegate as? AppDelegate)?.openWizard()
        }
        .keyboardShortcut(",", modifiers: [.command])
      }
    }
  }
}
