import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import os

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
  // Subsystem matches the rest of the engine (see MicCapture). Tail with:
  //   log show --predicate 'subsystem == "dev.alex.OpenFlow"
  //                         AND category == "Permissions"' --last 5m
  private static let logger = Logger(subsystem: "dev.alex.OpenFlow", category: "Permissions")

  public static func check() -> PermissionStatus {
    PermissionStatus(
      microphone: micGranted(),
      accessibility: AXIsProcessTrusted()
    )
  }

  public static func micGranted() -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return true
    default: return false
    }
  }

  public static func requestMicrophone() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .audio)
  }

  /// Show the standard Accessibility permission prompt. Calling
  /// `AXIsProcessTrustedWithOptions` with the prompt option is the only
  /// thing that gets tccd to write a `kTCCServiceAccessibility` row for
  /// this bundle on macOS 26 — passive checks (`AXIsProcessTrusted`,
  /// `AXIsProcessTrustedWithOptions(nil)`) all return `DB Action:None`
  /// from tccd and leave the app unlisted in System Settings.
  @MainActor
  public static func openAccessibilitySettings() {
    // The exported `kAXTrustedCheckOptionPrompt` is a non-Sendable C global
    // under Swift 6; using the documented literal value avoids the warning.
    let prompt: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
    let trusted = AXIsProcessTrustedWithOptions(prompt)
    logger.info("openAccessibilitySettings prompt-call trusted=\(trusted)")
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
