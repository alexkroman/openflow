import AppKit
import SwiftUI

@MainActor
final class OverlayBridge: ObservableObject {
  static let waveformBarCount = 21

  @Published var state: OverlayUIState = .idle
  @Published var recordingMode: RecordingMode = .pushToTalk
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
    OverlayView(
      state: bridge.state,
      recordingMode: bridge.recordingMode,
      levels: bridge.levels,
      holdHotkeySpelled: DictateHotkey.holdSpelledOut,
      tapHotkeySpelled: DictateHotkey.tapSpelledOut
    )
  }
}

@MainActor
final class OverlayWindowController {
  private static let customOriginXKey = "OpenFlowOverlayCustomOriginX"
  private static let customOriginYKey = "OpenFlowOverlayCustomOriginY"
  // The panel is sized to the pill's *largest* visible footprint (the
  // expanded info card with both hotkeys spelled out) plus a margin for the
  // drop shadow. Keeping the panel a constant size avoids window-resize
  // jitter when the SwiftUI view animates between compact and expanded
  // states. shadowMargin must stay comfortably larger than the shadow's
  // (radius + |y|) so the shadow isn't clipped at any edge.
  static let pillSize = CGSize(width: 130, height: 50)
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

  /// Records which hotkey is responsible for the upcoming/current session.
  /// Should be set before `session.press()` so the overlay's recording-card
  /// stop hint reflects the gesture the user just made.
  func setRecordingMode(_ mode: RecordingMode) {
    bridge.recordingMode = mode
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
    // A `pillSize` increase between app versions can leave a stored origin
    // that no longer keeps the (now wider/taller) panel on-screen; clamp()
    // pulls it back into the visible frame, which manifests as the pill
    // visibly shifting from where the user last dragged it. Accepted —
    // users can re-drag.
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
