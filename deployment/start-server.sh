#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"
exec "${GODOT_BIN:-/usr/local/bin/godot}" --headless --main-pack BeaconBay.pck -- --server --port="${PORT:-24680}"
