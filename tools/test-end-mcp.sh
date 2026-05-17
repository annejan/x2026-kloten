#!/bin/bash
# Build + autostart end_test.prg in the MCP-enabled VICE build.
# Same as test-end.sh but uses the vice-mcp binary so we can poll
# state and grab screenshots via http://127.0.0.1:6510/mcp.
set -e

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
KICKASS="$ROOT/kickass/KickAss.jar"

echo ">>> building end_test"
( cd "$ROOT/parts/end" && rm -f end_test.prg && java -jar "$KICKASS" end_test.asm )

if [[ ! -f "$ROOT/parts/end/end_test.prg" ]]; then
    echo "build failed"
    exit 1
fi

pkill -9 -f x64sc 2>/dev/null || true
sleep 1

/home/annejan/Projects/vice-mcp/vice/build-test-with-mcp/src/x64sc \
    -mcpserver \
    > /tmp/vice.log 2>&1 &
disown
sleep 4

if ! ss -tln | grep -q 6510; then
    echo "VICE-MCP failed to start. See /tmp/vice.log"
    exit 1
fi

curl -s -H "Content-Type: application/json" http://127.0.0.1:6510/mcp \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"vice.autostart\",\"arguments\":{\"path\":\"$ROOT/parts/end/end_test.prg\"}}}" \
    > /dev/null

echo ">>> end_test.prg running under VICE-MCP at http://127.0.0.1:6510/mcp"
