#!/usr/bin/env python3
"""
kloot_quad_preview.py — assemble the 4 quadrant .bin files into a
full-star composite PNG, one tile per frame, so the zoom + rotation
sequence is visible without running the demo.

Usage:
  tools/kloot_quad_preview.py [-o /tmp/kloot_quad.png] [-d parts/coda]
"""

import argparse
import os
import struct
import sys
import zlib

SPRITE_W = 24
SPRITE_H = 21
BYTES_PER_FRAME = 64
QUAD_W = SPRITE_W * 2   # 48
QUAD_H = SPRITE_H * 2   # 42


def read_bin(path: str) -> list[bytes]:
    """Return list of frames (each 64 bytes)."""
    with open(path, "rb") as f:
        data = f.read()
    n = len(data) // BYTES_PER_FRAME
    return [data[i * BYTES_PER_FRAME : (i + 1) * BYTES_PER_FRAME]
            for i in range(n)]


def pixel(frame: bytes, x: int, y: int) -> bool:
    """1bpp: is pixel (x, y) ON in a 24×21 sprite frame?"""
    bit_index = y * SPRITE_W + x
    return bool(frame[bit_index // 8] & (1 << (7 - bit_index % 8)))


def write_png(pixels: bytearray, w: int, h: int, path: str) -> None:
    raw = bytearray()
    row_bytes = w * 4
    for y in range(h):
        raw.append(0)  # filter
        raw.extend(pixels[y * row_bytes : (y + 1) * row_bytes])

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xffffffff
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
           chunk(b"IDAT", idat) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    p.add_argument("-d", "--dir", default="parts/coda",
                   help="Directory with kloot_star_{tr,tl,bl,br}.bin")
    p.add_argument("-o", "--output", default="/tmp/kloot_quad.png",
                   help="Output PNG path")
    p.add_argument("--scale", type=int, default=3,
                   help="Pixel scale factor for output")
    args = p.parse_args()

    # Layout in screen coords (matches coda.asm's sprite positions):
    #   Q1 (TL)  Q0 (TR)
    #   Q2 (BL)  Q3 (BR)
    # Each quadrant has the star centre at a specific sprite corner:
    #   TR: centre at sprite (0, 20)        → in composite at (24, 20)
    #   TL: centre at sprite (23, 20)       → in composite at (23, 20)
    #   BL: centre at sprite (23, 0)        → in composite at (23, 21)
    #   BR: centre at sprite (0, 0)         → in composite at (24, 21)
    # i.e. all four meet at composite (~23, ~20-21) — the centre seam.
    tr = read_bin(os.path.join(args.dir, "kloot_star_tr.bin"))
    tl = read_bin(os.path.join(args.dir, "kloot_star_tl.bin"))
    bl = read_bin(os.path.join(args.dir, "kloot_star_bl.bin"))
    br = read_bin(os.path.join(args.dir, "kloot_star_br.bin"))

    n_frames = min(len(tr), len(tl), len(bl), len(br))
    print(f"composite: {n_frames} frames, {QUAD_W}×{QUAD_H} each")

    scale = args.scale
    gap = 4
    tile_w = QUAD_W * scale
    tile_h = QUAD_H * scale
    img_w = n_frames * tile_w + (n_frames + 1) * gap
    img_h = tile_h + 2 * gap

    fg = bytes([0xc0, 0x70, 0x40, 0xff])   # brown-ish
    bg = bytes([0x14, 0x14, 0x1c, 0xff])
    pixels = bytearray(img_w * img_h * 4)
    for y in range(img_h):
        for x in range(img_w):
            i = (y * img_w + x) * 4
            pixels[i : i + 4] = bg

    def put_pixel(px: int, py: int, color: bytes) -> None:
        if 0 <= px < img_w and 0 <= py < img_h:
            i = (py * img_w + px) * 4
            pixels[i : i + 4] = color

    for f in range(n_frames):
        # composite frame f: assemble 4 quadrants into a 48×42 image
        # quad layout:  Q1 TL | Q0 TR
        #               Q2 BL | Q3 BR
        composite = [[False] * QUAD_W for _ in range(QUAD_H)]
        for sy in range(SPRITE_H):
            for sx in range(SPRITE_W):
                if pixel(tl[f], sx, sy):
                    composite[sy][sx] = True
                if pixel(tr[f], sx, sy):
                    composite[sy][sx + SPRITE_W] = True
                if pixel(bl[f], sx, sy):
                    composite[sy + SPRITE_H][sx] = True
                if pixel(br[f], sx, sy):
                    composite[sy + SPRITE_H][sx + SPRITE_W] = True

        # render this tile into the output image with scale
        tile_x0 = gap + f * (tile_w + gap)
        tile_y0 = gap
        for cy in range(QUAD_H):
            for cx in range(QUAD_W):
                if composite[cy][cx]:
                    for dy in range(scale):
                        for dx in range(scale):
                            put_pixel(tile_x0 + cx * scale + dx,
                                      tile_y0 + cy * scale + dy, fg)

    write_png(pixels, img_w, img_h, args.output)
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
