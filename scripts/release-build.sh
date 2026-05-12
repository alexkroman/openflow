#!/usr/bin/env bash
# Build, sign, notarize, and staple a release DMG into build/release/.
# Reproducible; safe to re-run. The publish step is a separate script.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/App/OpenFlow"
BUILD_ROOT="$REPO_ROOT/build/release"
DERIVED="$BUILD_ROOT/derived"
STAGE="$BUILD_ROOT/stage"
ENTITLEMENTS="$APP_DIR/OpenFlow/OpenFlow.entitlements"

readonly IDENTITY="640A7F5A9754400D4A0491E7A6FB30542D907806"
readonly TEAM_ID="Y54ZB9JF63"
readonly NOTARY_PROFILE="openflow-notary"

SKIP_CHECKS=0
for arg in "$@"; do
  case "$arg" in
    --skip-checks) SKIP_CHECKS=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

info()  { printf '\033[34m▸\033[0m %s\n' "$*"; }
step()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
die()   { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

if command -v xcbeautify >/dev/null 2>&1; then
  PRETTY=(xcbeautify --quiet)
else
  PRETTY=(cat)
fi

step "Preflight"
for cmd in xcodegen xcodebuild xcrun hdiutil codesign awk shasum; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing required tool: $cmd"
done

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notarytool profile '$NOTARY_PROFILE' not found. Run: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <you@example.com> --team-id $TEAM_ID --password <app-specific-password>"

[ -d "$REPO_ROOT/../tiny-audio-swift" ] || die "sibling repo ../tiny-audio-swift not found"

if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  info "warning: working tree is dirty (release artifacts don't depend on it but you may want a clean tree)"
fi

step "Read version"
VERSION="$(awk '/CFBundleShortVersionString:/ {gsub(/"/,"",$2); print $2; exit}' "$APP_DIR/project.yml")"
[ -n "$VERSION" ] || die "could not parse CFBundleShortVersionString from $APP_DIR/project.yml"
info "version: $VERSION"

step "Initial summary"
info "build root:  $BUILD_ROOT"
info "identity:    $IDENTITY"
info "notary:      $NOTARY_PROFILE"

mkdir -p "$BUILD_ROOT"

if [ "$SKIP_CHECKS" -eq 0 ]; then
  step "scripts/check.sh"
  "$REPO_ROOT/scripts/check.sh"
else
  info "checks skipped (--skip-checks)"
fi

step "xcodegen"
cd "$APP_DIR"
xcodegen generate --quiet

step "xcodebuild Release"
rm -rf "$DERIVED"
xcodebuild \
  -project "$APP_DIR/OpenFlow.xcodeproj" \
  -scheme OpenFlow \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build | "${PRETTY[@]}"

APP_BUILT="$DERIVED/Build/Products/Release/OpenFlow.app"
[ -d "$APP_BUILT" ] || die "expected app at $APP_BUILT — build did not produce it"
info "built: $APP_BUILT ($(du -sh "$APP_BUILT" | cut -f1))"

step "Stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_BUILT" "$STAGE/"
APP_STAGED="$STAGE/OpenFlow.app"

step "Sign nested mach-o"
NESTED_COUNT=0
while IFS= read -r -d '' f; do
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$f"
  NESTED_COUNT=$((NESTED_COUNT + 1))
done < <(find "$APP_STAGED" -type f \( -name "*.dylib" -o -name "*.so" \) -print0)
info "signed $NESTED_COUNT nested mach-o file(s)"

step "Sign bundle"
codesign --force --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  --options runtime \
  --timestamp \
  "$APP_STAGED"

step "Verify signature"
codesign --verify --strict --deep --verbose=2 "$APP_STAGED"
codesign -dvv "$APP_STAGED" 2>&1 | grep '^Timestamp=' \
  || die "no secure timestamp on bundle signature — notary would reject"
info "signature verified with secure timestamp"

step "Create DMG"
ln -sf /Applications "$STAGE/Applications"
DMG="$BUILD_ROOT/OpenFlow-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "OpenFlow $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

step "Sign DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --verbose=1 "$DMG"
info "dmg: $DMG ($(du -sh "$DMG" | cut -f1))"

step "Notarize"
NOTARY_PLIST="$BUILD_ROOT/notary-result.plist"
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format plist > "$NOTARY_PLIST"

NOTARY_STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$NOTARY_PLIST" 2>/dev/null || echo unknown)"
SUBMISSION_ID="$(/usr/libexec/PlistBuddy -c 'Print :id' "$NOTARY_PLIST" 2>/dev/null || echo unknown)"
info "notary status: $NOTARY_STATUS (id $SUBMISSION_ID)"

if [ "$NOTARY_STATUS" != "Accepted" ]; then
  step "Notary log"
  xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
  die "notarization rejected (status: $NOTARY_STATUS)"
fi

step "Staple"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
info "dmg stapled + validated"

step "Summary"
SIZE="$(du -h "$DMG" | cut -f1)"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
cat <<EOF

  DMG:    $DMG
  Size:   $SIZE
  SHA256: $SHA

  Publish with:
    scripts/release-publish.sh
EOF
