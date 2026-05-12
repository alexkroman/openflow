import Combine
import Foundation
import OpenFlowEngine

@MainActor
final class WizardController: ObservableObject {
  @Published private(set) var step: WizardStep
  @Published private(set) var permissions: PermissionStatus

  private weak var coordinator: AppCoordinator?
  private var pollTask: Task<Void, Never>?
  private var modelLoadObserver: AnyCancellable?
  private var hasKickedOffModelLoad = false

  init(coordinator: AppCoordinator) {
    self.coordinator = coordinator
    let perms = PermissionsChecker.check()
    self.permissions = perms
    self.step = WizardStep.evaluate(
      permissions: perms,
      modelState: coordinator.modelLoadState
    )
    self.modelLoadObserver = coordinator.$modelLoadState
      .sink { [weak self] newState in
        Task { @MainActor in self?.recompute(modelState: newState) }
      }
    if step == .settingUp {
      kickOffModelLoadIfNeeded()
    }
  }

  /// Called by the wizard window when it becomes visible.
  func startPolling() {
    pollTask?.cancel()
    pollTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self else { return }
        self.recompute(permissions: PermissionsChecker.check())
      }
    }
  }

  /// Called by the wizard window when it closes.
  func stopPolling() {
    pollTask?.cancel()
    pollTask = nil
  }

  /// One-shot fallback for the "Continue" button on the Permissions step.
  func continueFromPermissions() {
    recompute(permissions: PermissionsChecker.check())
  }

  /// Re-evaluates the step from current state and triggers side effects.
  private func recompute(
    permissions: PermissionStatus? = nil,
    modelState: ModelLoadState? = nil
  ) {
    let perms = permissions ?? self.permissions
    let models = modelState ?? coordinator?.modelLoadState ?? ModelLoadState()
    self.permissions = perms
    let newStep = WizardStep.evaluate(permissions: perms, modelState: models)
    if newStep != self.step {
      self.step = newStep
    }
    if newStep == .settingUp {
      kickOffModelLoadIfNeeded()
    }
  }

  private func kickOffModelLoadIfNeeded() {
    guard !hasKickedOffModelLoad, let coordinator else { return }
    hasKickedOffModelLoad = true
    coordinator.beginModelLoad()
  }
}
