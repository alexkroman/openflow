import AppKit
import Foundation
import OpenFlowEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
  @MainActor static private(set) var shared: AppDelegate?

  @MainActor private var coordinator: AppCoordinator?
  @MainActor private var wizardController: WizardController?
  @MainActor private let wizardWindow = WizardWindowController()

  @MainActor
  func applicationDidFinishLaunching(_ notification: Notification) {
    AppDelegate.shared = self

    // Fire the AX-protected call at launch so tccd registers OpenFlow in the
    // Accessibility list before the user ever opens System Settings.
    PermissionsChecker.registerForAccessibilityTCC()

    let overlay = OverlayWindowController()
    let toast = ToastPresenter()
    let coord = AppCoordinator(overlay: overlay, toast: toast)
    self.coordinator = coord

    let controller = WizardController(coordinator: coord)
    self.wizardController = controller

    if controller.step != .hotkey {
      wizardWindow.show(controller: controller, coordinator: coord)
    }

    coord.start()
  }

  @MainActor
  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows: Bool
  ) -> Bool {
    guard !hasVisibleWindows else { return true }
    if let coordinator = self.coordinator, let controller = self.wizardController {
      wizardWindow.show(controller: controller, coordinator: coordinator)
    }
    return false
  }

  @MainActor
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Called from the `Settings…` menu command in App.swift.
  @MainActor
  func openWizard() {
    guard let coordinator, let controller = wizardController else { return }
    wizardWindow.show(controller: controller, coordinator: coordinator)
  }
}
