import Foundation
import Testing

@testable import OpenFlowEngine

@Suite("MLXStyler adapter")
struct MLXStylerAdapterTests {
  @Test("Config defaults match documented values")
  func configDefaults() {
    let c = MLXStyler.Config()
    #expect(c.maxTokens == 512)
    #expect(abs(c.temperature - 0.2) < 0.001)
  }

  @Test("Config custom values pass through")
  func configCustom() {
    let c = MLXStyler.Config(maxTokens: 128, temperature: 0.0)
    #expect(c.maxTokens == 128)
    #expect(c.temperature == 0.0)
  }
}
