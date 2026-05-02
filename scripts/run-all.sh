#!/usr/bin/env bash
# Launch the Rust server and the Godot client side-by-side.
# Usage (from repo root):
#   ./scripts/run-all.sh
# Override the Godot binary with GODOT=/path/to/godot.
# Stop with Ctrl+C — both child processes are terminated.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
    for c in godot godot4 Godot_v4.6.2-stable_linux.x86_64 Godot.app/Contents/MacOS/Godot; do
        if command -v "$c" >/dev/null 2>&1; then
            GODOT="$c"; break
        fi
    done
fi
if [ -z "$GODOT" ]; then
    echo "Godot binary not found. Set GODOT=/path/to/godot." >&2
    exit 1
fi

export DRONOID_BIND="${DRONOID_BIND:-127.0.0.1:8080}"

echo "[run-all] DRONOID_BIND=$DRONOID_BIND"
echo "[run-all] Godot       =$GODOT"

cleanup() {
    trap - INT TERM EXIT
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null || true
    [ -n "${CLIENT_PID:-}" ] && kill "$CLIENT_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup INT TERM EXIT

start_server() {
    cargo run --manifest-path "$REPO_ROOT/server/Cargo.toml" &
    SERVER_PID=$!
}

start_server
sleep 2

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    if [ -f "$REPO_ROOT/galaxy.sqlite" ]; then
        STAMP="$(date +%Y%m%d-%H%M%S)"
        echo "[run-all] server exited early; backing up galaxy.sqlite* (likely incompatible schema)"
        for suffix in "" "-shm" "-wal"; do
            src="$REPO_ROOT/galaxy.sqlite$suffix"
            [ -f "$src" ] && mv "$src" "$src.bak-$STAMP"
        done
        echo "[run-all] retrying server"
        start_server
        sleep 2
    fi
fi

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "[run-all] server failed to start (see output above)" >&2
    exit 1
fi

"$GODOT" --path "$REPO_ROOT/client" &
CLIENT_PID=$!

wait "$CLIENT_PID"
