import Testing

@testable import OpenFlowEngine

private struct FakeReadiness: ModelReadiness {
  let isReady: Bool
}

@Suite("WizardStep.evaluate")
struct WizardStepTests {
  @Test("permissions missing returns .permissions")
  func permissionsMissing() {
    let perms = PermissionStatus(microphone: false, accessibility: false)
    let step = WizardStep.evaluate(permissions: perms, modelState: FakeReadiness(isReady: false))
    #expect(step == .permissions)
  }

  @Test("only microphone granted still returns .permissions")
  func onlyMicGranted() {
    let perms = PermissionStatus(microphone: true, accessibility: false)
    let step = WizardStep.evaluate(permissions: perms, modelState: FakeReadiness(isReady: true))
    #expect(step == .permissions)
  }

  @Test("only accessibility granted still returns .permissions")
  func onlyAxGranted() {
    let perms = PermissionStatus(microphone: false, accessibility: true)
    let step = WizardStep.evaluate(permissions: perms, modelState: FakeReadiness(isReady: true))
    #expect(step == .permissions)
  }

  @Test("permissions OK and models not ready returns .settingUp")
  func modelsNotReady() {
    let perms = PermissionStatus(microphone: true, accessibility: true)
    let step = WizardStep.evaluate(permissions: perms, modelState: FakeReadiness(isReady: false))
    #expect(step == .settingUp)
  }

  @Test("permissions OK and models ready returns .hotkey")
  func everythingReady() {
    let perms = PermissionStatus(microphone: true, accessibility: true)
    let step = WizardStep.evaluate(permissions: perms, modelState: FakeReadiness(isReady: true))
    #expect(step == .hotkey)
  }
}
