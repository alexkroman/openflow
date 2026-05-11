import AppKit
import CoreGraphics
import Foundation

public actor KeyInjector: InjectorProtocol {
  public struct Config: Sendable {
    public var longTextThreshold: Int
    public var keystrokePacingMicros: UInt32
    public init(longTextThreshold: Int = 500, keystrokePacingMicros: UInt32 = 1_000) {
      self.longTextThreshold = longTextThreshold
      self.keystrokePacingMicros = keystrokePacingMicros
    }
  }

  private var config: Config
  private var targetApp: NSRunningApplication?

  public init(config: Config = Config()) {
    self.config = config
  }

  public func setTargetApp(_ app: NSRunningApplication?) {
    self.targetApp = app
  }

  public func updateConfig(_ config: Config) {
    self.config = config
  }

  public nonisolated func insert(_ text: String) async throws {
    guard !text.isEmpty else { return }
    let cfg = await self.config
    let path = InjectionPath.choose(for: text, longTextThreshold: cfg.longTextThreshold)
    if let target = await self.targetApp {
      target.activate()
      try? await Task.sleep(nanoseconds: 30_000_000)
    }
    switch path {
    case .typeKeystrokes:
      await self.typeKeystrokes(text)
    case .clipboardPaste:
      await self.clipboardPaste(text)
    }
  }

  private func typeKeystrokes(_ text: String) {
    let pacing = config.keystrokePacingMicros
    let source = CGEventSource(stateID: .combinedSessionState)
    for scalar in text.unicodeScalars {
      postUnicode(scalar, source: source)
      usleep(pacing)
    }
  }

  private func postUnicode(_ scalar: Unicode.Scalar, source: CGEventSource?) {
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else { return }
    var utf16 = Array(String(scalar).utf16)
    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
    // (do NOT set the unicode string on keyUp — causes double-insert in some apps)
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
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
