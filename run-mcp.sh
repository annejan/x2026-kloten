#!/bin/bash
# Start VICE-MCP and autostart outline-64.d64 with drive 8 emulation.
#
# Requires:
#  - the vice-mcp build with the Drive8 resource exposure
#    (commit 60d2329 of github.com:annejan/vice-mcp.git)
#  - ~/.local/share/vice/{C64,GLSL,DRIVES} symlinks → /usr/share/vice/...
#
# MCP API at http://127.0.0.1:6510/mcp
set -e
cd "$(dirname "$0")"

DISK="$(pwd)/outline-64.d64"
if [[ ! -f "$DISK" ]]; then
    echo "outline-64.d64 not found. Run ./build.sh first."
    exit 1
fi

pkill -9 -f x64sc 2>/dev/null || true
sleep 1

# Prefer the vice-mcp build; fall back to stock x64sc (no MCP).
VICE_BIN="${VICE_MCP_BIN:-/home/annejan/Projects/vice-mcp/vice/build-test-with-mcp/src/x64sc}"
if [[ ! -x "$VICE_BIN" ]]; then
    VICE_BIN="$(command -v x64sc 2>/dev/null || echo /usr/bin/x64sc)"
    echo "Warning: vice-mcp build not found at \$VICE_MCP_BIN. Using $VICE_BIN (no MCP)." >&2
fi

"$VICE_BIN" \
    -mcpserver \
    > /tmp/vice.log 2>&1 &
disown
sleep 4

if ! ss -tln | grep -q 6510; then
    echo "VICE-MCP failed to start. See /tmp/vice.log"
    exit 1
fi

# Enable 1541 drive (the MCP build defaults to 0 = no drive) AND
# select SID 8580 (= SidModel 1) — the demo's declared submission
# preference. The 8580's digital filter is reproducible across
# C64 hardware, so the filter sweeps in interlude / hush / greets /
# end land identically every time. See docs/music-theory.md
# "Target SID chip: 8580" for the rationale.
curl -s -H "Content-Type: application/json" http://127.0.0.1:6510/mcp \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"vice.machine.config.set","arguments":{"resources":{"Drive8Type":1541,"SidModel":1}}}}' \
    > /dev/null

# Autostart the disk.
curl -s -H "Content-Type: application/json" http://127.0.0.1:6510/mcp \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"vice.autostart\",\"arguments\":{\"path\":\"$DISK\"}}}" \
    > /dev/null

echo "VICE+MCP ready at http://127.0.0.1:6510/mcp — loading $DISK"
