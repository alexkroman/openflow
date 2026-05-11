import AppKit

@MainActor
enum FloatingPanel {
  static func make(
    size: CGSize,
    collectionBehavior: NSWindow.CollectionBehavior,
    contentViewController: NSViewController? = nil,
    contentView: NSView? = nil
  ) -> NSPanel {
    let p = NSPanel(
      contentRect: .init(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    p.isOpaque = false
    p.backgroundColor = .clear
    p.level = .floating
    p.collectionBehavior = collectionBehavior
    p.hidesOnDeactivate = false
    if let contentViewController {
      p.contentViewController = contentViewController
    } else if let contentView {
      p.contentView = contentView
    }
    return p
  }
}
