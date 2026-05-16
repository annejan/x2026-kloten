#!/bin/bash
# outline-64 multi-part build pipeline.
#
# Builds each part PRG with KickAssembler then bakes the .d64 with Spindle.
# Output: outline-64.d64
set -e

ROOT="$(dirname "$(readlink -f "$0")")"
KICKASS="$ROOT/kickass/KickAss.jar"
SPIN="$ROOT/spindle-2.3/spindle/spin"

if [[ ! -f "$SPIN" ]]; then
    echo "Spindle 'spin' tool not found. Run: cd spindle-2.3/spindle && make"
    exit 1
fi

build_part() {
    local dir="$1" name="$2"
    echo ">>> building $name"
    ( cd "$ROOT/$dir" && rm -f "$name.prg" && java -jar "$KICKASS" "$name.asm" )
    if [[ ! -f "$ROOT/$dir/$name.prg" ]]; then
        echo "Build of $name failed."
        exit 1
    fi
}

build_part parts/screenfill screenfill
build_part parts/main       main

echo ">>> baking disk image"
( cd "$ROOT" && "$SPIN" -vv -o outline-64.d64 script )

echo ">>> done — outline-64.d64"
ls -la "$ROOT/outline-64.d64"
