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
                lobes: int = 4,
                petal_lengths: list[float] | None = None) -> float:
    """Polar radius for a Claude-style sparkle.

    Two superimposed N-fold petal functions:
      - Big petals at angles 0, 2π/lobes, 4π/lobes, ...: peak = r_outer.
      - Optional small petals halfway between, peak = r_diag.
    `curve` controls the sharpness of the big points; `diag_curve` controls
    the sharpness/size of the diagonal bumps. `lobes` sets the petal count
    (real Claude logo is 12; default 4 keeps the original 4-point look).

    `petal_lengths` (Stage D) is an optional list of `lobes` per-petal
    radius multipliers. If supplied, the big-petal peak at petal `k` is
    `r_outer * petal_lengths[k]` instead of a uniform `r_outer`. Use a
    seeded random walk to break the clean radial symmetry while keeping
    the petals readable.

    A cos(N*θ) wave has 2N peaks of |·|, so we use freq = lobes/2 to get
    exactly `lobes` peaks per full revolution.
    """
    freq = lobes / 2.0
    big = abs(math.cos(freq * theta)) ** curve
    diag = abs(math.sin(freq * theta)) ** diag_curve

    if petal_lengths is not None:
        # Identify which lobe `theta` is closest to (0..lobes-1) and use
        # that petal's length multiplier. The boundaries between petals
        # fall in the cos zero-crossings, where `big` is ~0, so the
        # discontinuity between adjacent petal multipliers doesn't show.
        sector = math.pi / lobes  # half the angular width of one petal
        # Wrap theta into [0, 2π) then find the nearest petal centre.
        theta_wrapped = theta % (2.0 * math.pi)
        petal_idx = int((theta_wrapped + sector) // (2.0 * sector)) % lobes
        r_peak = r_outer * petal_lengths[petal_idx]
    else:
        r_peak = r_outer

    return r_inner + (r_peak - r_inner) * big + r_diag * diag


def render_frame(angle_deg: float, r_outer: float, r_inner: float,
                 curve: float, r_diag: float = 0.0, diag_curve: float = 4.0,
                 lobes: int = 4, antialias_samples: int = 4,
                 quadrant: int = -1,
                 petal_lengths: list[float] | None = None) -> bytes:
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
                                        r_diag, diag_curve, lobes,
                                        petal_lengths):
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
    p.add_argument("--breath", type=float, default=0.0,
                   help="Breath amplitude (Stage C). 0 = no modulation "
                        "(default); positive = pixels of outer-radius "
                        "modulation per frame. The radius traces one full "
                        "sine cycle across the frame set, so star pulses "
                        "in time with rotation. Try ~2.0-3.0 for a clear "
                        "breath at outer=22.")
    p.add_argument("--asymmetry", type=float, default=0.0,
                   help="Per-petal length jitter (Stage D). 0 = uniform "
                        "petals (default); 0.4 = each petal's length "
                        "multiplier is in [0.8, 1.2]. Combined with "
                        "--seed for reproducible asymmetric layouts.")
    p.add_argument("--seed", type=int, default=0,
                   help="RNG seed for per-petal length jitter (--asymmetry). "
                        "Same seed → same star layout across re-runs.")
    args = p.parse_args()

    # Stage D asymmetry: pre-compute per-petal length multipliers if
    # --asymmetry > 0. Uniform petals (None) keeps the original radial
    # symmetry. With asymmetry, each petal gets a multiplier in
    # [1 − amp/2, 1 + amp/2]; the breath modulation still applies
    # globally on top of these per-petal values.
    if args.asymmetry > 0.0:
        import random as _random
        rng = _random.Random(args.seed)
        petal_lengths = [
            1.0 + (rng.random() - 0.5) * args.asymmetry
            for _ in range(args.lobes)
        ]
    else:
        petal_lengths = None

    # With asymmetric petals, the star no longer has N-fold rotational
    # symmetry — each rotation angle is visually distinct. Unique frames
    # then span 0..360°. With uniform petals, the cos(N·θ/2) function
    # gives N-fold symmetry and we only need 0..(360/N)°.
    if petal_lengths is not None:
        angle_step = 360.0 / args.frames
    else:
        # N-fold symmetric: 4 lobes → 90°/frame_set; 12 lobes → 30°/frame_set.
        angle_step = (360.0 / args.lobes) / args.frames

    frames = []
    for i in range(args.frames):
        angle = i * angle_step
        # Stage C breath: modulate outer radius across frames so one
        # rotation cycle = one breath cycle. cos goes 1 → −1 → 1, so
        # outer = base − amp*(1 − cos)/2 = base at frame 0, base−amp at
        # frame N/2, base at frame N. Looks like an inhale/exhale.
        if args.breath > 0.0:
            breath_phase = i * 2.0 * math.pi / args.frames
            outer = args.outer - args.breath * 0.5 * (1.0 - math.cos(breath_phase))
        else:
            outer = args.outer
        frame = render_frame(angle, outer, args.inner, args.curve,
                             args.diag, args.diag_curve, args.lobes,
                             quadrant=args.quadrant,
                             petal_lengths=petal_lengths)
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
