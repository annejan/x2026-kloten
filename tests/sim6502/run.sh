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
PARTS=(intro coda end interlude greets screenfill)

# `end` .import's the friet easter-egg payload, which lives in the gitignored
# parts/friet-met-desire/ (built from a separate repo via tools/update-friet.sh).
# The `end` unit tests (push_next_credit_row / scroll_rows_up) never touch it,
# so on a fresh clone / CI where it's absent, drop in a zero stub purely so the
# part assembles. Real builds (build.sh) use the real payload.
FRIET_BIN="$ROOT/parts/friet-met-desire/friet_payload.bin"
if [[ ! -f "$FRIET_BIN" ]]; then
    echo ">>> friet_payload.bin absent — writing a 256-byte zero stub for the test build"
    mkdir -p "$(dirname "$FRIET_BIN")"
    head -c 256 /dev/zero > "$FRIET_BIN"
fi

for p in "${PARTS[@]}"; do
    echo ">>> assembling $p for tests"
    # -symbolfile is explicit so we don't depend on a KickAss.cfg beside the
    # jar (CI lifts a bare jar out of the kickassembler image). Writes the
    # .sym next to the source, which we copy below.
    java -jar "$KICKASS" "$ROOT/parts/$p/$p.asm" -o "$HERE/$p.prg" -symbolfile >/dev/null
    cp "$ROOT/parts/$p/$p.sym" "$HERE/$p.sym"
done

status=0
for t in "$HERE"/*.6502; do
    echo ">>> sim6502: $(basename "$t")"
    docker run --rm -v "$ROOT:/code" "$IMAGE" -s "/code/tests/sim6502/$(basename "$t")" "$@" || status=1
done
exit $status
