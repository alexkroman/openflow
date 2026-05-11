import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let dictate = Self(
    "dictate",
    default: .init(.d, modifiers: [.control, .option])
  )
}

@MainActor
enum DictateHotkey {
  /// Display label for the currently bound shortcut, e.g. "⌃⌥D".
  /// Falls back to "—" if the user has cleared it.
  static var label: String {
    KeyboardShortcuts.getShortcut(for: .dictate)?.description ?? "—"
  }
}
