import AppKit
import SwiftUI

@MainActor
final class OverlayBridge: ObservableObject {
  static let waveformBarCount = 9

  @Published var state: OverlayUIState = .idle
  @Published var levels: [Float] = Array(repeating: 0, count: waveformBarCount)

  // Auto-gain: a running peak decays slowly between pushes so the bars stay
  // responsive regardless of the user's mic input gain. Floor prevents
  // divide-by-zero amplification of silence-floor noise into visible bars.
  private var peak: Float = peakFloor
  private static let peakFloor: Float = 0.0005
  private static let peakDecay: Float = 0.97

  func pushLevel(_ value: Float) {
    peak = max(value, max(Self.peakFloor, peak * Self.peakDecay))
    let normalized = min(1, value / peak)
    levels.removeFirst()
    levels.append(normalized)
  }
}

private struct OverlayHost: View {
  @ObservedObject var bridge: OverlayBridge
  var body: some View {
    OverlayView(state: bridge.state, levels: bridge.levels, hotkeyLabel: DictateHotkey.label)
  }
}

@MainActor
final class OverlayWindowController {
  private static let customOriginXKey = "OpenFlowOverlayCustomOriginX"
  private static let customOriginYKey = "OpenFlowOverlayCustomOriginY"
  // The panel is sized larger than the visible pill so SwiftUI's drop shadow
  // (radius 12, y-offset 4) has room to render without being clipped by the
  // window's contentRect — especially around the capsule's rounded ends, where
  // the shadow extends furthest from the pill body.
  static let pillSize = CGSize(width: 120, height: 28)
  static let shadowMargin: CGFloat = 16
  private static let panelSize = CGSize(
    width: pillSize.width + shadowMargin * 2,
    height: pillSize.height + shadowMargin * 2)

  private let panel: NSPanel
  private let hosting: NSHostingView<OverlayHost>
  private let bridge = OverlayBridge()
  private var suppressOriginPersist = false

  init() {
    let host = OverlayHost(bridge: bridge)
    self.hosting = NSHostingView(rootView: host)
    self.hosting.wantsLayer = true
    self.hosting.layer?.backgroundColor = .clear
    self.panel = FloatingPanel.make(
      size: Self.panelSize,
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

  func show(state: OverlayUIState) {
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

  func pushLevel(_ value: Float) {
    bridge.pushLevel(value)
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
        y: screen.visibleFrame.minY + 80 - Self.shadowMargin)
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
