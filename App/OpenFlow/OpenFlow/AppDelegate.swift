import AppKit
import Foundation
import OpenFlowEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
  @MainActor private var coordinator: AppCoordinator?
  @MainActor private var setupWindow = SetupWindowController()
  @MainActor private var statusItem: StatusItemController?

  @MainActor
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Fire the AX-protected call at launch so tccd registers OpenFlow in the
    // Accessibility list before the user ever opens System Settings — clicking
    // the button later loses the race against the Settings UI rendering.
    PermissionsChecker.registerForAccessibilityTCC()

    let overlay = OverlayWindowController()
    let toast = ToastPresenter()
    let setupWindow = self.setupWindow

    let statusItem = StatusItemController(
      onShowSetup: { setupWindow.show() },
      onQuit: { NSApp.terminate(nil) }
    )
    self.statusItem = statusItem

    let coord = AppCoordinator(
      overlay: overlay,
      toast: toast,
      statusItem: statusItem
    )
    self.coordinator = coord

    if !PermissionsChecker.check().allGranted {
      setupWindow.show()
    }

    coord.start()
  }

  // For LSUIElement agent apps, this fires when the user re-launches the .app
  // from Finder/Spotlight — the user-facing escape hatch for "menu bar icon
  // hidden by the notch."
  @MainActor
  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows: Bool
  ) -> Bool {
    guard !hasVisibleWindows else { return true }
    setupWindow.show()
    return true
  }
}
