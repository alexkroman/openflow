import KeyboardShortcuts
import SwiftUI

struct HotkeyStepView: View {
  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      Form {
        shortcutSection
        tipsSection
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage ?? NSImage())
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text("OpenFlow").font(.title).bold()
        Text("Hold the shortcut anywhere on your Mac and start dictating.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(28)
  }

  private var shortcutSection: some View {
    Section {
      LabeledContent {
        KeyboardShortcuts.Recorder(for: .dictate)
      } label: {
        Label("Hold to dictate", systemImage: "keyboard")
      }
    } header: {
      Text("Shortcut")
    } footer: {
      Text("Pick any key+modifier combo. Defaults to ⌃⌥D.")
    }
  }

  private var tipsSection: some View {
    Section {
      Label(
        "Speech is transcribed and cleaned up locally on this device.",
        systemImage: "lock.shield"
      )
    } header: {
      Text("Tips")
    }
  }
}
