import Foundation

public enum InjectionPath: Equatable, Sendable {
  case typeKeystrokes
  case clipboardPaste

  public static func choose(for text: String, longTextThreshold: Int) -> InjectionPath {
    text.count > longTextThreshold ? .clipboardPaste : .typeKeystrokes
  }
}
