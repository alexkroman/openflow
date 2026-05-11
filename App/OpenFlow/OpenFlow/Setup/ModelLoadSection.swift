import OpenFlowEngine
import SwiftUI
import TinyAudio

struct ModelLoadSection: View {
  let state: ModelLoadState
  let retrySTT: () -> Void
  let retryLLM: () -> Void

  var body: some View {
    Section {
      ModelLoadRow(
        label: "Speech recognition model",
        progress: sttProgress,
        error: sttError,
        retry: retrySTT
      )
      ModelLoadRow(
        label: "Language model",
        progress: llmProgress,
        error: llmError,
        retry: retryLLM
      )
    } header: {
      Text("Setting up")
    } footer: {
      Text("Downloaded once, then cached under ~/Library/Application Support/TinyAudio.")
        .foregroundStyle(.secondary)
    }
  }

  private var sttProgress: TinyAudio.LoadProgress? {
    switch state {
    case .loading(let stt, _): return stt
    case .ready: return .loading
    default: return nil
    }
  }
  private var llmProgress: TinyAudio.LoadProgress? {
    switch state {
    case .loading(_, let llm): return llm
    case .ready: return .loading
    default: return nil
    }
  }
  private var sttError: Error? {
    if case .failed(let stt, _) = state { return stt } else { return nil }
  }
  private var llmError: Error? {
    if case .failed(_, let llm) = state { return llm } else { return nil }
  }
}

private struct ModelLoadRow: View {
  let label: String
  let progress: TinyAudio.LoadProgress?
  let error: Error?
  let retry: () -> Void

  var body: some View {
    HStack {
      Text(label)
      Spacer()
      if let error {
        Text(error.localizedDescription)
          .foregroundStyle(.red)
          .lineLimit(1)
        Button("Retry", action: retry)
      } else if let progress {
        progressView(for: progress)
      } else {
        Text("Pending")
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func progressView(for p: TinyAudio.LoadProgress) -> some View {
    switch p {
    case .checking:
      Text("Checking cache")
        .foregroundStyle(.secondary)
    case .downloading(let fraction):
      ProgressView(value: fraction).frame(width: 160)
      Text("\(Int(fraction * 100))%")
        .monospacedDigit()
        .foregroundStyle(.secondary)
    case .loading:
      ProgressView()
        .controlSize(.small)
    }
  }
}
