import AppKit
import OpenFlowEngine
import SwiftUI

@MainActor
final class WizardWindowController {
  private var window: NSWindow?
  private let closeDelegate = WindowCloseObserver()
  private var stepSyncTask: Task<Void, Never>?

  func show(controller: WizardController, coordinator: AppCoordinator) {
    // Always recreate the window. Reusing a previously-closed NSWindow with a
    // SwiftUI hosting controller leaves the hosting view tree in a state where
    // makeKeyAndOrderFront silently no-ops on some macOS versions. A fresh
    // window is cheap and avoids the edge case entirely.
    if let oldWindow = window {
      stepSyncTask?.cancel()
      oldWindow.delegate = nil
      oldWindow.close()
    }

    let hosting = NSHostingController(
      rootView: WizardView(controller: controller, coordinator: coordinator)
    )
    let w = NSWindow(contentViewController: hosting)
    w.title = title(for: controller.step)
    w.styleMask = styleMask(for: controller.step)
    w.isReleasedWhenClosed = false
    w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    // NSHostingController's preferredContentSize is unreliable on first show —
    // SwiftUI hasn't measured yet, so the window opens at ~187pt tall and
    // clips the Form. Force an explicit per-step size.
    w.setContentSize(contentSize(for: controller.step))
    w.center()
    closeDelegate.controller = controller
    closeDelegate.onClose = { [weak self] in self?.stepSyncTask?.cancel() }
    w.delegate = closeDelegate
    window = w

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
        w.setContentSize(self.contentSize(for: controller.step))
      }
    }
  }

  private func bringToFront(_ w: NSWindow) {
    NSApp.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
    // Defensive: when invoked from a SwiftUI menu command, the activation
    // can lose the race against the foreground app. orderFrontRegardless
    // forces the window above other apps' windows.
    w.orderFrontRegardless()
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

  private func contentSize(for step: WizardStep) -> NSSize {
    switch step {
    case .permissions: return NSSize(width: 500, height: 440)
    case .settingUp:   return NSSize(width: 500, height: 260)
    case .hotkey:      return NSSize(width: 500, height: 320)
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
