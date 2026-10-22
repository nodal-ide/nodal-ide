#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

REPOSITORY="nodal-ide/nodal-ide"
REPOSITORY_URL="https://github.com/${REPOSITORY}"
NOTES_FILE="$ROOT_DIR/release_notes.md"
APP_PLIST="$ROOT_DIR/CodeEdit/Info.plist"
FINDER_PLIST="$ROOT_DIR/OpenWithCodeEdit/Info.plist"
PROJECT_FILE="$ROOT_DIR/CodeEdit.xcodeproj/project.pbxproj"
PLIST_BUDDY=/usr/libexec/PlistBuddy

fail() {
  printf 'release.sh: %s\n' "$*" >&2
  exit 1
}

for required_command in git gh jq xcodebuild xcrun perl plutil ditto shasum xmllint grep; do
  command -v "$required_command" >/dev/null 2>&1 || fail "Required command not found: $required_command"
done

[[ -f "$NOTES_FILE" ]] || fail "Create $NOTES_FILE with YAML front matter for version and build."
[[ "$(head -n 1 "$NOTES_FILE")" == "---" ]] || fail "release_notes.md must start with YAML front matter."

metadata_value() {
  awk -v field="$1" '
    NR == 1 && $0 == "---" { in_header = 1; next }
    in_header && $0 == "---" { closed = 1; exit }
    in_header && index($0, field ":") == 1 {
      value = substr($0, length(field) + 2)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      count++
    }
    END {
      if (!closed || count != 1 || value == "") exit 1
      print value
    }
  ' "$NOTES_FILE"
}

VERSION="$(metadata_value version)" || fail "release_notes.md needs exactly one 'version: X.Y.Z' field."
BUILD="$(metadata_value build)" || fail "release_notes.md needs exactly one 'build: N' field."
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must use numeric semantic versioning (X.Y.Z)."
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || fail "Build must be a positive integer without leading zeroes."
NOTES_STATUS="$(git status --porcelain --untracked-files=all)"
while IFS= read -r status_line; do
  [[ -z "$status_line" ]] && continue
  [[ "${status_line:3}" == "release_notes.md" ]] || fail "Only release_notes.md may be uncommitted when running a release."
done <<<"$NOTES_STATUS"

TAG="v${VERSION}"
STAGE_DIR=""
release_for_tag() {
  gh api "repos/${REPOSITORY}/releases?per_page=100" |
    jq -c --arg tag "$TAG" '[.[] | select(.tag_name == $tag)] | first // empty'
}

cleanup() {
  if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
    rm -rf "$STAGE_DIR"
  fi
}
trap cleanup EXIT

REMOTE_URL="$(git remote get-url origin 2>/dev/null)" || fail "Git origin is not configured."
case "$REMOTE_URL" in
  git@github.com:nodal-ide/nodal-ide.git|ssh://git@github.com/nodal-ide/nodal-ide.git|https://github.com/nodal-ide/nodal-ide|https://github.com/nodal-ide/nodal-ide.git) ;;
  *) fail "origin must point to nodal-ide/nodal-ide (found: $REMOTE_URL)." ;;
esac
[[ "$(git branch --show-current)" == "main" ]] || fail "Run releases from the main branch."
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail "Commit or stash all changes before releasing."
gh auth status --hostname github.com >/dev/null 2>&1 || fail "Authenticate gh with access to $REPOSITORY."

git fetch origin main --tags
read -r REMOTE_ONLY LOCAL_ONLY < <(git rev-list --left-right --count origin/main...HEAD)
if [[ "$LOCAL_ONLY" == "1" ]]; then
  LAST_COMMIT="$(git log -1 --format=%s)"
  case "$LAST_COMMIT" in
    "Release Nodal IDE ${TAG} (build ${BUILD})"|"Update release notes for Nodal IDE ${TAG}") ;;
    *) fail "Local main has unpushed commits." ;;
  esac
  git push origin main
elif [[ "$REMOTE_ONLY" != "0" || "$LOCAL_ONLY" != "0" ]]; then
  fail "main and origin/main must match before releasing."
