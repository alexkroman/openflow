import SwiftUI

@main
struct OpenFlowApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings { EmptyView() }
  }
}
