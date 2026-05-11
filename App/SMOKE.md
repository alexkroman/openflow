# OpenFlow Manual Smoke Checklist

Run before tagging a release. Each row should pass; failures get filed as issues.

## Prerequisites
- All three permissions granted (Mic / Accessibility / Input Monitoring)
- Both models present in `~/Library/Application Support/TinyAudio/Models/` (TinyAudio downloads them automatically on first launch — see "First-run model download" below)
- Build: `xcodebuild -project App/OpenFlow/OpenFlow.xcodeproj -scheme OpenFlow -configuration Debug -derivedDataPath /tmp/openflow-build build`

## First-run model download
1. Quit OpenFlow.
2. `rm -rf "$HOME/Library/Application Support/TinyAudio"`
3. Launch OpenFlow.
4. Setup window opens automatically with two progress rows ("Speech recognition model", "Language model").
5. Both rows progress from "Checking cache" → "Downloading X%" → row disappears once cached.
6. After both rows clear, dictation hotkey starts working.
7. Pressing the hotkey while a row is visible shows the "Still preparing models — please wait" toast.

## Retry path
1. Quit OpenFlow.
2. `rm -rf "$HOME/Library/Application Support/TinyAudio"`
3. Disconnect from network.
4. Launch OpenFlow → both rows show an error string + Retry button.
5. Reconnect, click Retry on each row → downloads complete.

## Apps to test
For each, place cursor in a text field, hold Right Option, dictate "this is a test um of the openflow dictation app", release.

| Target | Expected | Notes |
|---|---|---|
| TextEdit (new doc) | "This is a test of the OpenFlow dictation app." inserted | baseline |
| Slack message composer | Same — typed into the message box | network app |
| Mail compose window | Same — into body | rich-text |
| Xcode editor | Same — into the source file | code app |
| Safari URL bar | Same — into address bar | unusual focus target |
| Terminal.app | Same — into prompt | TTY input |
| Notes (rich text) | Same | NSTextView |
| Notion (Electron) | Same | Electron |

## Edge cases
- [ ] Tap (well below 80ms) — emits no events, no overlay
- [ ] Hold but release before saying anything (silence) — empty/short raw, styler may return empty; raw fallback inserts nothing if <3 words
- [ ] Long dictation (~30s) — single utterance, gets cleaned up correctly
- [ ] Hold beyond 60s — auto-stops with toast, normal pipeline runs
- [ ] Switch apps mid-recording — text inserts into the original target (focus capture)
- [ ] Disable styling in Settings — raw transcript inserted
- [ ] Long styled text (>500 chars) — clipboard-paste path used; clipboard restored after

## Known v1 limitations
- Right Option vs Left Option not distinguished — left also triggers
- Overlay positioned at bottom-center, not at caret (caret tracking deferred)
- TinyAudio public API doesn't expose streaming, so transcribed text appears all at once after the STT pass (overlay shows "Transcribing…" then jumps to full text). Streaming styled tokens still works.
- No Esc-to-cancel in v1 (it's wired in DictationSession.cancel() but no UI surface yet)
