#!/usr/bin/env python3
"""
Convert defeest_logo.png to C64 Koala multicolour bitmap.

Output Koala PRG layout (matches KickAss BF_KOALA):
  $00-$01: load address $6000
  $0000-$1f3f: bitmap (8000 bytes)
  $1f40-$2327: screen RAM (1000 bytes)
  $2328-$2710: color RAM (1000 bytes)
  $2711: background colour byte

Uniform colour layout — every cell uses the same 4-colour slot set:
  %00 = black  (bg, $d021)
  %01 = blue   (screen RAM hi nibble = 6)
  %10 = yellow (screen RAM lo nibble = 7)
  %11 = white  (color RAM lo nibble = 1)
"""
from PIL import Image
import sys

C64_RGB = {
    0x00: (0, 0, 0),
    0x01: (255, 255, 255),
    0x06: (0, 0, 170),
    0x07: (238, 238, 119),
}

# Our slots: %00=bg, %01,%10 from screen RAM nibbles, %11 from colour RAM
SLOT_COLORS = [0x00, 0x06, 0x07, 0x01]


def nearest_slot(rgb):
    r, g, b = rgb[:3]
    best_slot = 0
    best_d = 1 << 30
    for slot, c64 in enumerate(SLOT_COLORS):
        cr, cg, cb = C64_RGB[c64]
        d = (r - cr) ** 2 + (g - cg) ** 2 + (b - cb) ** 2
        if d < best_d:
            best_d = d
            best_slot = slot
    return best_slot


def main(in_path, out_path):
    img = Image.open(in_path).convert('RGBA')
    # Composite onto black bg
    bg = Image.new('RGB', img.size, (0, 0, 0))
    bg.paste(img, mask=img.split()[3])
    src_w, src_h = bg.size

    # MCM bitmap mode has logical pixels that are 2 hw px wide × 1 hw
    # tall. The koala canvas is 160 logical wide × 200 logical tall =
    # 320 hw × 200 hw. So:
    #   - Halve the width (every 2 hw px → 1 logical px)
    #   - Keep the height (each row maps 1:1)
    # NEAREST resample avoids LANCZOS averaging that would otherwise
    # turn white-on-black edges into mid-grey, which then maps to the
    # YELLOW slot (mid-grey is closer to yellow than to black/white in
    # RGB distance) — the "colour bleed" you'd otherwise see on text.
    # If the input is already 160 wide / ≤200 tall (a "native" canvas),
    # there's no downsample; the centred paste still positions it.
    if src_w > 320 or src_h > 200:
        # Oversized input — fit inside the 320×200 hardware frame first.
        scale = min(320 / src_w, 200 / src_h)
        bg = bg.resize((int(src_w * scale), int(src_h * scale)), Image.NEAREST)
        src_w, src_h = bg.size

    new_w = max(1, src_w // 2)
    new_h = src_h
    resized = bg.resize((new_w, new_h), Image.NEAREST) if new_w != src_w else bg
    # Center on 160×200 canvas
    canvas = Image.new('RGB', (160, 200), (0, 0, 0))
    off_x = (160 - new_w) // 2
    off_y = (200 - new_h) // 2
    canvas.paste(resized, (off_x, off_y))

    bitmap = bytearray(8000)
    # Build bitmap: 40 cells wide × 25 rows tall, each cell = 8 bytes
    for cell_y in range(25):
        for cell_x in range(40):
            cell_off = (cell_y * 40 + cell_x) * 8
            for row in range(8):
                y = cell_y * 8 + row
                byte = 0
                for px in range(4):
                    x = cell_x * 4 + px
                    slot = nearest_slot(canvas.getpixel((x, y)))
                    byte |= slot << ((3 - px) * 2)
                bitmap[cell_off + row] = byte

    screen = bytes([0x67] * 1000)
    color_ram = bytes([0x01] * 1000)

    with open(out_path, 'wb') as f:
        f.write(b'\x00\x60')          # load addr $6000
        f.write(bitmap)
        f.write(screen)
        f.write(color_ram)
        f.write(b'\x00')              # bg = black
    total = 2 + 8000 + 1000 + 1000 + 1
    print(f'wrote {out_path}: {total} bytes')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
