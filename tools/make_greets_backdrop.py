#!/usr/bin/env python3
"""
Generate parts/greets/backdrop.png — a 320x200 placeholder backdrop
for the greets DYCP scroller. Layout:

  black bg
  dark blue centre band (rows 9-16, behind where the sprites scroll)
  white "GREETINGS TO" at the top
  white "THE LEGENDS" at the bottom

Re-run this any time the layout / text needs to change. After running,
convert to .kla with:

  python3 tools/png_to_koala.py parts/greets/backdrop.png \\
      parts/greets/backdrop.kla

Then point greets.asm's LoadBinary at backdrop.kla.

Pixel font comes from parts/greets/chargen.bin (the C64 uppercase ROM)
scaled 2x horizontally so each chargen pixel survives png_to_koala's
160-wide resize without aliasing.
"""
from PIL import Image
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
CHARGEN = (ROOT / "parts/greets/chargen.bin").read_bytes()
OUT_PNG = ROOT / "parts/greets/backdrop.png"

# C64 Pepto palette (16 colours).
PEPTO = [
    (0, 0, 0), (255, 255, 255), (136, 57, 50), (103, 182, 189),
    (139, 63, 150), (85, 160, 73), (64, 49, 141), (191, 206, 114),
    (139, 84, 41), (87, 66, 0), (184, 105, 98), (80, 80, 80),
    (120, 120, 120), (148, 224, 137), (120, 105, 196), (159, 159, 159),
]


def render_letter(img, ch, x, y, color):
    """Draw a single letter at (x, y) using chargen bytes scaled 2x wide."""
    if ch == ' ':
        return
    # Charset 1 (uppercase + graphics) screencode for A-Z is $01-$1A.
    sc = ord(ch.upper()) - 0x40
    if sc < 1 or sc > 26:
        return
    off = sc * 8
    for row in range(8):
        byte = CHARGEN[off + row]
        for bit in range(8):
            if byte & (0x80 >> bit):
                px = x + bit * 2
                img.putpixel((px, y + row), color)
                img.putpixel((px + 1, y + row), color)


def render_text(img, text, centre_x, y, color):
    """Draw a string of letters centred horizontally at centre_x."""
    width = len(text) * 16
    x = centre_x - width // 2
    for i, ch in enumerate(text):
        render_letter(img, ch, x + i * 16, y, color)


def main():
    img = Image.new('P', (320, 200), color=0)
    palette = []
    for r, g, b in PEPTO:
        palette.extend([r, g, b])
    palette.extend([0] * (768 - len(palette)))
    img.putpalette(palette)

    # ---- Dark blue centre band ----
    # Rows 9-16 (y = 72..136) covers where the DYCP sprites scroll at
    # raster Y=130 ± wobble. The band frames the scroller in blue.
    for y in range(72, 136):
        for x in range(0, 320):
            img.putpixel((x, y), 6)  # blue ($06)

    # ---- White text top: "GREETINGS TO" ----
    # Row 3 (y = 24) — well above the blue band, in the black top
    # strip. Centred horizontally.
    render_text(img, "GREETINGS TO", 160, 24, 1)

    # ---- White text bottom: "THE LEGENDS" ----
    # Row 22 (y = 176) — well below the blue band, in the black
    # bottom strip. Centred horizontally.
    render_text(img, "THE LEGENDS", 160, 176, 1)

    img.save(OUT_PNG)
    print(f'wrote {OUT_PNG}')


if __name__ == '__main__':
    main()
