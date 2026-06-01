#!/bin/bash
# Build the parts-under-test and run the sim6502 6502 unit tests.
#
#   ./tests/sim6502/run.sh            # run all suites
#   ./tests/sim6502/run.sh -t         # ...with instruction trace
#   ./tests/sim6502/run.sh -n cac-*   # filter (passed through to the CLI)
#
# Uses the sim6502 testing framework via Docker (ghcr.io/barryw/sim6502).
# Each .6502 suite loads a part's freshly-assembled .prg + KickAssembler
# .sym, so we (re)build those here first. Build artifacts (.prg/.sym) are
# gitignored — only the .6502 test sources are tracked.
set -eo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/tests/sim6502"
KICKASS="$ROOT/kickass/KickAss.jar"
IMAGE="ghcr.io/barryw/sim6502:latest"

# Parts that have unit tests — assemble each to <name>.prg + copy its .sym.
PARTS=(intro)

for p in "${PARTS[@]}"; do
    echo ">>> assembling $p for tests"
    java -jar "$KICKASS" "$ROOT/parts/$p/$p.asm" -o "$HERE/$p.prg" >/dev/null
    cp "$ROOT/parts/$p/$p.sym" "$HERE/$p.sym"
done

status=0
for t in "$HERE"/*.6502; do
    echo ">>> sim6502: $(basename "$t")"
    docker run --rm -v "$ROOT:/code" "$IMAGE" -s "/code/tests/sim6502/$(basename "$t")" "$@" || status=1
done
exit $status
