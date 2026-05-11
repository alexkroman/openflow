import AVFoundation
import AppKit
import ApplicationServices
import Foundation

public struct PermissionStatus: Equatable, Sendable {
  public let microphone: Bool
  public let accessibility: Bool

  public init(microphone: Bool, accessibility: Bool) {
    self.microphone = microphone
    self.accessibility = accessibility
  }

  public var allGranted: Bool { microphone && accessibility }
}

public enum PermissionsChecker {
  public static func check() -> PermissionStatus {
    PermissionStatus(
      microphone: micGranted(),
      accessibility: AXIsProcessTrusted()
    )
  }

  private static func micGranted() -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return true
    default: return false
    }
  }

  public static func requestMicrophone() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .audio)
  }

  /// Trigger the Accessibility permission flow:
  /// 1. Make a *real* AX-protected call against another app's UI tree —
  ///    this is what reliably registers OpenFlow in TCC on macOS 26.
  ///    `AXIsProcessTrustedWithOptions` and the system-wide query don't
  ///    appear to count as "activity" for registration purposes.
  /// 2. Show the trust prompt with an "Open System Settings" button.
  @MainActor
  public static func openAccessibilitySettings() {
    forceAccessibilityActivity()
    let prompt: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
    _ = AXIsProcessTrustedWithOptions(prompt)
  }

  /// Kept as a no-prompt nudge — same protected-call body as
  /// `openAccessibilitySettings`'s first step. Best-effort.
  @MainActor
  public static func registerForAccessibilityTCC() {
    forceAccessibilityActivity()
  }

  @MainActor
  private static func forceAccessibilityActivity() {
    // AX reads against our own pid are NOT TCC-protected — apps can always
    // read their own UI. We must target a different process so tccd sees
    // a denied request and registers OpenFlow in the Accessibility list.
    // `frontmostApplication` is OpenFlow itself when this runs from a
    // button in our own window, which is why prior versions never worked.
    let myPid = ProcessInfo.processInfo.processIdentifier
    let others = NSWorkspace.shared.runningApplications.filter {
      $0.processIdentifier > 0 && $0.processIdentifier != myPid
    }
    let target =
      others.first(where: { $0.bundleIdentifier == "com.apple.finder" })
      ?? others.first(where: { $0.activationPolicy == .regular })
      ?? others.first
    guard let pid = target?.processIdentifier else { return }
    let element = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(
      element, kAXFocusedUIElementAttribute as CFString, &value)
  }

  @MainActor
  public static func openMicrophoneSettings() {
    openPrivacyPane(suffix: "Privacy_Microphone")
  }

  @MainActor
  private static func openPrivacyPane(suffix: String) {
    // The x-apple.systempreferences URL scheme is unreliable on macOS 26;
    // AppleScript's "reveal anchor" is the path that actually works.
    let pane = "com.apple.settings.PrivacySecurity.extension"
    let source = """
      tell application "System Settings"
        activate
        reveal anchor "\(suffix)" of pane id "\(pane)"
      end tell
      """
    if let script = NSAppleScript(source: source) {
      var error: NSDictionary?
      script.executeAndReturnError(&error)
      if error == nil { return }
    }
    legacyOpenPrivacyPane(suffix: suffix)
  }

  @MainActor
  private static func legacyOpenPrivacyPane(suffix: String) {
    let modern = URL(
      string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(suffix)")!
    let legacy = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?\(suffix)")!
    if !NSWorkspace.shared.open(modern) {
      _ = NSWorkspace.shared.open(legacy)
    }
  }
}
