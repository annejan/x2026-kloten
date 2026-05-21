#!/bin/bash
# capture_part_screenshots.sh — snapshot one hero frame per part for
# the submission bundle. Boots VICE-MCP, waits real-time for each
# part to reach its hero moment, captures via vice.display.screenshot.
#
# Usage:  ./tools/capture_part_screenshots.sh [output-dir]
#         default output-dir: $REPO_ROOT/submission/<bundle>/screenshots
#
# Timing source: docs/timing.md (current as of 2026-05-21). If the
# part durations change in the demo, update the SECONDS column below
# AND re-run the doc. The numbers below ASSUME current pefchain
# transition triggers; if any of f6=10/30/a0 thresholds move, this
# script captures the wrong frame for that part.
#
# !!! KNOWN BROKEN (2026-05-21) — see docs/submission.md
# "Dry-run findings". Of 7 snapshots, only 02-intro and 07-end
# landed in the right moment; the other 5 captured wrong parts /
# black transition frames. Root causes: (1) boot_ms anchors before
# VICE finishes booting, (2) timing.md is stale post commits
# 736a2f9 / 8ed0777 / 9d9f851. Fix-it-right: poll $F6 via MCP and
# anchor snapshots to part-transition events instead of wall clock.
# Fix-it-quick: recalibrate the offsets below empirically.
# Until either is done, hand-pick screenshots interactively via MCP
# at submission time and drop them into the bundle dir.

set -eo pipefail

OUT_DIR="${1:-/tmp/x2026-screenshots}"
mkdir -p "$OUT_DIR"

MCP="http://127.0.0.1:6510/mcp"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

mcp_call() {
    # mcp_call <toolname> <json-args>
    local tool="$1"; shift
    local args="$1"; shift
    curl -s -X POST "$MCP" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool\",\"arguments\":$args}}"
}

snapshot() {
    # snapshot <png-name> <seconds-from-boot>
    local name="$1"
    local target_t="$2"

    local now=$(($(date +%s%N) / 1000000))
    local elapsed_ms=$((now - boot_ms))
    local target_ms=$((target_t * 1000))
    local wait_ms=$((target_ms - elapsed_ms))

    if (( wait_ms > 0 )); then
        # convert ms back to seconds for sleep
        sleep $(awk "BEGIN { printf \"%.3f\", $wait_ms / 1000 }")
    fi

    mcp_call "vice.display.screenshot" \
        "{\"path\":\"$OUT_DIR/$name.png\"}" > /dev/null
    echo "  [$target_t s] -> $OUT_DIR/$name.png"
}

echo ">>> capture_part_screenshots: VICE boot"
pkill -9 -f x64sc 2>/dev/null || true
sleep 1
( cd "$ROOT" && ./run-mcp.sh ) > /tmp/screencap-mcp.log 2>&1
boot_ms=$(($(date +%s%N) / 1000000))

# Brief settle so MCP is responsive.
sleep 4
boot_ms=$((boot_ms + 4000))   # account for the settle delay

# Per docs/timing.md, one-pass ~3:00 layout (boot offsets in seconds):
snapshot "01-screenfill"  3      # radial bloom mid-reveal
snapshot "02-intro"       30     # logo + bars + balls, mid-act
snapshot "03-interlude"   83     # SPARKED sprite letters landed
snapshot "04-sinus"       88     # DEFEEST wobble in motion
snapshot "05-greets"      130    # mid-scroll, multiple groups visible
snapshot "06-coda"        175    # KLOTEN title card + twin stars
snapshot "07-end"         200    # credit roll mid-scroll

echo ">>> done"
ls -la "$OUT_DIR"/*.png
