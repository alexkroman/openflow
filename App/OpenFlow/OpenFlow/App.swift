import SwiftUI

@main
struct OpenFlowApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    // SwiftUI's `App` protocol requires at least one scene. We manage window
    // creation in AppDelegate, so this scene's content is never shown — its
    // sole purpose is to satisfy the protocol. We replace the auto-generated
    // "Settings…" menu item (which would otherwise open this EmptyView()
    // window) with a command that routes through AppDelegate to the real
    // Setup window. Cmd+, is preserved.
    Settings { EmptyView() }
      .commands {
        CommandGroup(replacing: .appSettings) {
          Button("Settings…") {
            (NSApp.delegate as? AppDelegate)?.showSetup()
          }
          .keyboardShortcut(",", modifiers: .command)
        }
      }
  }
}
