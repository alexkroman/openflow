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

    // Build statusItem first so we can hand it to the coordinator, then wire
    // the onShowSetup closure to look up the coordinator at click time (it
    // needs the coordinator's observable state to render the Setup UI).
    let statusItem = StatusItemController(
      onShowSetup: { [weak self] in
        guard let self else { return }
        MainActor.assumeIsolated {
          if let coordinator = self.coordinator {
            setupWindow.show(coordinator: coordinator)
          }
        }
      },
      onQuit: { NSApp.terminate(nil) }
    )
    self.statusItem = statusItem

    let coord = AppCoordinator(
      overlay: overlay,
      toast: toast,
      statusItem: statusItem
    )
    self.coordinator = coord

    // Show Setup on launch when permissions are missing OR models aren't
    // ready yet. modelLoadState starts as .idle on first launch (and remains
    // not-ready until both downloads complete) so this opens automatically on
    // any cold launch / cache wipe.
    if !PermissionsChecker.check().allGranted || !coord.modelLoadState.isReady {
      setupWindow.show(coordinator: coord)
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
    if let coordinator = self.coordinator {
      setupWindow.show(coordinator: coordinator)
    }
    return true
  }
}
