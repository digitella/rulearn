#!/usr/bin/env bash
# One-time repository hydration: the project sources were too large for the
# API-based upload, so the first workflow run downloads them from the Rork
# project preview (ASSET_SOURCE), verifies checksums and commits them back.
# Later runs are no-ops (.bootstrapped marker exists).
set -euo pipefail

if [ -f .bootstrapped ]; then
  echo "Repository already hydrated, skipping."
  exit 0
fi

BASE="${ASSET_SOURCE:?ASSET_SOURCE must point at the Rork preview}"

echo "Waiting for $BASE/_bootstrap/manifest.txt ..."
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w %{http_code} "$BASE/_bootstrap/manifest.txt" || true)
  [ "$code" = "200" ] && break
  [ "$i" = 60 ] && { echo "manifest not reachable (HTTP $code)"; exit 1; }
  sleep 15
done

curl -fsSL -o /tmp/manifest.txt "$BASE/_bootstrap/manifest.txt"
mkdir -p _bootstrap
curl -fsSL -o _bootstrap/manifest.txt "$BASE/_bootstrap/manifest.txt"

while read -r sha rel; do
  [ -n "$rel" ] || continue
  mkdir -p "$(dirname "$rel")"
  curl -fsSL --retry 5 -o "$rel" "$BASE/_bootstrap/${rel#./}"
  echo "$sha  $rel" | sha256sum -c - >/dev/null 2>&1 || { echo "checksum mismatch: $rel"; exit 1; }
done < /tmp/manifest.txt

count=$(wc -l < /tmp/manifest.txt)
echo "Hydrated $count files from $BASE"

touch .bootstrapped
git config user.name "rork-bootstrap"
git config user.email "rork@rork.app"
git add -A
git commit -m "Bootstrap: hydrate project sources from Rork ($count files)"
git push origin HEAD:main
echo "Pushed hydrated sources to main."
