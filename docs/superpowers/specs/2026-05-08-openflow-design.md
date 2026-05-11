# OpenFlow — Design Spec

**Date:** 2026-05-08
**Status:** Approved (brainstorming)
**Author:** Alex Kroman

## 1. Goal

Build a macOS dictation app — a WisprFlow competitor — that lets the user hold a global hotkey, speak into any app, and have the cleaned-up transcription typed into the focused text field. STT and LLM both run fully on-device.

**Non-goals (v1):** iOS support, cloud backends, custom user vocabulary, tone presets, context-aware styling, App Store distribution, sharing the app with other users (no signing/notarization).

## 2. Scope

### In scope
- Hold-to-talk global hotkey (default: Right Option), configurable in settings.
- Local STT via the existing `tiny-audio-swift` Swift package (`Transcriber`).
- LLM-based cleanup styling (filler removal, punctuation, capitalization, false-start fixing) via `mlx-swift-lm`, model `mlx-community/Qwen3-4B-Instruct-2507-4bit`.
- Floating overlay near the cursor showing pipeline state and streaming styled text.
- Keystroke synthesis into the focused app via `CGEventPost` + `keyboardSetUnicodeString`; clipboard-paste fallback for long text.
- Menu-bar-only app shell (`LSUIElement=YES`).
- First-run setup flow for permissions and model download.

### Out of scope
- Tone presets, custom user instructions, custom vocabulary.
- Per-app context-aware prompts.
- Live-stream styled tokens directly into the target app.
- Notarized/signed distribution.

## 3. Architecture

### Project layout

```
~/Code/openflow/
├── Package.swift                  # SwiftPM workspace root
├── Sources/
│   └── OpenFlowEngine/            # Local Swift package — the brain
│       ├── Pipeline/              # DictationSession actor + state machine
│       ├── STT/                   # TinyAudio wrapper (TranscriberProtocol)
│       ├── LLM/                   # MLX model loader + Styler (StylerProtocol)
│       ├── Hotkey/                # CGEventTap-based push-to-talk watcher
│       ├── Injection/             # CGEvent keystroke synthesizer
│       ├── Audio/                 # AVAudioEngine mic capture
│       └── Permissions/           # Accessibility / mic / input-monitoring helpers
├── Tests/
│   └── OpenFlowEngineTests/
└── App/
    └── OpenFlow.xcodeproj         # Thin AppKit shell
        ├── AppDelegate
        ├── StatusItemController   # Menu-bar icon + menu
        ├── OverlayWindow          # NSPanel near cursor
        ├── SettingsWindow
        ├── SetupWindow            # First-run guided checklist
        └── Info.plist             # NSMicrophoneUsageDescription, LSUIElement=YES
```

### Why a package + thin app

The engine is the interesting logic: STT, LLM, hotkey watching, focus capture, key injection, and the pipeline that orchestrates them. Keeping it as a Swift package makes the data flow obvious, lets us test the pipeline in isolation against stub `TranscriberProtocol` and `StylerProtocol` implementations, and avoids tangling AppKit lifecycle with engine state.

### Dependencies

The engine package declares two SwiftPM dependencies:
- `tiny-audio-swift` — local path dependency (`../tiny-audio-swift/swift`).
- `mlx-swift-lm` (≥3.31.3) — for `MLXLLM`, `MLXLMCommon`, `MLXHuggingFace` libraries. Plus `swift-huggingface` and `swift-transformers` for the Hub downloader and tokenizer loader. (Note: in earlier versions these libraries lived in `mlx-swift-examples`; they were extracted to `mlx-swift-lm` in 3.x.)

The app target depends only on `OpenFlowEngine`.

## 4. The dictation pipeline

### State machine

```
       ┌───────────┐  press  ┌──────────────┐  release  ┌──────────┐
 idle ─►│ recording ├────────►│ transcribing ├──────────►│ styling  │
       └───────────┘         └──────────────┘           └────┬─────┘
                                                             │ done
                                                             ▼
                                                      ┌────────────┐
                                                      │ injecting  │
                                                      └─────┬──────┘
                                                            │ done
                                                            ▼ idle
```

Cancel and failure are transitions out of *any* phase (omitted from the diagram for clarity):
- **Esc pressed** → `cancelled` → `idle` (no insertion).
- **Error thrown** → `failed(OpenFlowError)` → `idle` after surfacing to the user.

### Phase details

| Phase | Action | Overlay |
|---|---|---|
| `recording` | `AVAudioEngine` mic tap captures mono Float32 @16 kHz into a growing `[Float]` buffer. Frontmost app + focused AX element are captured on entry. | Recording pill with level meter |
| `transcribing` | `Transcriber.transcribeStream(.samples(buf, 16_000))` yields token deltas. | "Transcribing…" with streaming words |
| `styling` | `Styler.style(transcript)` runs the cleanup prompt; tokens stream. | Streaming words replace raw transcript |
| `injecting` | `KeyInjector` posts text to the captured target app. Re-activates target app first. | Fade-out animation |

