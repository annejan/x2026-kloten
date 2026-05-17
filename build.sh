#!/bin/bash
# outline-64 multi-part build pipeline (Spindle 3.1 / pefchain).
#
# For each part:
#   1. KickAssembler the source (default PRG output + .sym).
#   2. KickAssembler the EFO header with -binfile (raw bin, no load addr).
#      The header pulls setup/interrupt/fadeout addresses from the .sym.
#   3. Concatenate header.bin + code.prg → part.efo.
#   4. mkpef bundles part.efo into part.pef.
#
# Then pefchain links the .pef files per pefchain_script into the .d64.
set -e

ROOT="$(dirname "$(readlink -f "$0")")"
KICKASS="$ROOT/kickass/KickAss.jar"
SPINBIN="$ROOT/spindle-3.1/prebuilt-binaries/linux-x86_64"
MKPEF="$SPINBIN/mkpef"
PEFCHAIN="$SPINBIN/pefchain"

if [[ ! -x "$PEFCHAIN" ]]; then
    echo "pefchain binary not found at $PEFCHAIN."
    echo "Extract spindle-3.1.zip into the repo root."
    exit 1
fi

build_part() {
    local dir="$1" name="$2"
    echo ">>> building $name.pef"
    (
        cd "$ROOT/$dir"
        rm -f "$name.prg" "${name}_efo_header.bin" "$name.efo" "$name.pef"

        # Code
        java -jar "$KICKASS" "$name.asm" >/dev/null
        [[ -f "$name.prg" ]] || { echo "  $name.asm build failed"; exit 1; }

        # EFO header (relies on $name.sym from the previous step)
        java -jar "$KICKASS" -binfile "${name}_efo_header.asm" >/dev/null
        [[ -f "${name}_efo_header.bin" ]] || { echo "  header build failed"; exit 1; }

        # Concatenate header + prg → .efo
        cat "${name}_efo_header.bin" "$name.prg" > "$name.efo"

        # mkpef → .pef
        "$MKPEF" -o "$name.pef" "$name.efo" >/dev/null
        [[ -f "$name.pef" ]] || { echo "  mkpef failed"; exit 1; }
    )
}

build_part parts/screenfill screenfill
build_part parts/intro      intro
build_part parts/interlude  interlude
build_part parts/end        end

echo ">>> linking with pefchain"
( cd "$ROOT" && "$PEFCHAIN" -v -o outline-64.d64 pefchain_script )

echo ">>> done — outline-64.d64"
ls -la "$ROOT/outline-64.d64"
