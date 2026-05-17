#!/bin/bash
# Run outline-64.d64 in system VICE (x64sc) — visual only.
# For MCP-driven testing, see run-mcp.sh (loads rasterbars.prg, the
# single-PRG legacy build).
set -e

ROOT="$(dirname "$(readlink -f "$0")")"
DISK="$ROOT/outline-64.d64"

if [[ ! -f "$DISK" ]]; then
    echo "outline-64.d64 not found. Run ./build.sh first."
    exit 1
fi

pkill -9 -f x64sc 2>/dev/null || true
sleep 1
/usr/bin/x64sc -drive8type 1541 -autostart "$DISK" >/dev/null 2>&1 &
disown
echo "VICE running disk: $DISK"