### Why no live partials during recording

`tiny-audio-swift` has no "transcribe-while-buffer-grows" primitive. Live partials would require either re-running the encoder repeatedly on a growing buffer (wasteful) or using `MicrophoneTranscriber`'s VAD-based utterance chunking (which would split mid-sentence on natural pauses). For hold-to-talk semantics, the hotkey *is* the endpoint — running STT once on release is simpler and avoids spurious splits. The overlay shows audio level during recording instead of partial text.

### Cancellation

- **Esc**: cancels from any phase, dismisses overlay, no insertion.
- **Hotkey held >60s**: auto-stop with a warning toast; pipeline proceeds normally with whatever was captured.
- **Target app quit during recording**: skip injection on completion; copy styled text to clipboard and show toast.

## 5. Permissions, hotkey, injection

### Permissions required

| Permission | Why | Surfaced in |
|---|---|---|
| Microphone (`NSMicrophoneUsageDescription`) | `AVAudioEngine` mic tap | First-run setup; standard macOS prompt on first record |
| Accessibility (`AXIsProcessTrusted`) | (a) `CGEventTap` to read global hotkey, (b) `CGEventPost` to inject keystrokes, (c) capture focused AX element for caret positioning | First-run setup with deep link to `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` |
| Input Monitoring (`kTCCServiceListenEvent`) | Required by `CGEventTap` for `kCGSessionEventTap` on macOS 12+ | First-run setup with deep link |

The setup window shows the status of each permission with a "Re-check" button. The menu-bar icon shows a red dot until all three are granted. Dictation is disabled until permissions are complete.

### Hotkey watcher

- **Default trigger**: hold Right Option (`kVK_RightOption`, virtual keycode `0x3D`). It's a modifier — no character is typed when held alone, so we don't need to swallow events. User-configurable in Settings.
- **Implementation**: session-level `CGEventTap` listening for `flagsChanged`, `keyDown`, `keyUp`, dispatched onto a dedicated `RunLoop` on a background thread. Tap created with `kCGSessionEventTap` and `kCGHeadInsertEventTap`, callback set to `kCGEventTapOptionListenOnly` for modifier-only triggers.
- **Debounce**: `pressed` fires after 80 ms of sustained hold; `released` fires immediately on key-up.

### Keystroke injection

`KeyInjector.insert(_ text: String, into targetApp: NSRunningApplication)` — directional sketch (exact `CGEvent` parameters refined during implementation):

```
1. targetApp.activate()                                     // re-focus if drifted
2. chunk text into runs of one or more Unicode scalars
3. for each chunk:
     create a CGEvent keyDown with virtualKey=0
     call keyboardSetUnicodeString(chunk) on it
     post via .cghidEventTap
     post a matching keyUp
     usleep(1_000)                                          // 1ms pacing
```

- Uses `keyboardSetUnicodeString` — handles emoji, Unicode, all keyboard layouts, no keycode mapping.
- **Long-text fallback**: if `text.count > 500`, save current `NSPasteboard.general` contents → set new contents → post `Cmd+V` → restore old clipboard after 200 ms. Threshold configurable in Settings. The threshold exists because synthesizing 500+ keypresses takes >0.5 s and some apps drop characters.

## 6. LLM styling

### Model and loading

- Library: `mlx-swift-lm` (`MLXLLM`, `MLXLMCommon`).
- Model repo: `mlx-community/Qwen3-4B-Instruct-2507-4bit` (~2.4 GB on disk).
- Cached under `~/Library/Application Support/OpenFlow/models/` via `MLXLMCommon.ModelContainer`.
- First-run download: progress sheet in the Setup window.
- Loaded **lazily on first dictation of each launch** so menu-bar startup stays instant. Subsequent dictations reuse the in-memory `ModelContainer`.

### Styler interface

```swift
protocol StylerProtocol {
    func style(_ raw: String) -> AsyncThrowingStream<String, Error>
}

actor Styler: StylerProtocol { … }
```

Generation parameters: `temperature: 0.2`, `maxTokens: min(rawCharCount * 1.5, 512)`. Low temperature keeps rewrites faithful — we want cleanup, not creative reinterpretation.

### Styling prompt

System prompt (locked in v1):

```
You are a dictation cleanup assistant. The user spoke a message which was
transcribed by a speech-to-text model. Your job is to return ONLY the cleaned-up
text with no commentary, preamble, or quotes.

Rules:
- Remove filler words: um, uh, ah, like, you know, I mean, sort of, kind of
- Remove false starts and self-corrections; keep the corrected version
- Add proper punctuation and capitalization
- Fix obvious word errors that are clearly mis-transcriptions in context
- Preserve the speaker's wording, tone, and meaning — do NOT rephrase or
  summarize
- Preserve numbers, names, code, and technical terms exactly as transcribed
- If the input is a single sentence fragment, return it as a fragment
- If the input is empty or only filler, return empty string

Output: cleaned text only, nothing else.
```

