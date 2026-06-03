#!/usr/bin/env python3
"""
Export a FULL Koala .kla as a 320x200 paletted PNG (all 25 char rows),
using the Pepto C64 palette. The counterpart to png_to_koala.py.

Useful for editing in MultiPaint, which imports PNG (it only *saves*
koala, it can't open one). Open the PNG, edit, save back as koala.

  python3 tools/koala_to_png.py parts/intro/defeest.kla /tmp/defeest_full.png

The intro logo lives in char rows 8-16 (pixel rows 64-135); everything
else in this canvas is background and ignored by the demo.
"""
from PIL import Image
import sys

# Pepto PAL C64 palette (index = C64 colour number) — matches koala_to_logo_png.py.
C64_PALETTE = [
    (0, 0, 0), (255, 255, 255), (136, 57, 57), (103, 182, 189),
    (139, 79, 171), (80, 175, 75), (64, 64, 173), (199, 196, 126),
    (175, 91, 52), (116, 76, 34), (190, 126, 127), (87, 87, 87),
    (138, 138, 138), (150, 207, 142), (151, 143, 201), (173, 157, 120),
]
WIDTH_CHARS = 40
ROWS_CHARS = 25
PIXEL_W = WIDTH_CHARS * 8   # 320
PIXEL_H = ROWS_CHARS * 8    # 200


def read_koala(path):
    with open(path, 'rb') as f:
        data = f.read()
    if len(data) < 2 + 8000 + 1000 + 1000 + 1:
        raise ValueError(f"File too small for Koala ({len(data)} bytes)")
    off = 2
    bitmap = data[off:off + 8000]; off += 8000
    screen = data[off:off + 1000]; off += 1000
    color = data[off:off + 1000]; off += 1000
    bg = data[off]
    return bitmap, screen, color, bg


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.kla> <output.png>", file=sys.stderr)
        sys.exit(1)
    bitmap, screen, color, bg = read_koala(sys.argv[1])
    img = Image.new('P', (PIXEL_W, PIXEL_H))
    img.putpalette([c for rgb in C64_PALETTE for c in rgb])
    for cy in range(ROWS_CHARS):
        for cx in range(WIDTH_CHARS):
            sb = screen[cy * 40 + cx]
            cb = color[cy * 40 + cx]
            slot_col = {0: bg, 1: (sb >> 4) & 0x0f, 2: sb & 0x0f, 3: cb & 0x0f}
            cell_off = (cy * 40 + cx) * 8
            for row in range(8):
                bv = bitmap[cell_off + row]
                for px in range(4):
                    col = slot_col[(bv >> ((3 - px) * 2)) & 3]
                    x = cx * 8 + px * 2
                    y = cy * 8 + row
                    img.putpixel((x, y), col)
                    img.putpixel((x + 1, y), col)
    img.save(sys.argv[2])
    print(f"wrote {sys.argv[2]}: {PIXEL_W}x{PIXEL_H}, bg=${bg:02x} ({C64_PALETTE[bg]})")


if __name__ == '__main__':
    main()
