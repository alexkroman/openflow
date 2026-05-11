#!/usr/bin/env bash
# Reset all OpenFlow on-disk state to mimic a fresh install.
#
# Removes: TCC approvals, model cache (TinyAudio), preferences,
# caches, saved state, containers, HTTP/WebKit storage. Leaves
# /Applications/OpenFlow.app alone — the post-build Install step
# reinstates the bundle on the next Debug build.
set -euo pipefail

BUNDLE_ID="dev.alex.OpenFlow"

if pgrep -f "OpenFlow.app/Contents/MacOS/OpenFlow" >/dev/null 2>&1; then
  echo "→ quitting running OpenFlow"
  osascript -e 'tell application "OpenFlow" to quit' >/dev/null 2>&1 || \
    pkill -f "OpenFlow.app/Contents/MacOS/OpenFlow" || true
  sleep 1
fi

echo "→ resetting TCC for $BUNDLE_ID"
tccutil reset All "$BUNDLE_ID"

PATHS=(
  "$HOME/Library/Application Support/TinyAudio"
  "$HOME/Library/Caches/$BUNDLE_ID"
  "$HOME/Library/Containers/$BUNDLE_ID"
  "$HOME/Library/HTTPStorages/$BUNDLE_ID"
  "$HOME/Library/HTTPStorages/$BUNDLE_ID.binarycookies"
  "$HOME/Library/WebKit/$BUNDLE_ID"
  "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
  "$HOME/Library/Preferences/$BUNDLE_ID.plist"
)
for p in "${PATHS[@]}"; do
  if [ -e "$p" ]; then
    rm -rf "$p"
    echo "→ removed $p"
  fi
done

# `defaults delete` + killing cfprefsd ensures no in-memory plist gets
# re-flushed to disk after we delete the file.
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
killall cfprefsd >/dev/null 2>&1 || true

echo "✓ reset complete"
