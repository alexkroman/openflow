#!/bin/bash
# Project health check: build + test the SPM engine and the macOS app.
# Pipes xcodebuild through xcbeautify when available (brew install xcbeautify).
# Runs swiftlint when available (brew install swiftlint).
# Runs periphery when available (brew install periphery).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/App/OpenFlow"

export OS_ACTIVITY_MODE=disable

if command -v xcbeautify >/dev/null 2>&1; then
  PRETTY=(xcbeautify --quiet)
else
  PRETTY=(cat)
  echo "note: xcbeautify not installed; using raw output (brew install xcbeautify)"
fi

run_xcodebuild() {
  set -o pipefail
  xcodebuild "$@" | "${PRETTY[@]}"
}

echo "==> swift test (OpenFlowEngine)"
cd "$REPO_ROOT"
swift test

echo "==> xcodegen (App/OpenFlow)"
cd "$APP_DIR"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --quiet
else
  echo "note: xcodegen not installed; skipping project regeneration"
fi

echo "==> xcodebuild build (OpenFlow)"
run_xcodebuild \
  -project OpenFlow.xcodeproj \
  -scheme OpenFlow \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build

if command -v swiftlint >/dev/null 2>&1; then
  echo "==> swiftlint"
  cd "$REPO_ROOT"
  swiftlint --quiet
else
  echo "note: swiftlint not installed; skipping (brew install swiftlint)"
fi

if command -v periphery >/dev/null 2>&1; then
  echo "==> periphery"
  cd "$REPO_ROOT"
  # --strict promotes any unused-code finding to a non-zero exit.
  # Periphery does its own xcodebuild + index — separate from the build above
  # because reusing DerivedData reliably across machines is fragile.
  periphery scan --strict --quiet
else
  echo "note: periphery not installed; skipping (brew install periphery)"
fi

echo "==> ok"
