import Foundation

/// Minimal readiness signal for the wizard. Conformers report whether the
/// on-device models are loaded and the dictation pipeline is usable.
public protocol ModelReadiness {
  var isReady: Bool { get }
}

public enum WizardStep: Equatable, Sendable {
  case permissions
  case settingUp
  case hotkey

  public static func evaluate(
    permissions: PermissionStatus,
    modelState: ModelReadiness
  ) -> WizardStep {
    if !permissions.allGranted { return .permissions }
    if !modelState.isReady     { return .settingUp }
    return .hotkey
  }
}
