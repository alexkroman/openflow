import AppKit
import SwiftUI

@MainActor
final class OverlayBridge: ObservableObject {
  @Published var state: OverlayState = .init(phase: .idle)
}

private struct OverlayHost: View {
  @ObservedObject var bridge: OverlayBridge
  var body: some View {
    OverlayView(state: bridge.state)
  }
}

@MainActor
final class OverlayWindowController {
  private static let customOriginXKey = "OpenFlowOverlayCustomOriginX"
  private static let customOriginYKey = "OpenFlowOverlayCustomOriginY"

  private let panel: NSPanel
  private let hosting: NSHostingView<OverlayHost>
  private let bridge = OverlayBridge()
  private var suppressOriginPersist = false

  init() {
    let host = OverlayHost(bridge: bridge)
    self.hosting = NSHostingView(rootView: host)
    self.panel = FloatingPanel.make(
      size: CGSize(width: 260, height: 36),
      collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary],
      contentView: hosting
    )
    panel.isMovable = true
    panel.isMovableByWindowBackground = true

    NotificationCenter.default.addObserver(
      forName: NSWindow.didMoveNotification,
      object: panel,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleDidMove()
      }
    }
  }

  func show(state: OverlayState) {
    bridge.state = state
    guard !panel.isVisible else { return }
    reposition()
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      panel.alphaValue = 1
      panel.orderFrontRegardless()
    } else {
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        panel.animator().alphaValue = 1
      }
    }
  }

  private func reposition() {
    guard let screen = NSScreen.main else { return }
    let frame = panel.frame
    let origin: NSPoint
    if let custom = storedCustomOrigin() {
      origin = clamp(point: custom, size: frame.size, into: screen.visibleFrame)
    } else {
      origin = NSPoint(
        x: screen.visibleFrame.midX - frame.width / 2,
        y: screen.visibleFrame.minY + 80)
    }
    suppressOriginPersist = true
    panel.setFrameOrigin(origin)
    suppressOriginPersist = false
  }

  private func handleDidMove() {
    guard !suppressOriginPersist else { return }
    let origin = panel.frame.origin
    UserDefaults.standard.set(Double(origin.x), forKey: Self.customOriginXKey)
    UserDefaults.standard.set(Double(origin.y), forKey: Self.customOriginYKey)
  }

  private func storedCustomOrigin() -> NSPoint? {
    let defaults = UserDefaults.standard
    guard
      defaults.object(forKey: Self.customOriginXKey) != nil,
      defaults.object(forKey: Self.customOriginYKey) != nil
    else { return nil }
    return NSPoint(
      x: defaults.double(forKey: Self.customOriginXKey),
      y: defaults.double(forKey: Self.customOriginYKey))
  }

  private func clamp(point: NSPoint, size: CGSize, into rect: NSRect) -> NSPoint {
    let maxX = rect.maxX - size.width
    let maxY = rect.maxY - size.height
    return NSPoint(
      x: min(max(point.x, rect.minX), maxX),
      y: min(max(point.y, rect.minY), maxY))
  }
}
