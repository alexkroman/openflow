#!/bin/bash
# Generate AppIcon.appiconset from the mic.fill SF Symbol on a solid brand-color
# squircle. Re-runnable; safe to commit the output.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/App/OpenFlow/OpenFlow/Resources/Assets.xcassets/AppIcon.appiconset"
swift "$REPO_ROOT/scripts/generate-icon.swift" "$OUT_DIR"
echo "AppIcon written to $OUT_DIR"