fi

EXISTING_RELEASE="$(release_for_tag)"
if [[ -n "$EXISTING_RELEASE" ]]; then
  EXISTING_DRAFT="$(jq -r '.draft' <<<"$EXISTING_RELEASE")"
  EXISTING_PRERELEASE="$(jq -r '.prerelease' <<<"$EXISTING_RELEASE")"
  if [[ "$EXISTING_DRAFT" == "false" && "$EXISTING_PRERELEASE" == "false" ]]; then
    [[ -z "$NOTES_STATUS" ]] || fail "The release is already published; release_notes.md has uncommitted edits."
    printf 'Release %s is already published: %s\n' "$TAG" "$REPOSITORY_URL/releases/tag/$TAG"
    exit 0
  fi
fi

CURRENT_VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
CURRENT_BUILD="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$APP_PLIST")"
if [[ "$CURRENT_VERSION" == "$VERSION" && "$CURRENT_BUILD" == "$BUILD" ]]; then
  if [[ -n "$NOTES_STATUS" ]]; then
    git add "$NOTES_FILE"
    git commit -m "Update release notes for Nodal IDE ${TAG}"
    git push origin main
  fi
else
  VERSION_IS_NEWER="$(awk -v release_version="$VERSION" -v current="$CURRENT_VERSION" 'BEGIN {
    split(release_version, n, "[.]"); split(current, c, "[.]")
    for (i = 1; i <= 3; i++) {
      if (n[i] > c[i]) exit 0
      if (n[i] < c[i]) exit 1
    }
    exit 1
  }' && printf yes || printf no)"
  [[ "$VERSION_IS_NEWER" == "yes" ]] || fail "Version $VERSION must be newer than $CURRENT_VERSION."
  [[ "$BUILD" -gt "$CURRENT_BUILD" ]] || fail "Build $BUILD must be greater than $CURRENT_BUILD."

  "$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$APP_PLIST"
  "$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD" "$APP_PLIST"
  "$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$FINDER_PLIST"
  "$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD" "$FINDER_PLIST"
  NODAL_RELEASE_VERSION="$VERSION" NODAL_RELEASE_BUILD="$BUILD" perl -0pi -e '
    s/(CURRENT_PROJECT_VERSION\s*=\s*)\d+;/$1$ENV{NODAL_RELEASE_BUILD};/g;
    s/(MARKETING_VERSION\s*=\s*)"Change in Info.plist";/$1"$ENV{NODAL_RELEASE_VERSION}";/g;
  ' "$PROJECT_FILE"

  git add "$APP_PLIST" "$FINDER_PLIST" "$PROJECT_FILE" "$NOTES_FILE"
  git commit -m "Release Nodal IDE ${TAG} (build ${BUILD})"
  git push origin main
fi

[[ -z "$(git status --porcelain --untracked-files=all)" ]] || fail "Worktree changed during release preparation."

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nodal-release.XXXXXX")"
ARCHIVE_PATH="$STAGE_DIR/Nodal.xcarchive"
ASSET_DIR="$STAGE_DIR/assets"
mkdir -p "$ASSET_DIR"
BUILD_LOG="$STAGE_DIR/xcodebuild.log"
NOTES_BODY_FILE="$STAGE_DIR/release-notes-body.md"
NODAL_DERIVED_DATA_PATH="${NODAL_DERIVED_DATA_PATH:-}"
awk '
  NR == 1 && $0 == "---" { in_header = 1; next }
  in_header && $0 == "---" { in_header = 0; body = 1; next }
  body { print }
' "$NOTES_FILE" >"$NOTES_BODY_FILE"
grep -Eq '[^[:space:]]' "$NOTES_BODY_FILE" || fail "release_notes.md must contain release notes after the front matter."

XCODEBUILD_ARGS=(
  -project CodeEdit.xcodeproj \
  -scheme CodeEdit \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -skipPackagePluginValidation
)
if [[ -n "$NODAL_DERIVED_DATA_PATH" ]]; then
  XCODEBUILD_ARGS+=(-derivedDataPath "$NODAL_DERIVED_DATA_PATH")
