#!/usr/bin/env bash
# Tag + push + publish the notarized DMG produced by release-build.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/App/OpenFlow"
BUILD_ROOT="$REPO_ROOT/build/release"

info()  { printf '\033[34m▸\033[0m %s\n' "$*"; }
step()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
die()   { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

step "Preflight"
for cmd in gh git xcrun awk; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing required tool: $cmd"
done

VERSION="$(awk '/CFBundleShortVersionString:/ {gsub(/"/,"",$2); print $2; exit}' "$APP_DIR/project.yml")"
[ -n "$VERSION" ] || die "could not parse version"
DMG="$BUILD_ROOT/OpenFlow-$VERSION.dmg"
[ -f "$DMG" ] || die "DMG not found at $DMG — run scripts/release-build.sh first"
info "version: $VERSION"
info "dmg:     $DMG"

step "Validate staple"
xcrun stapler validate "$DMG" >/dev/null || die "DMG not stapled — rebuild with release-build.sh"

step "Tag preflight"
TAG="v$VERSION"
if git -C "$REPO_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
  die "tag $TAG already exists locally"
fi
if git -C "$REPO_ROOT" ls-remote --tags origin "refs/tags/$TAG" | grep -q .; then
  die "tag $TAG already exists on origin"
fi

step "Working tree"
if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  die "working tree dirty — commit or stash before publishing"
fi

step "Confirm"
SHORT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
SIZE="$(du -h "$DMG" | cut -f1)"
cat <<EOF

  About to tag $TAG at commit $SHORT_SHA, push to origin, and publish a
  GitHub Release.

  DMG: $DMG ($SIZE)

EOF
read -r -p "Continue? [y/N]: " ANS
case "$ANS" in
  y|Y) ;;
  *) info "aborted"; exit 0 ;;
esac

step "Tag + push"
git -C "$REPO_ROOT" tag -a "$TAG" -m "$TAG"
git -C "$REPO_ROOT" push origin "$TAG"

step "GitHub Release"
# Upload under a stable, version-less name so
# https://github.com/<owner>/<repo>/releases/latest/download/OpenFlow.dmg
# always resolves to the current release (README.md links to that URL).
STABLE_DMG="$BUILD_ROOT/OpenFlow.dmg"
cp "$DMG" "$STABLE_DMG"
gh release create "$TAG" "$STABLE_DMG" \
  --title "$TAG" \
  --generate-notes \
  --latest

URL="$(gh release view "$TAG" --json url -q .url)"
info "published: $URL"
