import AppKit
import Foundation

public protocol InjectorProtocol: Sendable {
  func setTargetApp(_ app: NSRunningApplication?) async
  /// Insert text into whatever the OS currently treats as the focus target.
  func insert(_ text: String) async throws
}

extension InjectorProtocol {
  public func setTargetApp(_ app: NSRunningApplication?) async {}
}
