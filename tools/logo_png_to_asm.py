#!/usr/bin/env python3
"""
Convert an artist-edited 320×72 paletted PNG back into C64 multicolour
bitmap data and per-cell colour info for the intro.

Usage:
  python3 tools/logo_png_to_asm.py /tmp/logo_edited.png parts/intro/logo_rows.asm

On output:
  - Writes logo_rows.asm with the 2880-byte bitmap data
  - Prints the per-cell screen-RAM and colour-RAM values to stdout so
    you can update intro.asm if colours changed.

Requirements:
  The PNG must use C64 colour indices (0-15) in its palette matching the
  Pepto palette (or any 16-entry palette where index = C64 colour number).

Encoding:
  Each 8×8 character cell picks its 4-colour slot assignment based on
  the dominant colours within that cell. The globally most-frequent
  colour becomes background (%00). The remaining 3 top colours in each
  cell are assigned to %01 (screen hi), %10 (screen lo), %11 (colour RAM).
"""
from PIL import Image
from collections import Counter
import struct
import sys

FIRST_CHAR_ROW = 8
LAST_CHAR_ROW = 16
LOGO_CHAR_ROWS = LAST_CHAR_ROW - FIRST_CHAR_ROW + 1
WIDTH_CHARS = 40
WIDTH_PX = 320
HEIGHT_PX = 72


def analyse_image(path: str) -> tuple[Image.Image, list[list[Counter]]]:
    """Analyse the PNG: return image and per-cell colour counters."""
    img = Image.open(path)
    if img.mode != 'P':
        print(f"Error: image must be paletted (P) mode, got {img.mode}",
              file=sys.stderr)
        sys.exit(1)
    if img.size != (WIDTH_PX, HEIGHT_PX):
        print(f"Error: image must be {WIDTH_PX}x{HEIGHT_PX}, got {img.size}",
              file=sys.stderr)
        sys.exit(1)

    # Count colours per cell
    cell_counters: list[list[Counter]] = []
    for char_row in range(LOGO_CHAR_ROWS):
        row_counters: list[Counter] = []
        for cell_x in range(WIDTH_CHARS):
            counter: Counter = Counter()
            for py in range(8):
                y = char_row * 8 + py
                for px in range(8):
                    x = cell_x * 8 + px
                    c = img.getpixel((x, y))
                    counter[c] += 1
            row_counters.append(counter)
        cell_counters.append(row_counters)

    return img, cell_counters


def pick_global_bg(cell_counters: list[list[Counter]]) -> int:
    """Pick the globally most common colour as background (%00)."""
    global_counter: Counter = Counter()
    for row in cell_counters:
        for ctr in row:
            global_counter.update(ctr)
    bg, _ = global_counter.most_common(1)[0]
    return bg


def encode_cell(img: Image.Image, cell_x: int, char_row: int,
                counter: Counter, bg: int,
                existing_screen: bytes | None,
                existing_color: bytes | None) -> tuple[bytes, int, int, int]:
    """
    Encode one 8×8 cell.

    Returns: (8-byte bitmap row data, screen_byte, color_byte, bg).
    If existing_screen is provided, preserves the slot-to-colour mapping
    from the original koala.
    """
    # Determine slot assignments for this cell
    # Exclude bg from the top-3, then assign to slots 1,2,3
    if existing_screen is not None and existing_color is not None:
        off = char_row * 40 + cell_x
        slot_col = {
            1: (existing_screen[off] >> 4) & 0x0f,
            2: existing_screen[off] & 0x0f,
            3: existing_color[off] & 0x0f,
        }
    else:
        non_bg = [(c, cnt) for c, cnt in counter.items() if c != bg]
        non_bg.sort(key=lambda x: -x[1])
        slot_col = {}
        # Fill slots 1-3 with top non-bg colours
        for slot in [1, 2, 3]:
            if slot - 1 < len(non_bg):
                slot_col[slot] = non_bg[slot - 1][0]
            else:
                slot_col[slot] = bg  # unused slot → bg

    # Build reverse map: colour → slot
    col_to_slot = {bg: 0}
    for slot, col in slot_col.items():
        col_to_slot[col] = slot

    # Build 8 bitmap bytes
    cell_off = (char_row * 40 + cell_x) * 8
    bitmap_bytes = bytearray(8)
    for row in range(8):
        y = (char_row - FIRST_CHAR_ROW) * 8 + row
        byte_val = 0
        for px in range(4):
            # Grab two hardware pixels at once
            x = cell_x * 8 + px * 2
            # Get colour of left pixel (both should be same in multicolour)
            col = img.getpixel((x, y))
            slot = col_to_slot.get(col, 0)
            byte_val |= slot << ((3 - px) * 2)
        bitmap_bytes[row] = byte_val

    screen_byte = (slot_col[1] << 4) | slot_col[2]
    color_byte = slot_col[3]
    return bytes(bitmap_bytes), screen_byte, color_byte, bg


