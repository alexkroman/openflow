import AppKit
import OpenFlowEngine
import SwiftUI

@MainActor
final class WizardWindowController {
  private var window: NSWindow?
  private let closeDelegate = WindowCloseObserver()

  func show(controller: WizardController, coordinator: AppCoordinator) {
    if let window {
      controller.startPolling()
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
    w.delegate = closeDelegate
    window = w

    // Keep the title and style mask in sync with the step.
    Task { @MainActor [weak self, weak controller] in
      guard let controller else { return }
      for await _ in controller.$step.values {
        guard let self, let w = self.window else { return }
        w.title = self.title(for: controller.step)
        w.styleMask = self.styleMask(for: controller.step)
      }
    }

    controller.startPolling()
    bringToFront(w)
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

/// Stops the controller's permission poll loop when the window closes.
@MainActor
final class WindowCloseObserver: NSObject, NSWindowDelegate {
  weak var controller: WizardController?

  func windowWillClose(_ notification: Notification) {
    controller?.stopPolling()
  }
}
