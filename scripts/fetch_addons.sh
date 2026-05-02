#!/usr/bin/env bash
# Fetch Godot addons declared below into client/addons/.
# Usage (from repo root):
#   ./scripts/fetch_addons.sh
# Addons are never committed (see .gitignore). Re-run after pulling
# whenever the list changes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDONS_DIR="$REPO_ROOT/client/addons"

# Each entry: "name|owner/repo|tag|asset_filename"
ADDONS=()

fetch_release() {
    local entry="$1"
    IFS='|' read -r name repo tag asset <<<"$entry"
    local url="https://github.com/$repo/releases/download/$tag/$asset"
    local tmp
    tmp="$(mktemp -d)"
    echo "Fetching $name from $url"
    curl -fL "$url" -o "$tmp/$asset"
    mkdir -p "$tmp/extract"
    unzip -q "$tmp/$asset" -d "$tmp/extract"
    local target="$ADDONS_DIR/$name"
    rm -rf "$target"
    mkdir -p "$target"
    cp -R "$tmp/extract"/* "$target"/
    rm -rf "$tmp"
    echo "Installed $name -> $target"
}

if [ "${#ADDONS[@]}" -eq 0 ]; then
    echo "No addons declared yet."
    exit 0
fi

mkdir -p "$ADDONS_DIR"
for entry in "${ADDONS[@]}"; do
    fetch_release "$entry"
done