fi

if ! xcodebuild "${XCODEBUILD_ARGS[@]}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  'CODE_SIGN_IDENTITY=' \
  archive >"$BUILD_LOG" 2>&1; then
  grep -En 'error:|warning: (Line Length|File Length)|BUILD (SUCCEEDED|FAILED)|The following build commands failed' "$BUILD_LOG" || true
  tail -n 80 "$BUILD_LOG"
  FAILURE_LOG="${TMPDIR:-/tmp}/nodal-release-${VERSION}-build.log"
  cp "$BUILD_LOG" "$FAILURE_LOG"
  fail "Release archive failed; full log: $FAILURE_LOG"
fi
grep -En 'error:|warning: (Line Length|File Length)|BUILD (SUCCEEDED|FAILED)' "$BUILD_LOG" || true

BUILT_APP="$ARCHIVE_PATH/Products/Applications/CodeEdit.app"
[[ -d "$BUILT_APP" ]] || fail "Expected app archive not found at $BUILT_APP."
BUILT_INFO="$BUILT_APP/Contents/Info.plist"
[[ "$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$BUILT_INFO")" == "$VERSION" ]] || fail "Archived app version does not match $VERSION."
[[ "$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$BUILT_INFO")" == "$BUILD" ]] || fail "Archived app build does not match $BUILD."
[[ "$("$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$BUILT_INFO")" == "do.upper.nodalide" ]] || fail "Archived app bundle identifier is not Nodal's."

BUILT_FINDER_INFO="$BUILT_APP/Contents/PlugIns/OpenWithCodeEdit.appex/Contents/Info.plist"
[[ -f "$BUILT_FINDER_INFO" ]] || fail "Finder extension is missing from the archive."
[[ "$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$BUILT_FINDER_INFO")" == "$VERSION" ]] || fail "Archived Finder extension version does not match $VERSION."
[[ "$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$BUILT_FINDER_INFO")" == "$BUILD" ]] || fail "Archived Finder extension build does not match $BUILD."

ditto "$BUILT_APP" "$ASSET_DIR/Nodal.app"
ZIP_PATH="$ASSET_DIR/Nodal-${VERSION}.zip"
HTML_PATH="$ASSET_DIR/Nodal-${VERSION}.html"
APPCAST_PATH="$ASSET_DIR/appcast.xml"
ditto -c -k --sequesterRsrc --keepParent "$ASSET_DIR/Nodal.app" "$ZIP_PATH"
cat >"$HTML_PATH" <<HTML
<!DOCTYPE html>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0;url=${REPOSITORY_URL}/releases/tag/${TAG}">
<title>Nodal IDE ${VERSION} release notes</title>
<p><a href="${REPOSITORY_URL}/releases/tag/${TAG}">View Nodal IDE ${VERSION} release notes</a></p>
HTML

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
if [[ -n "${NODAL_SPARKLE_BIN:-}" ]]; then
  SPARKLE_BIN="$NODAL_SPARKLE_BIN"
elif [[ -n "$NODAL_DERIVED_DATA_PATH" && -x "$NODAL_DERIVED_DATA_PATH/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" ]]; then
  SPARKLE_BIN="$NODAL_DERIVED_DATA_PATH/SourcePackages/artifacts/sparkle/Sparkle/bin"
else
  SPARKLE_APPCAST="$(find "$DERIVED_DATA" -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' -type f -print -quit 2>/dev/null || true)"
  [[ -n "$SPARKLE_APPCAST" ]] || fail "Sparkle tools not found; set NODAL_SPARKLE_BIN to the Sparkle bin directory."
  SPARKLE_BIN="$(dirname "$SPARKLE_APPCAST")"
fi
[[ -x "$SPARKLE_BIN/generate_appcast" && -x "$SPARKLE_BIN/generate_keys" ]] || fail "Invalid Sparkle tool directory: $SPARKLE_BIN."

PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" --account nodal -p 2>/dev/null)"
APP_PUBLIC_KEY="$("$PLIST_BUDDY" -c 'Print :SUPublicEDKey' "$BUILT_INFO")"
[[ "$PUBLIC_KEY" == "$APP_PUBLIC_KEY" ]] || fail "Nodal Sparkle Keychain key does not match the app's public key."

KEY_FILE="$STAGE_DIR/nodal-sparkle-private-key"
umask 077
"$SPARKLE_BIN/generate_keys" --account nodal -x "$KEY_FILE" >/dev/null
[[ -s "$KEY_FILE" ]] || fail "Could not export the Nodal Sparkle private key."
chmod 600 "$KEY_FILE"

"$SPARKLE_BIN/generate_appcast" \
  --ed-key-file "$KEY_FILE" \
  --download-url-prefix "$REPOSITORY_URL/releases/download/${TAG}/" \
  --release-notes-url-prefix "$REPOSITORY_URL/releases/download/${TAG}/" \
  --full-release-notes-url "$REPOSITORY_URL/releases/tag/${TAG}" \
  --link "$REPOSITORY_URL" \
  --maximum-deltas 0 \
  "$ASSET_DIR"
xmllint --noout "$APPCAST_PATH"

REMOTE_TAG="$(git ls-remote --tags origin "refs/tags/${TAG}" | awk 'NR == 1 { print $1 }')"
if [[ -z "$REMOTE_TAG" ]]; then
  if ! git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    git tag -a "$TAG" -m "Nodal IDE ${TAG}"
  fi
  [[ "$(git rev-parse "${TAG}^{commit}")" == "$(git rev-parse HEAD)" ]] || fail "Local tag $TAG points to a different commit."
  git push origin "$TAG"
else
  git fetch origin "refs/tags/${TAG}:refs/tags/${TAG}"
  [[ "$(git rev-parse "${TAG}^{commit}")" == "$(git rev-parse HEAD)" ]] || fail "Remote tag $TAG points to a different commit."
fi

EXISTING_RELEASE="$(release_for_tag)"
if [[ -n "$EXISTING_RELEASE" ]]; then
  [[ "$(jq -r '.draft' <<<"$EXISTING_RELEASE")" == "true" ]] || fail "A published release already exists for $TAG; refusing to replace it."
  gh release edit "$TAG" --repo "$REPOSITORY" --title "Nodal IDE ${VERSION}" --notes-file "$NOTES_BODY_FILE"
  gh release upload "$TAG" "$ZIP_PATH" "$HTML_PATH" "$APPCAST_PATH" --repo "$REPOSITORY" --clobber
else
  gh release create "$TAG" "$ZIP_PATH" "$HTML_PATH" "$APPCAST_PATH" \
    --repo "$REPOSITORY" \
    --target main \
    --title "Nodal IDE ${VERSION}" \
    --notes-file "$NOTES_BODY_FILE" \
    --draft \
    --verify-tag
fi

REMOTE_RELEASE="$(release_for_tag)"
[[ -n "$REMOTE_RELEASE" ]] || fail "GitHub draft release could not be found by tag."
for asset in "$ZIP_PATH" "$HTML_PATH" "$APPCAST_PATH"; do
  asset_name="$(basename "$asset")"
  local_digest="sha256:$(shasum -a 256 "$asset" | awk '{print $1}')"
  remote_digest="$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .digest // empty' <<<"$REMOTE_RELEASE")"
  [[ "$remote_digest" == "$local_digest" ]] || fail "Uploaded asset verification failed: $asset_name."
done

gh release edit "$TAG" --repo "$REPOSITORY" --draft=false --prerelease=false --latest
LATEST_TAG="$(gh api "repos/${REPOSITORY}/releases/latest" --jq '.tag_name')"
[[ "$LATEST_TAG" == "$TAG" ]] || fail "GitHub latest release is $LATEST_TAG, expected $TAG."
printf 'Published %s: %s/releases/tag/%s\n' "$TAG" "$REPOSITORY_URL" "$TAG"
