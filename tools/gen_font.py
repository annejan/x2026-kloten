#!/usr/bin/env python3
"""
Generate parts/greets/font.bin — the 32-slot sprite font used by greets.

Reads parts/greets/chargen.bin (the C64 character ROM, set B/lowercase
half), applies EPX-3 upscaling to expand each 8×8 glyph to 24×21
hi-res sprite data, and writes the 32-slot × 64-byte = 2048-byte font
binary at parts/greets/font.bin.

Day-to-day workflow:
    # Edit a glyph
    open parts/greets/font.bin in Spritemate or SpritePad
    # save raw 2048-byte .bin back over parts/greets/font.bin
    ./build.sh

Reset to the chargen-EPX baseline:
    python3 tools/gen_font.py

EPX rule (Eric's Pixel Expansion, 3× variant): each source pixel
becomes a 3×3 output block; the four corners of each block default
to P (the centre) but get replaced by a neighbour value when the
two adjacent neighbours agree on a value different from P. This
rounds outer corners and fills inner corners — turning chargen's
chunky 8×8 staircases into smooth 24×21 slopes.

Slot layout (matches greets.asm:ptr_lookup):
    $20-$39: A-Z       (chargen codes $41-$5A, set B uppercase)
    $3A:     blank     (64 zero bytes — default for unmapped chars)
    $3B:     hyphen    (chargen $2D)
    $3C:     digit '0' (chargen $30)
    $3D:     digit '1' (chargen $31)
    $3E:     digit '2' (chargen $32)
    $3F:     digit '5' (chargen $35)

The 4 digit slots cover every digit in the current greets scroller
("WGI2015"). Adding more digits means freeing a slot first — the
2048-byte sprite-shape window is fully packed.
"""

import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARGEN = os.path.join(REPO, "parts/greets/chargen.bin")
OUT = os.path.join(REPO, "parts/greets/font.bin")


def glyph_8x8(chargen, code):
    """Read 8 bytes for `code` from set B ($0800 offset), return 64-pixel list."""
    base = 0x800 + code * 8
    pixels = []
    for row in range(8):
        b = chargen[base + row]
        for col in range(8):
            pixels.append((b >> (7 - col)) & 1)
    return pixels


def epx_upscale(src):
    """Apply EPX-3 upscaling: 8×8 → 24×24 binary buffer."""
    out = [[0] * 24 for _ in range(24)]
    for sy in range(8):
        for sx in range(8):
            p = src[sy * 8 + sx]
            n = src[(sy - 1) * 8 + sx] if sy > 0 else 0
            s = src[(sy + 1) * 8 + sx] if sy < 7 else 0
            w = src[sy * 8 + sx - 1] if sx > 0 else 0
            e = src[sy * 8 + sx + 1] if sx < 7 else 0
            nw = n if (n == w and n != p) else p
            ne = n if (n == e and n != p) else p
            sw = s if (s == w and s != p) else p
            se = s if (s == e and s != p) else p
            ox = sx * 3
            oy = sy * 3
            out[oy][ox]         = nw
            out[oy][ox + 1]     = p
            out[oy][ox + 2]     = ne
            out[oy + 1][ox]     = p
            out[oy + 1][ox + 1] = p
            out[oy + 1][ox + 2] = p
            out[oy + 2][ox]     = sw
            out[oy + 2][ox + 1] = p
            out[oy + 2][ox + 2] = se
    return out


def pack_24x21(out24):
    """Pack 24×24 → 21 rows × 3 bytes + 1 pad. Drop one sub-row at src-rows 2/5/7."""
    rows = []
    for src_row in range(8):
        max_sub = 2 if src_row in (2, 5, 7) else 3
        for sub_row in range(max_sub):
            y = src_row * 3 + sub_row
            b = [0, 0, 0]
            for col in range(24):
                if out24[y][col]:
                    b[col // 8] |= 1 << (7 - (col % 8))
            rows.extend(b)
    rows.append(0)  # pad to 64 bytes
    return bytes(rows)


def glyph_bin(chargen, code):
    return pack_24x21(epx_upscale(glyph_8x8(chargen, code)))


def main():
    with open(CHARGEN, "rb") as f:
        chargen = f.read()

    blob = bytearray()
    # Slots $20-$39: A-Z (chargen $41-$5A)
    for c in range(0x41, 0x5B):
        blob += glyph_bin(chargen, c)
    # Slot $3A: blank
    blob += bytes(64)
    # Slot $3B: hyphen
    blob += glyph_bin(chargen, 0x2D)
    # Slots $3C-$3F: digits 0, 1, 2, 5
    for d in (0x30, 0x31, 0x32, 0x35):
        blob += glyph_bin(chargen, d)

    assert len(blob) == 2048, f"Expected 2048 bytes, got {len(blob)}"

    with open(OUT, "wb") as f:
        f.write(blob)
    print(f"wrote {OUT} ({len(blob)} bytes, 32 slots × 64 B)")


if __name__ == "__main__":
    main()
