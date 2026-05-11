import Foundation
import MLXLLM
import MLXLMCommon

public actor MLXStyler: StylerProtocol {
  public struct Config: Sendable {
    /// Folder name inside the host app's bundle Resources/ that contains the
    /// MLX-converted model files (config.json, tokenizer.json, *.safetensors).
    public let bundledModelFolder: String
    public let maxTokens: Int
    public let temperature: Float
    public init(
      bundledModelFolder: String = "Models/Qwen3.5-2B-OptiQ-4bit",
      maxTokens: Int = 512,
      temperature: Float = 0.2
    ) {
      self.bundledModelFolder = bundledModelFolder
      self.maxTokens = maxTokens
      self.temperature = temperature
    }
  }

  private let config: Config
  private let modelURLOverride: URL?
  private var container: ModelContainer?
  private var primerCacheURL: URL?

  public init(config: Config = Config()) {
    self.config = config
    self.modelURLOverride = nil
  }

  /// Init with an absolute model directory URL. Used by CLI test harnesses
  /// that don't load the model from the host app bundle.
  public init(modelURL: URL, config: Config = Config()) {
    self.config = config
    self.modelURLOverride = modelURL
  }

  /// Load the bundled model from the host app's Bundle.main resources, then
  /// pre-build a KV cache containing the styling system prompt. Per-turn
  /// `style()` calls reload that cache from disk and skip the ~700-token
  /// system-prompt prefill they would otherwise pay every dictation.
  /// First call may take a few seconds (MLX kernel JIT + weight load + primer
  /// turn). Subsequent calls are no-ops.
  public func warmUp() async throws {
    if container != nil { return }
    do {
      guard let modelURL = bundledModelURL() else {
        throw OpenFlowError.modelLoadFailed(
          underlying: NSError(
            domain: "OpenFlow",
            code: -1,
            userInfo: [
              NSLocalizedDescriptionKey:
                "Bundled model not found in app Resources. Run scripts/fetch-model.sh and rebuild."
            ]))
      }
      let modelConfiguration = ModelConfiguration(directory: modelURL)
      let container = try await LLMModelFactory.shared.loadContainer(
        configuration: modelConfiguration
      )
      self.container = container
      self.primerCacheURL = try? await Self.buildPrimerCache(container: container)
    } catch let e as OpenFlowError {
      throw e
    } catch {
      throw OpenFlowError.modelLoadFailed(underlying: error)
    }
  }

  /// Whether the bundled model exists in Resources/. Used by Setup UI.
  public nonisolated func isBundledModelPresent() -> Bool {
    bundledModelURL() != nil
  }

  private nonisolated func bundledModelURL() -> URL? {
    if let override = modelURLOverride {
      let configFile = override.appendingPathComponent("config.json")
      return FileManager.default.fileExists(atPath: configFile.path) ? override : nil
    }
    // Bundle.main.resourceURL points to the .app/Contents/Resources directory.
    guard let base = Bundle.main.resourceURL else { return nil }
    let url = base.appendingPathComponent(config.bundledModelFolder, isDirectory: true)
    let configFile = url.appendingPathComponent("config.json")
    return FileManager.default.fileExists(atPath: configFile.path) ? url : nil
  }

  /// Run one tiny throwaway turn to materialize the system-prompt KV state,
  /// then snapshot it to a file in the temp dir. The primer prompt is the
  /// same empty-transcript shape that the system prompt explicitly handles
  /// (`<transcript></transcript>` → empty output), so the primer turn left
  /// in cache is consistent with the prompt's rules and shouldn't bias
  /// later turns.
  private static func buildPrimerCache(container: ModelContainer) async throws -> URL {
    let primer = ChatSession(
      container,
      instructions: StylingPrompt.system,
      generateParameters: GenerateParameters(maxTokens: 4, temperature: 0.0)
    )
    _ = try await primer.respond(to: StylingPrompt.userMessage(for: ""))
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("openflow-styler-primer-\(UUID().uuidString).safetensors")
    try await primer.saveCache(to: url)
    return url
  }

  public nonisolated func style(_ raw: String) -> AsyncThrowingStream<StylerEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          try await self.warmUp()
          guard let container = await self.container else {
            continuation.finish(
              throwing: OpenFlowError.modelLoadFailed(
                underlying: NSError(domain: "OpenFlow", code: -1)))
            return
          }
          let cfg = self.config
          let tokenLimit = min(cfg.maxTokens, max(64, Int(Double(raw.count) * 1.5)))
          let parameters = GenerateParameters(
            maxTokens: tokenLimit, temperature: cfg.temperature)

          // Resume from the prefilled system-prompt cache when available;
          // fall back to fresh prefill if it isn't ready (warmUp failed or
          // primer save failed). With the cache, only the user transcript
          // gets prefilled per turn.
          let session: ChatSession
          if let url = await self.primerCacheURL,
            let (cache, _) = try? loadPromptCache(url: url) {
            session = ChatSession(container, cache: cache, generateParameters: parameters)
          } else {
            session = ChatSession(
              container, instructions: StylingPrompt.system,
              generateParameters: parameters)
          }

          let userText = StylingPrompt.userMessage(for: raw)
          for try await chunk in session.streamResponse(to: userText) {
            if Task.isCancelled {
              continuation.finish()
              return
            }
            continuation.yield(.delta(chunk))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: OpenFlowError.stylerFailed(underlying: error))
        }
      }
    }
  }
}
