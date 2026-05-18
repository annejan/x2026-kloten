#!/usr/bin/env python3
"""
Export character rows 8-16 (the DEFEEST logo) from a Koala .kla file
as a paletted 320x72 PNG for hand-pixel editing.

Usage:
  python3 tools/koala_to_logo_png.py parts/screenfill/defeest.kla /tmp/logo.png

The PNG uses the Pepto C64 palette so colours appear correct in any
indexed-PNG viewer (Aseprite, GrafX2, GIMP, etc.).
"""
from PIL import Image
import struct
import sys

# Pepto PAL C64 palette (R, G, B) — the most accurate for PAL machines.
C64_PALETTE = [
    (0, 0, 0),         # 0  black
    (255, 255, 255),   # 1  white
    (136, 57, 57),     # 2  red
    (103, 182, 189),   # 3  cyan
    (139, 79, 171),    # 4  purple
    (80, 175, 75),     # 5  green
    (64, 64, 173),     # 6  blue
    (199, 196, 126),   # 7  yellow
    (175, 91, 52),     # 8  orange
    (116, 76, 34),     # 9  brown
    (190, 126, 127),   # 10 pink
    (87, 87, 87),      # 11 dark grey
    (138, 138, 138),   # 12 medium grey
    (150, 207, 142),   # 13 light green
    (151, 143, 201),   # 14 light blue
    (173, 157, 120),   # 15 light yellow
]

# Character rows 8-16 (pixel rows 64-135)
FIRST_CHAR_ROW = 8
LAST_CHAR_ROW = 16   # inclusive
LOGO_CHAR_ROWS = LAST_CHAR_ROW - FIRST_CHAR_ROW + 1  # 9
WIDTH_CHARS = 40
PIXEL_W = WIDTH_CHARS * 8         # 320
PIXEL_H = LOGO_CHAR_ROWS * 8      # 72


def read_koala(path: str) -> tuple[bytes, bytes, bytes, int]:
    """Read a Koala .kla/.prg file; return (bitmap, screen, color, bg)."""
    with open(path, 'rb') as f:
        data = f.read()
    # Koala PRG: 2-byte load address + 8000 bitmap + 1000 screen + 1000 color + 1 bg
    if len(data) < 2 + 8000 + 1000 + 1000 + 1:
        raise ValueError(f"File too small for Koala ({len(data)} bytes)")
    off = 2  # skip load address
    bitmap = data[off:off + 8000]
    off += 8000
    screen = data[off:off + 1000]
    off += 1000
    color = data[off:off + 1000]
    off += 1000
    bg = data[off]
    return bitmap, screen, color, bg


def decode_cell(bitmap: bytes, screen_byte: int, color_byte: int, bg: int,
                cell_x: int, cell_y: int) -> list[list[int]]:
    """
    Decode one 8x8 character cell into an 8x8 list of C64 colour indices.

    Returns: 8 rows, each a list of 8 colour indices (hardware pixels).
    """
    # Slot-to-colour mapping for this cell
    slot_col = {
        0: bg,
        1: (screen_byte >> 4) & 0x0f,
        2: screen_byte & 0x0f,
        3: color_byte & 0x0f,
    }

    cell_off = (cell_y * 40 + cell_x) * 8
    rows = []
    for row in range(8):
        byte_val = bitmap[cell_off + row]
        # 4 multicolour pixels per byte, each 2 bits = slot index
        # bits 7-6 = pixel 0, bits 5-4 = pixel 1, ...
        hw_row = []
        for px in range(4):
            slot = (byte_val >> ((3 - px) * 2)) & 3
            col = slot_col[slot]
            # In multicolour mode each logical pixel is 2 hardware pixels wide
            hw_row.append(col)
            hw_row.append(col)
        rows.append(hw_row)
    return rows


def build_logo_image(bitmap: bytes, screen: bytes, color: bytes, bg: int) -> Image.Image:
    """Build a 320x72 paletted PIL Image of logo rows 8-16."""
    img = Image.new('P', (PIXEL_W, PIXEL_H))
    img.putpalette([c for rgb in C64_PALETTE for c in rgb])

    for local_row in range(LOGO_CHAR_ROWS):
        char_row = FIRST_CHAR_ROW + local_row
        for cell_x in range(WIDTH_CHARS):
            screen_byte = screen[char_row * 40 + cell_x]
            color_byte = color[char_row * 40 + cell_x]
            cell_pixels = decode_cell(bitmap, screen_byte, color_byte, bg,
                                      cell_x, char_row)
            for py in range(8):
                for px in range(8):
                    x = cell_x * 8 + px
                    y = local_row * 8 + py
                    img.putpixel((x, y), cell_pixels[py][px])

    return img


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <defeest.kla> <output.png>", file=sys.stderr)
        sys.exit(1)

    bitmap, screen, color, bg = read_koala(sys.argv[1])
    img = build_logo_image(bitmap, screen, color, bg)
    img.save(sys.argv[2])
    print(f"wrote {sys.argv[2]}: {PIXEL_W}x{PIXEL_H}, bg=${bg:02x} "
          f"({C64_PALETTE[bg]})")


if __name__ == '__main__':
    main()
