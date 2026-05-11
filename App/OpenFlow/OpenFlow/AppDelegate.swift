import AppKit
import Foundation
import OpenFlowEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
  @MainActor private var coordinator: AppCoordinator?
  @MainActor private var setupWindow = SetupWindowController()

  @MainActor
  func applicationDidFinishLaunching(_ notification: Notification) {
    let overlay = OverlayWindowController()
    let toast = ToastPresenter()
    let setupWindow = self.setupWindow

    let coord = AppCoordinator(
      overlay: overlay,
      toast: toast,
      onShowSetup: { [weak self] in
        guard let self else { return }
        MainActor.assumeIsolated {
          if let coordinator = self.coordinator {
            setupWindow.show(coordinator: coordinator)
          }
        }
      }
    )
    self.coordinator = coord

    // modelLoadState starts not-ready, so Setup opens on every cold launch / cache wipe.
    if !PermissionsChecker.check().allGranted || !coord.modelLoadState.isReady {
      setupWindow.show(coordinator: coord)
    }

    coord.start()
  }

  /// Called from the SwiftUI `Settings…` command (⌘,) in `App.swift`.
  @MainActor
  func showSetup() {
    guard let coordinator else { return }
    setupWindow.show(coordinator: coordinator)
  }

  // Closing the Setup window must not quit the app — the hotkey still drives
  // dictation while the app sits idle in the Dock. Re-opening Setup is the
  // job of `applicationShouldHandleReopen` (Dock-icon click).
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

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
