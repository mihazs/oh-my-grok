#!/usr/bin/env bash
# Manual GitHub release when Actions / release-please is unavailable (e.g. billing lock).
# Usage: ./scripts/manual-release.sh 0.1.0
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <semver without v, e.g. 0.1.0>" >&2
  exit 1
fi

TAG="v${VERSION}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists locally." >&2
else
  git tag -a "$TAG" -m "Release $TAG"
  echo "Created tag $TAG at $(git rev-parse --short HEAD)"
fi

NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT

{
  echo "# oh-my-grok $TAG"
  echo
  echo "## Install"
  echo
  echo '```bash'
  echo "grok plugin install github:mihazs/oh-my-grok@${TAG} --trust"
  echo "grok plugin enable oh-my-grok"
  echo '```'
  echo
  awk -v ver="$VERSION" '
    $0 ~ "^## \\[" ver "\\]" { found=1; next }
    found && /^## \[/ { exit }
    found { print }
  ' CHANGELOG.md
} >"$NOTES_FILE"

git push origin "$TAG"

if gh release view "$TAG" --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" >/dev/null 2>&1; then
  gh release edit "$TAG" --notes-file "$NOTES_FILE"
  echo "Updated existing release $TAG"
else
  gh release create "$TAG" --title "$TAG" --notes-file "$NOTES_FILE"
  echo "Created release $TAG"
fi

echo "Done: $(gh release view "$TAG" --json url -q .url)"