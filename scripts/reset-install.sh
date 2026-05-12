#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="dev.alex.OpenFlow"
MODELS_DIR="$HOME/Library/Application Support/TinyAudio/Models"

echo "==> Deleting model cache: $MODELS_DIR"
rm -rf "$MODELS_DIR"

echo "==> Resetting TCC permissions for $BUNDLE_ID"
tccutil reset Accessibility "$BUNDLE_ID" || true
tccutil reset Microphone "$BUNDLE_ID" || true

echo "==> Clearing UserDefaults for $BUNDLE_ID"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo "Done. Quit and relaunch OpenFlow for permission prompts to reappear."
