import AppKit
import Foundation

public struct CapturedFocus: Sendable {
  public let pid: pid_t
  public let bundleIdentifier: String?
  public let processName: String?

  public init(pid: pid_t, bundleIdentifier: String?, processName: String?) {
    self.pid = pid
    self.bundleIdentifier = bundleIdentifier
    self.processName = processName
  }
}

public enum FocusCapture {
  @MainActor
  public static func captureFrontmost() -> CapturedFocus? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    return CapturedFocus(
      pid: app.processIdentifier,
      bundleIdentifier: app.bundleIdentifier,
      processName: app.localizedName
    )
  }

  public static func runningApp(for captured: CapturedFocus) -> NSRunningApplication? {
    NSRunningApplication(processIdentifier: captured.pid)
  }
}
