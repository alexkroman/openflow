import AppKit
import OpenFlowEngine
import SwiftUI

@MainActor
final class SetupWindowController {
  private var window: NSWindow?

  func show(coordinator: AppCoordinator) {
    if let window {
      NSApp.activate()
      window.makeKeyAndOrderFront(nil)
      return
    }
    let initialHeight = SetupView.targetHeight(
      modelReady: coordinator.modelLoadState.isReady,
      allGranted: PermissionsChecker.check().allGranted
    )
    let view = SetupView(coordinator: coordinator) { [weak self] height in
      // Hop off the SwiftUI update cycle before touching AppKit. The
      // earlier `sizingOptions = .preferredContentSize` crash came from
      // AppKit observing SwiftUI's intrinsic size synchronously; an
      // async, state-driven resize avoids that re-entrancy.
      Task { @MainActor in self?.setContentHeight(height) }
    }
    let hosting = NSHostingController(rootView: view)
    let w = NSWindow(contentViewController: hosting)
    w.title = "OpenFlow"
    // Closable so the user can dismiss it without quitting (terminate-after-
    // last-window-closed is false in AppDelegate, so the hotkey keeps working
    // in the background). No miniaturize button — Apple's Settings and
    // onboarding windows don't offer one either.
    w.styleMask = [.titled, .closable]
    // Default for windows created from a hosting controller is true; closing
    // would deallocate the NSWindow and the cached `window` ref would dangle
    // on the next show() call.
    w.isReleasedWhenClosed = false
    w.setContentSize(NSSize(width: 500, height: initialHeight))
    w.center()
    window = w
    NSApp.activate()
    w.makeKeyAndOrderFront(nil)
  }

  private func setContentHeight(_ height: CGFloat) {
    guard let window else { return }
    let currentFrame = window.frame
    let topY = currentFrame.maxY
    let contentRect = NSRect(origin: .zero, size: NSSize(width: 500, height: height))
    let newFrameSize = window.frameRect(forContentRect: contentRect).size
    guard abs(newFrameSize.height - currentFrame.height) > 0.5 else { return }
    let newFrame = NSRect(
      x: currentFrame.minX,
      y: topY - newFrameSize.height,
      width: newFrameSize.width,
      height: newFrameSize.height
    )
    window.setFrame(newFrame, display: true, animate: true)
  }
}
