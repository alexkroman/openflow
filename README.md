# OpenFlow

Hold a hotkey, speak, and your words land as cleaned-up text in whatever app
you're focused on. Fully on-device — your voice never leaves your Mac.

## Download

[**Download OpenFlow (DMG)**](https://github.com/alexkroman/openflow/releases/latest/download/OpenFlow.dmg)

Open the DMG and drag **OpenFlow.app** into Applications.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon Mac (M1 / M2 / M3 / M4)
- ~2 GB free disk space for the on-device models

## First launch

OpenFlow lives in your menu bar — there's no Dock icon, so look for the
OpenFlow icon at the top of the screen.

1. The Setup window walks you through granting **Microphone**,
   **Accessibility**, and **Input Monitoring** permissions in System Settings.
2. On first run OpenFlow downloads its speech-recognition and text-cleanup
   models (~1.4 GB). Progress is shown in the Setup window. The hotkey stays
   disabled until both models are ready.

## How to dictate

Hold **⌃⌥D** (Control-Option-D), speak, then release. A small overlay shows
the current phase:

`recording → transcribing → styling → injecting`

When it finishes, the cleaned-up text is typed straight into the app you were
focused on. You can rebind the hotkey from OpenFlow's menu-bar Settings.

## Privacy

Everything runs locally on your Mac:

- Speech-to-text via [`tiny-audio-swift`](https://github.com/mazesmazes/tiny-audio-swift)
- Cleanup styling via an MLX-based LLM (Qwen3.5-2B-OptiQ-4bit)

No audio, transcripts, or text are sent to any server. The only network
activity is the one-time model download on first launch.

## Contributing

Issues and pull requests are welcome. See [`CLAUDE.md`](CLAUDE.md) for the
architecture overview and how to build from source.
