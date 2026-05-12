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
# Skip codesigning for the health-check build: the Developer ID cert only
# lives on the maintainer's machine. The postBuildScripts "Install to
# /Applications" step also bails out when CODE_SIGNING_ALLOWED=NO.
run_xcodebuild \
  -project OpenFlow.xcodeproj \
  -scheme OpenFlow \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> swift-format"
cd "$REPO_ROOT"
# Apple's swift-format (bundled with Xcode 16+) is the project's sole Swift
# linter/formatter. --strict makes any pending formatting a non-zero exit so
# this check fails if someone forgot to run swift-format on their diff.
find Sources Tests App/OpenFlow/OpenFlow scripts -name '*.swift' -print0 \
  | xargs -0 xcrun swift-format lint --strict

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

if command -v actionlint >/dev/null 2>&1; then
  echo "==> actionlint"
  cd "$REPO_ROOT"
  actionlint
else
  echo "note: actionlint not installed; skipping (brew install actionlint)"
fi

if command -v prettier >/dev/null 2>&1; then
  echo "==> prettier --check"
  cd "$REPO_ROOT"
  prettier --check '**/*.{yml,yaml,md}'
else
  echo "note: prettier not installed; skipping (brew install prettier)"
fi

echo "==> ok"
