#!/bin/bash
# Fast iteration loop for parts/end/end.asm.
# Builds end_test.asm (end.asm + BASIC stub) and autostarts in
# system x64sc. No Spindle, no screenfill, no main demo.
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
/usr/bin/x64sc -autostart "$ROOT/parts/end/end_test.prg" >/dev/null 2>&1 &
disown
echo ">>> running end_test.prg in x64sc"
