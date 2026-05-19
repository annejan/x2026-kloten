#!/usr/bin/env python3
"""
render_kloot_star.py — pre-render the rotating Kloot star sprite for coda.

The shape: a Claude-style 4-point star (four sharp arms at the cardinal
directions, concave edges curving inward between them). Single-colour
C64 sprite (24×21 pixels, 1 bpp, 64 bytes per frame including 1 padding
byte at the end).

Because the star has 4-fold rotational symmetry, we only need to render
unique angles in the range 0°-90°; cycling through those frames at
50 Hz produces a perceived continuous rotation. We pre-render N_FRAMES
unique frames (default 16, ~5.625° apart) and emit them as a single
binary blob suitable for `.import binary "kloot_star.bin"` in
KickAssembler.

Outputs:
  - <out>.bin       raw sprite bytes, N_FRAMES * 64 bytes
  - <out>.png       N_FRAMES preview tiles in a single image for eyeballing

Usage:
  tools/render_kloot_star.py [-o parts/coda/kloot_star.bin]
                             [--preview /tmp/kloot_star_preview.png]
                             [--frames 16]
                             [--outer 11.0] [--inner 4.0]
                             [--curve 2.2]
"""

import argparse
import math
import os
import struct
import sys

SPRITE_W = 24
SPRITE_H = 21
BYTES_PER_FRAME = 64  # 24*21/8 = 63 + 1 trailing pad byte


def star_radius(theta: float, r_outer: float, r_inner: float, curve: float,
                r_diag: float = 0.0, diag_curve: float = 4.0,
                lobes: int = 4) -> float:
    """Polar radius for a Claude-style sparkle.

    Two superimposed N-fold petal functions:
      - Big petals at angles 0, 2π/lobes, 4π/lobes, ...: peak = r_outer.
      - Optional small petals halfway between, peak = r_diag.
    `curve` controls the sharpness of the big points; `diag_curve` controls
    the sharpness/size of the diagonal bumps. `lobes` sets the petal count
    (real Claude logo is 12; default 4 keeps the original 4-point look).

    A cos(N*θ) wave has 2N peaks of |·|, so we use freq = lobes/2 to get
    exactly `lobes` peaks per full revolution.
    """
    freq = lobes / 2.0
    big = abs(math.cos(freq * theta)) ** curve
    diag = abs(math.sin(freq * theta)) ** diag_curve
    return r_inner + (r_outer - r_inner) * big + r_diag * diag


def render_frame(angle_deg: float, r_outer: float, r_inner: float,
                 curve: float, r_diag: float = 0.0, diag_curve: float = 4.0,
                 lobes: int = 4, antialias_samples: int = 4,
                 quadrant: int = -1) -> bytes:
    """Render a single rotated star into 24×21 1bpp = 63 bytes + 1 pad.

    `quadrant` = -1 (default): full star centred on the 24×21 sprite.
    `quadrant` = 0/1/2/3 (Stage B): renders ONE quadrant of a logical
    48×42 star. The four tiles can be arranged in a 2×2 grid on screen
    to form a sharp double-size star. Quadrant numbering matches sprite
    position when placed in the 2×2 grid:

        +---------+---------+
        | spr 1   | spr 0   |
        | TL  q=1 | TR  q=0 |
        +---------+---------+
        | spr 2   | spr 3   |
        | BL  q=2 | BR  q=3 |
        +---------+---------+

    For quadrant Q, the full-star centre is placed just OUTSIDE the
    sprite in the opposite corner — so all sprite pixels fall in the
    correct quadrant of the full star.

    Pixel is ON if its centre lies inside the star's polar boundary at
    the rotated angle. Light box-filter supersampling is used to anti-
    alias the boundary, then thresholded back to 1bpp at 50% coverage.
    """
    if quadrant < 0:
        cx = (SPRITE_W - 1) / 2.0
        cy = (SPRITE_H - 1) / 2.0
    elif quadrant == 0:    # top-right of star → centre at left-bottom of sprite
        cx, cy = -0.5, SPRITE_H - 0.5
    elif quadrant == 1:    # top-left of star → centre at right-bottom of sprite
        cx, cy = SPRITE_W - 0.5, SPRITE_H - 0.5
    elif quadrant == 2:    # bottom-left of star → centre at right-top of sprite
        cx, cy = SPRITE_W - 0.5, -0.5
    elif quadrant == 3:    # bottom-right of star → centre at left-top of sprite
        cx, cy = -0.5, -0.5
    else:
        raise ValueError(f"quadrant must be -1..3, got {quadrant}")
    rot = math.radians(angle_deg)

    out = bytearray(BYTES_PER_FRAME)
    inv_step = 1.0 / antialias_samples
    sub_offsets = [(i + 0.5) * inv_step - 0.5 for i in range(antialias_samples)]

    for py in range(SPRITE_H):
        for px in range(SPRITE_W):
            covered = 0
            for sy in sub_offsets:
                for sx in sub_offsets:
                    dx = (px + sx) - cx
                    dy = (py + sy) - cy
                    if dx == 0 and dy == 0:
                        covered += 1
                        continue
                    r = math.hypot(dx, dy)
                    theta = math.atan2(dy, dx) - rot
                    if r <= star_radius(theta, r_outer, r_inner, curve,
                                        r_diag, diag_curve, lobes):
                        covered += 1
            total = antialias_samples * antialias_samples
            if covered * 2 >= total:  # ≥ 50% coverage → pixel ON
                bit_index = py * SPRITE_W + px
                byte_index = bit_index // 8
                bit_in_byte = 7 - (bit_index % 8)
                out[byte_index] |= 1 << bit_in_byte
    return bytes(out)


