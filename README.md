# OpenFlow

A macOS dictation app — hold Right Option, speak, get cleaned-up text typed
into whatever app you're using. Fully on-device: speech-to-text via
[`tiny-audio-swift`](../tiny-audio-swift) (a sibling clone in your `~/Code/`
directory), cleanup styling via an MLX-based LLM (Qwen3.5-2B-OptiQ-4bit).

## Download

[Download OpenFlow (latest, DMG)](https://github.com/alexkroman/openflow/releases/latest/download/OpenFlow.dmg)

## Build

Requirements:
- macOS 14+, Apple Silicon
- Xcode 16+ (Swift 6 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A clone of `tiny-audio-swift` at `../tiny-audio-swift` (sibling to this repo)

```bash
swift test                                  # engine unit tests
cd App/OpenFlow && xcodegen generate        # generate xcodeproj
xcodebuild -project App/OpenFlow/OpenFlow.xcodeproj \
  -scheme OpenFlow -configuration Debug \
  -derivedDataPath /tmp/openflow-build build
open /tmp/openflow-build/Build/Products/Debug/OpenFlow.app
```

On first launch:
1. Grant Microphone, Accessibility, and Input Monitoring permissions in the
   Setup window.
2. Click "Download (~1.4 GB)" to pre-download the LLM model.
3. Open any text app and hold Right Option to dictate.

## Layout

- `Sources/OpenFlowEngine/` — engine package (pipeline, STT, LLM, hotkey, injection)
- `Tests/OpenFlowEngineTests/` — engine unit tests (21 tests across 5 suites)
- `App/OpenFlow/` — AppKit shell (status item, overlay, settings, setup)
- `App/SMOKE.md` — manual smoke checklist
- `docs/superpowers/specs/` — design spec
- `docs/superpowers/plans/` — implementation plan

## Architecture

A local Swift package `OpenFlowEngine` owns the dictation pipeline behind
protocol seams. A thin AppKit shell wires it to a menu-bar status item, a
floating overlay, a Settings window, and a first-run Setup window.

```
HotkeyWatcher → DictationSession → MicCapture
                       ↓
              TinyAudioTranscriber  (STT)
                       ↓
              SafeguardedStyler → MLXStyler  (LLM)
                       ↓
              KeyInjector → focused app
```

Pipeline phases: `idle → recording → transcribing → styling → injecting → idle`.
Cancel and failure are transitions out of any active phase.