def main():
    if len(sys.argv) not in (3, 4):
        print(f"Usage: {sys.argv[0]} <input.png> <output_logo_rows.asm> "
              "[defeest.kla]", file=sys.stderr)
        print("", file=sys.stderr)
        print("If defeest.kla is provided, per-cell colour assignments from")
        print("the original koala are preserved (only bitmap data changes).", file=sys.stderr)
        print("Without it, colours are auto-assigned per cell.", file=sys.stderr)
        sys.exit(1)

    in_png = sys.argv[1]
    out_asm = sys.argv[2]
    kla_path = sys.argv[3] if len(sys.argv) > 3 else None

    img, cell_counters = analyse_image(in_png)
    bg = pick_global_bg(cell_counters)

    # Load existing koala colours if provided
    existing_screen = None
    existing_color = None
    if kla_path:
        with open(kla_path, 'rb') as f:
            data = f.read()
        existing_screen = data[2 + 8000: 2 + 8000 + 1000]
        existing_color = data[2 + 8000 + 1000: 2 + 8000 + 1000 + 1000]

    # Encode all cells
    all_bitmap = bytearray()
    screen_ram = bytearray(LOGO_CHAR_ROWS * WIDTH_CHARS)
    color_ram = bytearray(LOGO_CHAR_ROWS * WIDTH_CHARS)

    for local_row in range(LOGO_CHAR_ROWS):
        char_row = FIRST_CHAR_ROW + local_row
        for cell_x in range(WIDTH_CHARS):
            counter = cell_counters[local_row][cell_x]
            bmp, sc, cr, _ = encode_cell(
                img, cell_x, char_row, counter, bg,
                existing_screen, existing_color)
            all_bitmap.extend(bmp)
            screen_ram[local_row * WIDTH_CHARS + cell_x] = sc
            color_ram[local_row * WIDTH_CHARS + cell_x] = cr

    if len(all_bitmap) != LOGO_CHAR_ROWS * WIDTH_CHARS * 8:
        print(f"Error: bitmap length mismatch ({len(all_bitmap)})",
              file=sys.stderr)
        sys.exit(1)

    # Write logo_rows.asm
    with open(out_asm, 'w') as f:
        f.write(f";; Auto-generated from {in_png}\n")
        f.write(f";; background = ${bg:02x}\n")
        f.write(f";; {len(all_bitmap)} bytes of bitmap data (rows {FIRST_CHAR_ROW}-{LAST_CHAR_ROW})\n")
        f.write("logo_rows:\n")
        for i in range(0, len(all_bitmap), 16):
            chunk = all_bitmap[i:i + 16]
            bytes_str = ", ".join(f"${b:02x}" for b in chunk)
            f.write(f"  .byte {bytes_str}\n")

    # Print per-cell colour info for intro.asm
    print(f"Updated: {out_asm}")
    print(f"Background colour: ${bg:02x}")
    print()

    # Summarise screen/color RAM — only show non-uniform cells
    uniform_sc = screen_ram[0]
    uniform_cr = color_ram[0]
    non_uniform_sc = [(i, screen_ram[i]) for i in range(len(screen_ram))
                      if screen_ram[i] != uniform_sc]
    non_uniform_cr = [(i, color_ram[i]) for i in range(len(color_ram))
                      if color_ram[i] != uniform_cr]

    if not non_uniform_sc and not non_uniform_cr:
        print(f"Screen RAM: uniform ${uniform_sc:02x} (hi=${(uniform_sc>>4)&0xf:02x}, lo=${uniform_sc&0xf:02x})")
        print(f"Colour RAM: uniform ${uniform_cr:02x}")
    else:
        print("Non-uniform colour cells detected!")
        if non_uniform_sc:
            print(f"  Screen RAM deviations from ${uniform_sc:02x}:")
            for i, v in non_uniform_sc:
                row = i // WIDTH_CHARS
                col = i % WIDTH_CHARS
                print(f"    row+{row}, col {col}: ${v:02x}")
        if non_uniform_cr:
            print(f"  Colour RAM deviations from ${uniform_cr:02x}:")
            for i, v in non_uniform_cr:
                row = i // WIDTH_CHARS
                col = i % WIDTH_CHARS
                print(f"    row+{row}, col {col}: ${v:02x}")

    # Also show the screen_ram and color_ram as .byte arrays for easy insertion
    print()
    print("# Screen RAM (per-cell colour pair) for all 9 logo rows:")
    print(f".byte {', '.join(f'${b:02x}' for b in screen_ram)}")
    print()
    print("# Color RAM (per-cell colour 3) for all 9 logo rows:")
    print(f".byte {', '.join(f'${b:02x}' for b in color_ram)}")


if __name__ == '__main__':
    main()
