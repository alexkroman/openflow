#!/usr/bin/env bash
# Tag + push + publish the notarized DMG produced by release-build.sh.
# Pass --republish to overwrite an existing tag + release with new artifacts
# (useful when the published DMG turned out to be broken and needs a redo
# without bumping the version).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/App/OpenFlow"
BUILD_ROOT="$REPO_ROOT/build/release"

REPUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --republish) REPUBLISH=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

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
DSYM_ZIP="$BUILD_ROOT/OpenFlow-$VERSION.app.dSYM.zip"
CHECKSUMS="$BUILD_ROOT/SHA256SUMS"
[ -f "$DMG" ] || die "DMG not found at $DMG — run scripts/release-build.sh first"
[ -f "$DSYM_ZIP" ] || die "dSYM zip not found at $DSYM_ZIP — run scripts/release-build.sh first"
[ -f "$CHECKSUMS" ] || die "SHA256SUMS not found at $CHECKSUMS — run scripts/release-build.sh first"
info "version: $VERSION"
info "dmg:     $DMG"
info "dsym:    $DSYM_ZIP"

step "Validate staple"
xcrun stapler validate "$DMG" >/dev/null || die "DMG not stapled — rebuild with release-build.sh"

step "Tag preflight"
TAG="v$VERSION"
LOCAL_TAG_EXISTS=0
REMOTE_TAG_EXISTS=0
git -C "$REPO_ROOT" rev-parse "$TAG" >/dev/null 2>&1 && LOCAL_TAG_EXISTS=1
git -C "$REPO_ROOT" ls-remote --tags origin "refs/tags/$TAG" | grep -q . && REMOTE_TAG_EXISTS=1
if [ "$REPUBLISH" -eq 0 ]; then
  [ "$LOCAL_TAG_EXISTS" -eq 0 ] || die "tag $TAG already exists locally (pass --republish to overwrite)"
  [ "$REMOTE_TAG_EXISTS" -eq 0 ] || die "tag $TAG already exists on origin (pass --republish to overwrite)"
else
  [ "$LOCAL_TAG_EXISTS" -eq 1 ] || [ "$REMOTE_TAG_EXISTS" -eq 1 ] \
    || die "--republish set but tag $TAG does not exist yet — use a normal publish instead"
  info "republish mode: will overwrite tag $TAG and its release"
fi

step "Working tree"
if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  die "working tree dirty — commit or stash before publishing"
fi

step "Confirm"
SHORT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
SIZE="$(du -h "$DMG" | cut -f1)"
ACTION="tag $TAG at commit $SHORT_SHA, push to origin, and publish a"
if [ "$REPUBLISH" -eq 1 ]; then
  ACTION="DELETE the existing $TAG release + tag and republish from $SHORT_SHA — overwriting a"
fi
cat <<EOF

  About to $ACTION
  GitHub Release.

  DMG: $DMG ($SIZE)

EOF
read -r -p "Continue? [y/N]: " ANS
case "$ANS" in
  y|Y) ;;
  *) info "aborted"; exit 0 ;;
esac

if [ "$REPUBLISH" -eq 1 ]; then
  step "Delete existing release + tag"
  # Deleting the release first (with --cleanup-tag) removes both the GitHub
  # release entry and the remote tag in one step. Local tag is removed
  # separately so the tag-create step below can recreate it cleanly.
  gh release delete "$TAG" --yes --cleanup-tag 2>/dev/null || true
  git -C "$REPO_ROOT" tag -d "$TAG" 2>/dev/null || true
  git -C "$REPO_ROOT" push origin ":refs/tags/$TAG" 2>/dev/null || true
fi

step "Tag + push"
git -C "$REPO_ROOT" tag -a "$TAG" -m "$TAG"
git -C "$REPO_ROOT" push origin "$TAG"

step "GitHub Release"
# Upload under stable, version-less names so
# https://github.com/<owner>/<repo>/releases/latest/download/<name>
# always resolves to the current release (README.md links to that URL).
# gh uses the on-disk basename as the asset's download filename, so we
# hardlink the versioned files to stable names before uploading.
STABLE_DMG="$BUILD_ROOT/OpenFlow.dmg"
STABLE_DSYM="$BUILD_ROOT/OpenFlow.app.dSYM.zip"
ln -f "$DMG" "$STABLE_DMG"
ln -f "$DSYM_ZIP" "$STABLE_DSYM"
gh release create "$TAG" \
  "$STABLE_DMG" \
  "$STABLE_DSYM" \
  "$CHECKSUMS" \
  --title "$TAG" \
  --generate-notes \
  --latest

URL="$(gh release view "$TAG" --json url -q .url)"
info "published: $URL"
