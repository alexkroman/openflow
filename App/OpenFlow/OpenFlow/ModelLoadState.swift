import Foundation

struct ModelLoadState: Sendable, Equatable {
  var stt: ChannelStatus = .checking
  var llm: ChannelStatus = .checking

  var isReady: Bool { stt == .loaded && llm == .loaded }
}

enum ChannelStatus: Sendable, Equatable {
  case checking
  case downloading(fraction: Double)
  case loading
  case loaded
  case failed(message: String)
}
