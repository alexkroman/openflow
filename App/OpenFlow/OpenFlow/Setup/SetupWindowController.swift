import AppKit
import SwiftUI

@MainActor
final class SetupWindowController {
  private var window: NSWindow?

  func show() {
    if let window {
      bringToFront(window)
      return
    }
    let hosting = NSHostingController(rootView: SetupView())
    let w = NSWindow(contentViewController: hosting)
    w.title = "OpenFlow Setup"
    w.styleMask = [.titled, .closable]
    // Default for windows created from a hosting controller is true; closing
    // would deallocate the NSWindow and the cached `window` ref would dangle
    // on the next show() call.
    w.isReleasedWhenClosed = false
    w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    w.center()
    window = w
    bringToFront(w)
  }

  private func bringToFront(_ w: NSWindow) {
    // LSUIElement apps don't get a free pass through macOS 14+ cooperative
    // activation — when this is invoked from the status-bar menu, NSApp.activate
    // typically loses the race against the foreground app, so makeKeyAndOrderFront
    // only reorders within OpenFlow's own window stack. orderFrontRegardless
    // bypasses that and forces the window above other apps' windows.
    NSApp.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
    w.orderFrontRegardless()
  }
}
