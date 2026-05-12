import AppKit
import CoreGraphics
import Foundation

public actor KeyInjector: InjectorProtocol {
  private var targetApp: NSRunningApplication?

  public init() {}

  public static func withTrailingSpace(_ text: String) -> String {
    guard !text.isEmpty else { return text }
    guard let last = text.last, last.isWhitespace else { return text + " " }
    return text
  }

  public func setTargetApp(_ app: NSRunningApplication?) {
    targetApp = app
  }

  public nonisolated func insert(_ text: String) async throws {
    guard !text.isEmpty else { return }
    let finalText = KeyInjector.withTrailingSpace(text)
    if let target = await targetApp {
      target.activate()
      try? await Task.sleep(nanoseconds: 30_000_000)
    }
    await clipboardPaste(finalText)
  }

  private func clipboardPaste(_ text: String) async {
    let pb = NSPasteboard.general
    var savedItems: [NSPasteboardItem] = []
    if let items = pb.pasteboardItems {
      for item in items {
        let copy = NSPasteboardItem()
        for type in item.types {
          if let data = item.data(forType: type) {
            copy.setData(data, forType: type)
          }
        }
        savedItems.append(copy)
      }
    }
    pb.clearContents()
    pb.setString(text, forType: .string)
    postCmdV()
    try? await Task.sleep(nanoseconds: 200_000_000)
    pb.clearContents()
    if !savedItems.isEmpty { pb.writeObjects(savedItems) }
  }

  private func postCmdV() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let vKey: CGKeyCode = 0x09  // kVK_ANSI_V
    let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
  }
}
