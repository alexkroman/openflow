import SwiftUI
import TinyAudio

struct ModelLoadSection: View {
  let state: ModelLoadState
  let retrySTT: () -> Void
  let retryLLM: () -> Void

  var body: some View {
    Section {
      ModelLoadRow(label: "Speech recognition model", status: state.stt, retry: retrySTT)
      ModelLoadRow(label: "Language model", status: state.llm, retry: retryLLM)
    } header: {
      Text("Setting up")
    } footer: {
      Text("Downloaded once, then cached under ~/Library/Application Support/TinyAudio.")
        .foregroundStyle(.secondary)
    }
  }
}

private struct ModelLoadRow: View {
  let label: String
  let status: ChannelStatus
  let retry: () -> Void

  var body: some View {
    HStack {
      Text(label)
      Spacer()
      statusView
    }
  }

  @ViewBuilder
  private var statusView: some View {
    switch status {
    case .progress(let p):
      progressView(for: p)
    case .loaded:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
      Text("Ready").foregroundStyle(.secondary)
    case .failed(let message):
      Text(message).foregroundStyle(.red).lineLimit(1)
      Button("Retry", action: retry)
    }
  }

  @ViewBuilder
  private func progressView(for p: TinyAudio.LoadProgress) -> some View {
    switch p {
    case .checking:
      Text("Checking cache").foregroundStyle(.secondary)
    case .downloading(let fraction):
      ProgressView(value: fraction).frame(width: 160)
      Text("\(Int(fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
    case .loading:
      ProgressView().controlSize(.small)
    }
  }
}
