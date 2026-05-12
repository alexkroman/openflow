import AppKit

@MainActor
enum AppRelauncher {
  /// Spawn a fresh instance of OpenFlow and terminate the current one. Needed
  /// because Accessibility permission changes don't always propagate to a
  /// running process — only a new process reads fresh TCC state at launch.
  static func relaunch() {
    let url = Bundle.main.bundleURL
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
      Task { @MainActor in NSApp.terminate(nil) }
    }
  }
}
