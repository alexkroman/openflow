import AppKit
import OpenFlowEngine
import SwiftUI

@MainActor
final class WizardWindowController {
  private var window: NSWindow?
  private let closeDelegate = WindowCloseObserver()
  private var stepSyncTask: Task<Void, Never>?

  func show(controller: WizardController, coordinator: AppCoordinator) {
    if let window {
      controller.startPolling()
      // Restart the sync task in case the previous window-close cancelled it.
      startStepSync(controller: controller)
      bringToFront(window)
      return
    }
    let hosting = NSHostingController(
      rootView: WizardView(controller: controller, coordinator: coordinator)
    )
    let w = NSWindow(contentViewController: hosting)
    w.title = title(for: controller.step)
    w.styleMask = styleMask(for: controller.step)
    w.isReleasedWhenClosed = false
    w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    w.center()
    closeDelegate.controller = controller
    closeDelegate.onClose = { [weak self] in self?.stepSyncTask?.cancel() }
    w.delegate = closeDelegate
    window = w

    // Keep the title and style mask in sync with the step. Stored so the
    // window-close path can cancel it; restarted on next show().
    startStepSync(controller: controller)

    controller.startPolling()
    bringToFront(w)
  }

  private func startStepSync(controller: WizardController) {
    stepSyncTask?.cancel()
    stepSyncTask = Task { @MainActor [weak self, weak controller] in
      guard let controller else { return }
      for await _ in controller.$step.values {
        guard let self, let w = self.window else { return }
        w.title = self.title(for: controller.step)
        w.styleMask = self.styleMask(for: controller.step)
      }
    }
  }

  private func bringToFront(_ w: NSWindow) {
    NSApp.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
  }

  private func title(for step: WizardStep) -> String {
    switch step {
    case .permissions: return "Welcome to OpenFlow"
    case .settingUp:   return "Setting up OpenFlow"
    case .hotkey:      return "OpenFlow"
    }
  }

  private func styleMask(for step: WizardStep) -> NSWindow.StyleMask {
    switch step {
    case .permissions, .settingUp: return [.titled, .closable]
    case .hotkey:                  return [.titled, .closable, .miniaturizable]
    }
  }
}

/// Stops the controller's permission poll loop and the window's step-sync
/// task when the window closes.
@MainActor
private final class WindowCloseObserver: NSObject, NSWindowDelegate {
  weak var controller: WizardController?
  var onClose: (() -> Void)?

  func windowWillClose(_ notification: Notification) {
    controller?.stopPolling()
    onClose?()
  }
}
