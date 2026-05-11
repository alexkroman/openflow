import AppKit
import OpenFlowEngine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
  private let onShowSetup: () -> Void
  private let onQuit: () -> Void
  private let item: NSStatusItem
  private let phaseItem = NSMenuItem()
  private var iconState: IconState = .idle

  private enum IconState { case idle, recording, processing, error }

  init(
    onShowSetup: @escaping () -> Void,
    onQuit: @escaping () -> Void
  ) {
    self.onShowSetup = onShowSetup
    self.onQuit = onQuit
    self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    // Notch escape hatch: autosaveName persists visibility across launches,
    // and .removalAllowed lets the user ⌘-drag the icon out (and any third-party
    // menu-bar manager re-show it) when the notch overflow swallows it.
    item.autosaveName = "OpenFlowStatusItem"
    item.behavior = [.removalAllowed]

    let menu = NSMenu()
    menu.delegate = self
    menu.autoenablesItems = false
    item.menu = menu
    buildMenu(menu)
    refreshIcon()
  }

  func update(phase: PipelinePhase) {
    switch phase {
    case .recording: iconState = .recording
    case .transcribing, .styling: iconState = .processing
    case .failed: iconState = .error
    case .idle, .injecting, .cancelled: iconState = .idle
    }
    refreshIcon()
    refreshPhaseLabel(phase: phase)
  }

  private func buildMenu(_ menu: NSMenu) {
    phaseItem.title = "Idle"
    phaseItem.isEnabled = false
    menu.addItem(phaseItem)
    menu.addItem(.separator())

    let setup = NSMenuItem(
      title: "Open Setup…", action: #selector(showSetup), keyEquivalent: ",")
    setup.target = self
    menu.addItem(setup)
    menu.addItem(.separator())

    let quit = NSMenuItem(
      title: "Quit OpenFlow", action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {}

  private func refreshIcon() {
    guard let button = item.button else { return }
    let symbolName: String
    switch iconState {
    case .idle: symbolName = "mic"
    case .recording: symbolName = "mic.fill"
    case .processing: symbolName = "waveform"
    case .error: symbolName = "exclamationmark.circle"
    }
    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "OpenFlow")
    image?.isTemplate = true
    button.image = image
  }

  private func refreshPhaseLabel(phase: PipelinePhase) {
    let title: String
    switch phase {
    case .idle, .cancelled, .injecting: title = "Idle"
    case .recording: title = "Recording…"
    case .transcribing: title = "Transcribing…"
    case .styling: title = "Cleaning up…"
    case .failed(let err): title = err.errorDescription ?? "Error"
    }
    phaseItem.title = title
  }

  @objc private func showSetup() {
    onShowSetup()
  }

  @objc private func quit() {
    onQuit()
  }
}
