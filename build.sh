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
set -eo pipefail

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

        # Code — capture stderr; show it if build fails
        local ka_err; ka_err=$(java -jar "$KICKASS" "$name.asm" 2>&1 >/dev/null)
        [[ -s "$name.prg" ]] || { echo "  $name.asm build failed:"; echo "$ka_err"; exit 1; }

        # EFO header (relies on $name.sym from the previous step)
        ka_err=$(java -jar "$KICKASS" -binfile "${name}_efo_header.asm" 2>&1 >/dev/null)
        [[ -s "${name}_efo_header.bin" ]] || { echo "  header build failed:"; echo "$ka_err"; exit 1; }

        # Concatenate header + prg → .efo
        cat "${name}_efo_header.bin" "$name.prg" > "$name.efo"

        # mkpef → .pef (plus any extra binaries at fixed load addresses)
        local mkp_err; mkp_err=$("$MKPEF" -o "$name.pef" "$name.efo" "${extras[@]}" 2>&1 >/dev/null)
        [[ -s "$name.pef" ]] || { echo "  mkpef failed:"; echo "$mkp_err"; exit 1; }
    )
}

build_part parts/screenfill screenfill
build_part parts/intro      intro
build_part parts/interlude  interlude
build_part parts/greets     greets
# Coda's Kloot star quad — Stage B: 4 separate sprite-shape binaries pinned
# at $0C00 / $1400 / $1800 / $1C00 so the KA PRG stays compact at $0800-$0AFF
# and pefchain can stream each chunk into RAM independently.
#
# Each kloot_star_*.bin now contains 24 frames = 8 zoom + 16 steady-rotation
# (1536 B each) — coda walks a single shape counter 0..23 with wrap-to-8.
# Bases stride by $600 (24 × 64) so a single shape counter + per-quadrant
# pointer-base ADD covers the whole 6-KB sprite region $2000-$37FF.
build_part parts/coda       coda \
    kloot_star_tr.bin,2000 \
    kloot_star_tl.bin,2600 \
    kloot_star_bl.bin,2c00 \
    kloot_star_br.bin,3200
# Strip PRG header (2 bytes load address) so end.asm can .import binary it.
tail -c +3 "$ROOT/parts/friet/friet.prg" > "$ROOT/parts/friet/friet_payload.bin"
build_part parts/end        end

echo ">>> linking with pefchain"
# --title       16-char disk name, lowercase by demoscene convention
# --disk-id     2-char ID; arbitrary identity beyond Spindle's default `2a`
# --dirart      PETSCII-style box-drawing listing; see dirart.txt
# --dir-entry   Hex index of the entry that's the actual PRG (= the row
#               in dirart.txt holding the entry the user wants visible
#               as "the demo file" when LISTing). We point at $06 — the
#               first "kloten met" line.
( cd "$ROOT" && "$PEFCHAIN" -v \
    --title "DEFEEST/X2026" \
    --disk-id "KL" \
    --dirart dirart.txt \
    --dir-entry 6 \
    -o outline-64.d64 pefchain_script )

echo ">>> done — outline-64.d64"

# Secret easter egg: friet.prg loads when pressing space during end credits.
# Rebuild from source if the friet-van-desire repo is available.
if [[ -f "$ROOT/tools/update-friet.sh" ]]; then
    "$ROOT/tools/update-friet.sh" 2>&1 || echo "  (friet rebuild skipped)"
fi
# File "friet" blends into the dirart directory chaos (among DEL entries).
c1541 "$ROOT/outline-64.d64" -write "$ROOT/parts/friet/friet.prg" friet >/dev/null 2>&1

ls -la "$ROOT/outline-64.d64"