def write_preview_png(frames: list[bytes], path: str, fg=(217, 119, 87),
                      bg=(20, 20, 28), gap=2, scale=4) -> None:
    """Write a single PNG mosaic with all frames laid out in a row.

    Pure stdlib — no Pillow dependency. Emits an 8-bit RGBA PNG.
    """
    import zlib

    n = len(frames)
    tile_w = SPRITE_W * scale
    tile_h = SPRITE_H * scale
    img_w = n * tile_w + (n + 1) * gap
    img_h = tile_h + 2 * gap

    # Build raw RGBA scanlines (filter byte 0 per row).
    fg_bytes = bytes([*fg, 255])
    bg_bytes = bytes([*bg, 255])
    raw = bytearray()
    for y in range(img_h):
        raw.append(0)  # filter: None
        for x in range(img_w):
            # Locate the tile this pixel falls into.
            xt = x - gap
            yt = y - gap
            if yt < 0 or yt >= tile_h:
                raw.extend(bg_bytes)
                continue
            tile_idx = xt // (tile_w + gap)
            x_in_strip = xt - tile_idx * (tile_w + gap)
            if (0 <= tile_idx < n and 0 <= x_in_strip < tile_w):
                px = x_in_strip // scale
                py = yt // scale
                bit_index = py * SPRITE_W + px
                byte_index = bit_index // 8
                bit_in_byte = 7 - (bit_index % 8)
                if frames[tile_idx][byte_index] & (1 << bit_in_byte):
                    raw.extend(fg_bytes)
                else:
                    raw.extend(bg_bytes)
            else:
                raw.extend(bg_bytes)

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xffffffff
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", img_w, img_h, 8, 6, 0, 0, 0)  # RGBA, no interlace
    idat = zlib.compress(bytes(raw), 9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    p.add_argument("-o", "--output", default="parts/coda/kloot_star.bin",
                   help="Output .bin path (default: %(default)s)")
    p.add_argument("--preview", default="/tmp/kloot_star_preview.png",
                   help="Output preview PNG path (default: %(default)s)")
    p.add_argument("--frames", type=int, default=16,
                   help="Number of rotation frames (default: %(default)s)")
    p.add_argument("--outer", type=float, default=11.0,
                   help="Outer radius in px (default: %(default)s)")
    p.add_argument("--inner", type=float, default=3.5,
                   help="Inner radius in px — smaller = sharper points "
                        "(default: %(default)s)")
    p.add_argument("--curve", type=float, default=2.2,
                   help="Point sharpness exponent — higher = sharper "
                        "(default: %(default)s)")
    p.add_argument("--diag", type=float, default=0.0,
                   help="Extra radius for the small diagonal sparkle bumps "
                        "(default: %(default)s = none, pure 4-point star)")
    p.add_argument("--diag-curve", type=float, default=4.0,
                   help="Sharpness exponent for the diagonal bumps "
                        "(default: %(default)s)")
    p.add_argument("--lobes", type=int, default=4,
                   help="Number of star points (real Claude logo = 12; "
                        "default: %(default)s)")
    p.add_argument("--quadrant", type=int, default=-1, choices=[-1, 0, 1, 2, 3],
                   help="-1 = full star centred (default). 0/1/2/3 = render "
                        "one tile of a logical 48×42 star, suitable for a "
                        "2×2 sprite cluster (Stage B). 0=TR, 1=TL, 2=BL, 3=BR.")
    args = p.parse_args()

    # N-fold symmetric star: unique frames span 0..(360/lobes)°.
    # 4 lobes → 90°/frame_set; 12 lobes → 30°/frame_set.
    angle_step = (360.0 / args.lobes) / args.frames
    frames = []
    for i in range(args.frames):
        angle = i * angle_step
        frame = render_frame(angle, args.outer, args.inner, args.curve,
                             args.diag, args.diag_curve, args.lobes,
                             quadrant=args.quadrant)
        frames.append(frame)

    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "wb") as f:
        for frame in frames:
            f.write(frame)
    print(f"wrote {len(frames) * BYTES_PER_FRAME} bytes "
          f"({len(frames)} frames × {BYTES_PER_FRAME} bytes) → {args.output}")

    if args.preview:
        write_preview_png(frames, args.preview)
        print(f"preview → {args.preview}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
