import Foundation

/// Event emitted by a styler. `.delta` appends to accumulated styled text;
/// `.replaceAll` clears the accumulator and uses the provided text instead.
public enum StylerEvent: Sendable, Equatable {
  case delta(String)
  case replaceAll(String)
}

public protocol StylerProtocol: Sendable {
  /// Style a raw transcript. Yielded events drive the consumer's accumulator.
  func style(_ raw: String) -> AsyncThrowingStream<StylerEvent, Error>
}
