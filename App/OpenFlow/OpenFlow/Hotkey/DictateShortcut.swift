import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let dictate = Self(
    "dictate",
    default: .init(.d, modifiers: [.control, .option])
  )
  static let handsFree = Self(
    "handsFree",
    default: .init(.h, modifiers: [.control, .option])
  )
}

@MainActor
enum DictateHotkey {
  /// Compact glyph label, e.g. "⌃⌥D". Falls back to "—" if cleared.
  static var holdLabel: String { glyphLabel(.dictate) }
  /// Compact glyph label for the hands-free hotkey, e.g. "⌃⌥H".
  static var tapLabel: String { glyphLabel(.handsFree) }

  /// Spelled-out form, e.g. "Ctrl+Opt+D". Used in the overlay info card.
  static var holdSpelledOut: String { spelledLabel(.dictate) }
  /// Spelled-out form of the hands-free hotkey, e.g. "Ctrl+Opt+H".
  static var tapSpelledOut: String { spelledLabel(.handsFree) }

  private static func glyphLabel(_ name: KeyboardShortcuts.Name) -> String {
    KeyboardShortcuts.getShortcut(for: name)?.description ?? "—"
  }

  private static func spelledLabel(_ name: KeyboardShortcuts.Name) -> String {
    guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return "—" }
    var parts: [String] = []
    let mods = shortcut.modifiers
    if mods.contains(.control) { parts.append("Ctrl") }
    if mods.contains(.option) { parts.append("Opt") }
    if mods.contains(.shift) { parts.append("Shift") }
    if mods.contains(.command) { parts.append("Cmd") }
    // KeyboardShortcuts.Key is a struct (wraps a Carbon virtual keycode),
    // not an enum — String(describing:) produces useless struct debug
    // output. nsMenuItemKeyEquivalent yields the actual character ("h" for
    // the H key, special-key glyph for arrows/return/etc.) or nil for keys
    // that can't be expressed as a menu equivalent.
    if let keyStr = shortcut.nsMenuItemKeyEquivalent {
      parts.append(keyStr.uppercased())
    }
    return parts.joined(separator: "+")
  }
}
