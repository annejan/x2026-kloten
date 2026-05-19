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
    shift 2
    # Any remaining args are extra data files for mkpef, e.g. "foo.bin,2800".
    # These ride alongside the main .efo so the KA PRG can stay contiguous.
    local extras=("$@")
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

        # mkpef → .pef (plus any extra binaries at fixed load addresses)
        "$MKPEF" -o "$name.pef" "$name.efo" "${extras[@]}" >/dev/null
        [[ -f "$name.pef" ]] || { echo "  mkpef failed"; exit 1; }
    )
}

build_part parts/screenfill screenfill
build_part parts/intro      intro
build_part parts/interlude  interlude
build_part parts/greets     greets
build_part parts/sinus      sinus
# Coda's Kloot star quad — Stage B: 4 separate sprite-shape binaries pinned
# at $0C00 / $1400 / $1800 / $1C00 so the KA PRG stays compact at $0800-$0AFF
# and pefchain can stream each chunk into RAM independently. The four bases
# are multiples of $400 (i.e. ptr-aligned) so coda.asm can use ORA-based
# pointer cycling.
build_part parts/coda       coda \
    kloot_star_tr.bin,2800 \
    kloot_star_tl.bin,2c00 \
    kloot_star_bl.bin,3000 \
    kloot_star_br.bin,3400
build_part parts/end        end

echo ">>> linking with pefchain"
( cd "$ROOT" && "$PEFCHAIN" -v -o outline-64.d64 pefchain_script )

echo ">>> done — outline-64.d64"
ls -la "$ROOT/outline-64.d64"