User message: raw transcript wrapped as `<transcript>…</transcript>` so transcript content can't be confused with instructions.

### Safeguards

- **Empty-result guard**: if styler returns empty but raw transcript was >3 words, fall back to inserting raw transcript.
- **Timeout**: 8 seconds. On timeout, fall back to raw transcript and show a toast: *"Styling timed out — inserted raw transcript."*
- **Length guard**: if styled output is >2× raw character count, treat as model misbehavior and fall back to raw.
- **Disable styling toggle** in Settings — pipeline skips the `styling` phase entirely when off.

## 7. UI shell

### Menu-bar status item

Mic icon. Visual states tied to pipeline phase:
- idle: gray
- recording: red pulse
- transcribing: amber spinner
- styling: blue spinner
- error / missing permissions: red dot

Click reveals: *Dictate now / Settings… / Pause / Quit OpenFlow*. "Pause" disables the hotkey watcher until toggled back on.

### Floating overlay

`NSPanel` configured as:
- `level = .floating`
- `styleMask = [.borderless, .nonactivatingPanel]`
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`
- `becomesKeyOnlyIfNeeded = true`, `worksWhenModal = true`, `acceptsMouseMovedEvents = false`

Position: queries the system focused AX element via `AXUIElementCopyAttributeValue` for `kAXFocusedUIElementAttribute` → `kAXBoundsAttribute`, anchors below the caret line; falls back to bottom-center of the active screen if AX bounds unavailable (common in browsers, Electron apps).

The overlay never takes key focus.

### Settings window

Standard `NSWindow` invoked from the status menu. Sections:
- **Hotkey**: recorder field (`HotkeyRecorderView`); default Right Option.
- **Styling**: enable/disable toggle.
- **Long-text fallback threshold**: stepper, default 500.
- **Model**: status (downloaded / size), re-download button.
- **Permissions**: status of each, re-check buttons, deep links.

### First-run Setup window

Same backing structure as Settings but presented as a guided checklist. Shown automatically on first launch; remains the primary surface until: all 3 permissions granted + model downloaded. Status menu deep-links to it whenever a permission becomes missing.

## 8. Error handling

Typed `OpenFlowError` enum at the engine boundary:

```swift
enum OpenFlowError: Error {
    case microphonePermissionDenied
    case accessibilityPermissionMissing
    case inputMonitoringPermissionMissing
    case modelDownloadFailed(underlying: Error)
    case modelLoadFailed(underlying: Error)
    case sttFailed(underlying: Error)
    case stylerTimedOut
    case stylerFailed(underlying: Error)
    case targetAppLost
    case audioCaptureFailed(underlying: Error)
}
```

| Failure | Recovery |
|---|---|
| Mic permission denied | Setup window opens; status icon red |
| Accessibility / Input Monitoring missing | Setup window opens; hotkey + injection disabled |
| Model download fails | Sheet shows error + retry; dictation disabled, app stays usable |
| STT throws mid-pipeline | Overlay shows red error pill 2 s; nothing inserted |
| Styler throws or times out | Fall back to raw transcript; toast |
| Target app quit during recording | Skip injection; copy styled text to clipboard; toast |
| Hotkey held >60 s | Auto-stop with warning toast; pipeline proceeds |

No silent failures: every error path either inserts text, surfaces a toast, or opens Settings.

## 9. Testing

Engine package has unit tests; app shell uses manual smoke verification.

| Test | Coverage |
|---|---|
| `PipelineStateMachineTests` | All valid transitions; invalid transitions throw; cancel from each state; failure transitions |
| `StylerPromptTests` | 10 sample raw transcripts × structural property assertions: no fillers in output, length within bounds, all numerics preserved, no preamble like "Here is the cleaned text:" |
| `KeyInjectorTests` | Long-text fallback threshold; clipboard save/restore; unicode characters split correctly; pacing preserved |
| `HotkeyDebounceTests` | 80 ms debounce window; rapid press/release sequences |
| `FocusCaptureTests` | Frontmost app captured at press, retained across phases, falls back when unavailable |

STT and LLM are stubbed via protocols (`TranscriberProtocol`, `StylerProtocol`) so pipeline tests don't load real models.

A manual smoke checklist lives in `App/SMOKE.md` — apps to dictate into before each release: TextEdit, Slack, Xcode, Mail, browser address bar, Terminal. End-to-end behavior depends on real apps' input handling, which can't be unit-tested.

## 10. Distribution

Local Xcode build, copy the `.app` to `/Applications`. No signing or notarization in v1. Single user (the author).

## 11. Open questions deferred to implementation

- Exact `mlx-swift-lm` revision pin and `MLXLMCommon.ModelConfiguration` invocation — pin to a tagged release at implementation time.
- Whether `MLXLMCommon` exposes a streaming token API in the form assumed by `Styler.style(...) -> AsyncThrowingStream`. If only chunk-by-chunk is available, wrap into the same shape.
- Final overlay visual design (dimensions, blur, level meter style) — determined during UI implementation against real frames.
