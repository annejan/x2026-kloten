#!/usr/bin/env python3
"""
font_png.py — round-trip parts/greets/font.bin ↔ parts/greets/font.png.

Spritemate (and most other sprite editors) can't load the raw 2048-byte
sprite blob that the greets pefchain loader expects, but they all do
PNG. This script gives you that round-trip:

    python3 tools/font_png.py export    # font.bin → font.png
    python3 tools/font_png.py import    # font.png → font.bin

Workflow:
    1. python3 tools/font_png.py export
    2. In Spritemate (https://www.spritemate.com/):
         File → New Project (32 sprites, hi-res, single-colour)
         File → Import Image or Spritesheet (*.png), pick font.png,
         configure cell size 24×21, 8 columns × 4 rows.
       Or in GIMP / Aseprite / MultiPaint / any image editor: just open
       font.png and edit.
    3. Save / export back as PNG at the same dimensions (192×84 px,
       1-bit black-and-white grid). Overwrite font.png.
    4. python3 tools/font_png.py import
    5. ./build.sh

PNG layout: 8 columns × 4 rows of 24×21 sprite cells, no gutters.
    row 0: slots $20-$27   = A B C D E F G H
    row 1: slots $28-$2F   = I J K L M N O P
    row 2: slots $30-$37   = Q R S T U V W X
    row 3: slots $38-$3F   = Y Z blank - 0 1 2 5

Pixels: white (1) = sprite pixel ON, black (0) = transparent.
The PNG is 1-bit paletted; any palette mapping where index 0 = off /
index 1 = on round-trips cleanly.
"""

import os
import sys
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(REPO, "parts/greets/font.bin")
PNG = os.path.join(REPO, "parts/greets/font.png")

COLS = 8
ROWS = 4
SPRITE_W = 24
SPRITE_H = 21
IMG_W = COLS * SPRITE_W            # 192
IMG_H = ROWS * SPRITE_H            # 84
SPRITE_COUNT = COLS * ROWS         # 32
SPRITE_BYTES = 64


def export_bin_to_png():
    with open(BIN, "rb") as f:
        data = f.read()
    if len(data) != SPRITE_COUNT * SPRITE_BYTES:
        raise SystemExit(
            f"{BIN} is {len(data)} bytes, expected {SPRITE_COUNT * SPRITE_BYTES}"
        )

    img = Image.new("1", (IMG_W, IMG_H), 0)
    px = img.load()
    for slot in range(SPRITE_COUNT):
        col = slot % COLS
        row = slot // COLS
        ox = col * SPRITE_W
        oy = row * SPRITE_H
        sprite = data[slot * SPRITE_BYTES:(slot + 1) * SPRITE_BYTES]
        for y in range(SPRITE_H):
            r0, r1, r2 = sprite[y * 3], sprite[y * 3 + 1], sprite[y * 3 + 2]
            for x in range(SPRITE_W):
                b = (r0, r1, r2)[x // 8]
                if (b >> (7 - (x % 8))) & 1:
                    px[ox + x, oy + y] = 1
    img.save(PNG, "PNG")
    print(f"wrote {PNG} ({IMG_W}×{IMG_H} px, {SPRITE_COUNT} sprites)")


def import_png_to_bin():
    img = Image.open(PNG).convert("1")
    if img.size != (IMG_W, IMG_H):
        raise SystemExit(
            f"{PNG} is {img.size[0]}×{img.size[1]} px, expected {IMG_W}×{IMG_H}"
        )
    px = img.load()

    blob = bytearray()
    for slot in range(SPRITE_COUNT):
        col = slot % COLS
        row = slot // COLS
        ox = col * SPRITE_W
        oy = row * SPRITE_H
        for y in range(SPRITE_H):
            for bytecol in range(3):
                b = 0
                for bit in range(8):
                    x = bytecol * 8 + bit
                    if px[ox + x, oy + y]:
                        b |= 1 << (7 - bit)
                blob.append(b)
        blob.append(0)  # pad to 64

    if len(blob) != SPRITE_COUNT * SPRITE_BYTES:
        raise SystemExit(f"internal: produced {len(blob)} bytes")
    with open(BIN, "wb") as f:
        f.write(blob)
    print(f"wrote {BIN} ({len(blob)} bytes)")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("export", "import"):
        print(__doc__)
        sys.exit(1)
    if sys.argv[1] == "export":
        export_bin_to_png()
    else:
        import_png_to_bin()


if __name__ == "__main__":
    main()
