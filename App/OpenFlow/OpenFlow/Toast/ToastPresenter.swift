import AppKit
import SwiftUI

@MainActor
final class ToastPresenter {
  private var window: NSPanel?
  private var dismissTask: Task<Void, Never>?

  func show(_ message: String, durationSeconds: Double = 2.5) {
    dismissTask?.cancel()
    let host = NSHostingController(rootView: ToastView(text: message))
    let p = FloatingPanel.make(
      size: CGSize(width: 320, height: 44),
      collectionBehavior: [.canJoinAllSpaces, .stationary],
      contentViewController: host
    )

    if let screen = NSScreen.main {
      let frame = p.frame
      p.setFrameOrigin(
        NSPoint(
          x: screen.visibleFrame.midX - frame.width / 2,
          y: screen.visibleFrame.maxY - 100
        ))
    }
    p.orderFrontRegardless()
    self.window?.orderOut(nil)
    self.window = p

    dismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(durationSeconds))
      await MainActor.run { [weak self] in
        self?.window?.orderOut(nil)
        self?.window = nil
      }
    }
  }
}

private struct ToastView: View {
  let text: String
  var body: some View {
    Text(text)
      .padding(.horizontal, 14).padding(.vertical, 10)
      .background(.regularMaterial, in: Capsule())
  }
}
