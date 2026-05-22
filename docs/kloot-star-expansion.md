# Kloot star — design history + current render params

> **Quick orientation if you're new to this file:**
> The Kloot star is the brown sparkle in coda. Everything below is
> design history. The CURRENT runtime architecture is summarised
> right under this paragraph — read that first, dive into stage A/B
> only if you need the back-story.

## Current state (as of 2026-05-21, post Stage F + parallax + NMI fix)

The coda runs **TWO** Kloot stars on screen at once + a 32-star
parallax PETSCII starfield. The whole effect is built on the Stage E
pre-rendered zoom shape data plus the Stage F ping-pong counter on
top of it:

- **6 KB shape data** at `$2000-$37FF` — 4 quadrants × 24 frames × 64 B.
  Each 24-frame sequence = **8 zoom** (small → full with rotation
  built in) + **16 steady-rotation** frames. Pre-rendered with
  `tools/render_kloot_star.py` using the params in the "Current
  render command" section below (asymmetric 12-lobe Claude-style
  sparkle with breath modulation). Both stars share this same data —
  the difference is per-star X/Y positions, per-star shape counters,
  and per-star ping-pong direction.
- **Star 1** = sprites 0-3 (brown `$09`), **Star 2** = sprites 4-7
  (cyan `$0E`). Each has its own `kloot_shape_N` counter (0..23)
  advancing at independent rates (`SHAPE_DIV_1=3`, `SHAPE_DIV_2=2`
  ticks-per-step at the half-rate divider) → fundamentally different
  rotation speeds, lobes drift apart visually.
- **Stage F ping-pong zoom breath** (PR #33). Each star's
  `kloot_shape_N` walks `0 → 23 → 0` forever via a per-star direction
  byte (`kloot_dir_N`). Forward: zoom in (0..7) → rotate (8..23) →
  reverse. Backward: rotate in reverse (23..8) → zoom out (7..0) →
  reverse. Star 1 starts at shape=0 forward (opens with zoom-in);
  star 2 starts at shape=23 backward (opens with zoom-out). The two
  breaths are naturally out of phase — one shrinks while the other
  grows. Rotation reversal is invisible because the burst has 12-fold
  symmetry. Shared step routine `kloot_advance` indexed by `X = star
  number (0 or 1)` keeps the binary footprint manageable.
- **Orbital motion**: each star has its own `starN_orbit_phase`
  advancing per IRQ (`ORBIT_SPEED_1=1`, `ORBIT_SPEED_2=2`). Phase
  indexes a 256-byte sine table at `$0F00` (page-aligned — MUST end
  before `$1000` or it stomps the inherited intro music tables).
  X / Y offsets computed from sine + cosine (cosine via phase + 64
  offset).
- **Sprite-pointer writes** are now a 4-iteration Y-indexed loop over
  a `sprite_bases` table (one of the cost-recoveries from PR #33).
  Pointers re-written every IRQ at 50 Hz (commit `ae80273`) so the
  Spindle NMI loader can't pull the kloot quads off-screen.
- **Depth swap**: a `swap_flag` toggles which star is in front. The
  toggle fires on the bit-6 transition of (phase2 − phase1) — that
  happens every ~64 frames at max separation, so the swap is invisible
  (stars are far apart). Implementation also swaps the sprite slot
  assignments + colour registers so brown stays brown and cyan stays
  cyan regardless of which is in front.
- **In-front-of-text toggle**: `$D01B` flips between `$FF` (sprites
  behind text) and `$00` (sprites in front) on the same safe-window
  trigger. Stars appear to orbit through the title in 3D.
- **Parallax PETSCII starfield** (PR #31). 32 stars across 4 speed
  tiers (`tier_speed[]={3,5,8,14}` half-rate ticks per move), 4
  distinct chars (`+ * . ,`) and 4 colours (white / lt-grey /
  dk-grey / blue). Per half-rate tick each star's countdown advances;
  on zero the star erases its current col, decrements col with wrap
  `0→39`, draws the tier's char + colour at the new column. Title
  rows 11 and 13 are never assigned to any star so the drift passes
  above + below the centred title.

IRQ ordering inside coda's `interrupt`:
`orbital motion math → priority-swap detect → sprite position
writes (FIRST so VIC's per-raster sprite-Y check sees the new
positions before raster 52) → jsr my_music_play (now via the
`bit $0000` callmusic placeholder) → re-assert $D418 = $1F →
$D417 = $26 V2+V3 LP routing (V1 clean, res 2) → $D416 sin-LFO cutoff →
jsr star_field → half-rate state advance (`kloot_advance` called
twice with X=0, X=1) → sprite-pointer loop`.

(The dedicated `coda_kick` routine was removed when coda switched
to the resident K-S-K-S kit — see `docs/sid-drums.md`.)

EFO claims: `'P', $08, $0F` for code + state + col_tab + sin_tab
(8 pages), `'P', $20, $37` for the 6 KB Kloot-star shape data,
`'I', $10, $12` for inherited intro music.

## Current render command (Stage E)

The committed `parts/coda/kloot_star_*.bin` files are produced by:

```bash
for q in 0 1 2 3; do
  name=tr; case $q in 1) name=tl;; 2) name=bl;; 3) name=br;; esac
  python3 tools/render_kloot_star.py \
    --quadrant $q \
    --frames-zoom 8 \
    --frames 16 \
    --lobes 12 \
    --inner 2.5 \
    --curve 2.0 \
    --outer 22.0 \
    --asymmetry 0.4 \
    --seed 42 \
    --breath 4 \
    -o parts/coda/kloot_star_${name}.bin
done
```

Each `--quadrant 0..3` flag picks one tile of the 96×84 logical star.
`--asymmetry 0.4 --seed 42` is the magic that gave the star its
visible spikes — each of the 12 lobes gets a random multiplier in
`[0.8, 1.2]`, so the result reads as a recognisable Claude-style
sparkle rather than a smooth radial circle. **Without --asymmetry the
star reads as boring/circular** (user feedback 2026-05-20). Always
include these flags when re-rendering.

`--breath 4` modulates the outer radius across rotation frames →
inhale/exhale feel. `--frames-zoom 8` prepends 8 size-scaled frames
before the rotation set; coda walks the resulting 24-frame sequence
with wrap-to-8 so the zoom plays once, rotation loops forever.

---

# Bigger Kloot star — multi-sprite technical proposal

## Goal
Replace the single 24×21 sprite 0 in coda with a larger star using multiple sprites and/or sprite expansion. Target: ~48×42 with ~12 lobes instead of 4.

## Constraints
- Coda only: sprites 0-3 free (greets uses 0-7 but coda clears `$D015` in `setup`)
- Sprite pointers at `$07F8`–`$07FB`, X at `$D000`–`$D007`, Y at `$D001`–`$D009` (every other byte), colours at `$D027`–`$D02A`
- 64 bytes per sprite frame; data needs contiguous RAM block(s)
- `tools/render_kloot_star.py` generates the sprite shape from a polar function

## Stage A — sprite expansion (quick win, ~15 min)

Enable sprite 0 double-width (`$D01D` bit 0) + double-height (`$D017` bit 0). The 24×21 star becomes 48×42 with no new data — just two `ora` instructions:

```asm
// In setup, after sta $d015:
lda #$01
sta $d017         // sprite 0 double height
sta $d01d         // sprite 0 double width
```

Pixels go chunky (each original pixel is 2×2), but the anti-aliased render may still read as a sparkle. Adjust `KLOOT_X` from 64 to 40 (star is now 48 wide instead of 24, centre it better).

**If chunky look is acceptable, stop here.** Otherwise proceed to Stage B.

## Stage B — 4-sprite cluster (~2-3 hours)

Arrange 4 sprites as a 2×2 grid, each 24×21, forming a single 48×42 star:

```
+-------+-------+
| spr 1 | spr 0 |    sprite 0 = top-right quadrant
|       |       |    sprite 1 = top-left  quadrant
+-------+-------+    sprite 2 = bottom-left  quadrant
| spr 2 | spr 3 |    sprite 3 = bottom-right quadrant
+-------+-------+
```

### Renderer changes

Add a `--quadrant N` flag (0-3) to `tools/render_kloot_star.py` that shifts the origin so only 1/4 of the star falls within the 24×21 tile:

```python
# Each tile still writes 64 bytes; the star centre is offset
# by half the tile dimension.
dx_quadrant = (SPRITE_W // 2) * (1 if (q & 1) else -1)
dy_quadrant = (SPRITE_H // 2) * (1 if (q & 2) else -1)
cx = (SPRITE_W - 1) / 2.0 + dx_quadrant
cy = (SPRITE_H - 1) / 2.0 + dy_quadrant
```

Output: 4 binaries (`kloot_star_q0.bin` … `kloot_star_q3.bin`), each 16 frames × 64 bytes = 1 KB. Total 4 KB.

Optionally also add `--lobes N` (default 4) to control the polar frequency:

```python
# Current: big = abs(math.cos(2.0 * theta)) ** curve   # 4 lobes
# 12 lobes: big = abs(math.cos(6.0 * theta)) ** curve
n_lobes = args.lobes
big = abs(math.cos((n_lobes / 2) * theta)) ** curve
```

Retune `--inner` and `--curve` for 12 fine points so they don't blur — try `--inner 2.0 --curve 3.0 --outer 11.0`. Preview PNG shows instantly without building.

### Data layout in RAM

| Address | Content |
|---------|---------|
| `$2800` | sprite 0 (top-right) — 16 frames × 64 bytes = 1 KB |
| `$2C00` | sprite 1 (top-left) — 1 KB |
| `$3000` | sprite 2 (bottom-left) — 1 KB |
| `$3400` | sprite 3 (bottom-right) — 1 KB |

Sprite pointer values: `$A0`–`$AF` (spr 0), `$B0`–`$BF` (spr 1), `$C0`–`$CF` (spr 2), `$D0`–`$DF` (spr 3).

### Position setup in coda.asm

```asm
// 48×42 star, centred where the old 24×21 was.
// Old centre: X=64+12=76, Y=139+10=149
// Sprite 0 (top-right):   X=76,     Y=139
// Sprite 1 (top-left):    X=76-24,  Y=139
// Sprite 2 (bottom-left): X=76-24,  Y=139+21
// Sprite 3 (bottom-right):X=76,     Y=139+21

lda #76
sta $d000  // spr 0 X
lda #52
sta $d002  // spr 1 X
sta $d004  // spr 2 X
lda #76
sta $d006  // spr 3 X
// $D010 MSB bits all clear (all X < 256)

lda #139
sta $d001  // spr 0 Y
sta $d003  // spr 1 Y
lda #160   // 139 + 21
sta $d005  // spr 2 Y
sta $d007  // spr 3 Y

// All 4 orange, or gradient:
lda #$08
sta $d027  // spr 0
sta $d028  // spr 1
sta $d029  // spr 2
sta $d02a  // spr 3
```

### Per-frame pointer update

All 4 sprites advance through their 16-frame rotation in lockstep. Compute from `kloot_shape` (0-15):

```asm
// In interrupt, after advancing kloot_shape:
ldx kloot_shape
lda #KLOOT_SHAPE_BASE      // $A0
stx $07f8                  // spr 0 = $A0 + shape
txa
ora #$10
sta $07f9                  // spr 1 = $B0 + shape
ora #$10
sta $07fa                  // spr 2 = $C0 + shape
ora #$10
sta $07fb                  // spr 3 = $D0 + shape
```

Wait — `ora #$10` stacks: $A0→$B0→$C0→$D0 works only if shape bits 0-3 don't overlap. Since shape is 0-15 (bits 0-3) and the quadrant offset is bit 4, they don't collide. This works.

### EFO header changes

```asm
// coda_efo_header.asm:
'P', $08, $0A     // code (was $08-$0A)
'P', $28, $2B     // sprite 0 (was $28-$2B)
'P', $2C, $2F     // sprite 1 — new
'P', $30, $33     // sprite 2 — new
'P', $34, $37     // sprite 3 — new
```

### build.sh changes

Pass all 4 binaries to `mkpef`:

```bash
build_part coda "$CODA_ASM" \
    "kloot_star_q0.bin,$2800" \
    "kloot_star_q1.bin,$2C00" \
    "kloot_star_q2.bin,$3000" \
    "kloot_star_q3.bin,$3400"
```

The existing `build_part` already forwards trailing `<file>,<addr>` args — see the multi-file mkpef pattern in `docs/pefchain-notes.md`.

### Risk: sprite DMA load

4 sprites per scanline = 4 × 63 cycles = 252 cycles of DMA per scanline (worse case if all 4 overlap the same row). VIC has ~43 DMA cycles available per scanline before stealing CPU time.

Mitigations:
- The star sits in the bottom half of screen (Y ≥ 139, below title row 11). The raster IRQ at line 50 runs before these scanlines, so only the idle main loop (`jmp *`) gets stretched — fine for a static title card with no concurrent effects.
- If needed: drop to **3 sprites** (L-shape: top-left + top-right + bottom-left, omit bottom-right). Still ~50% bigger than single sprite.

## Simpler alternative: 2 sprites side-by-side

Half the data, half the DMA load. 48×21 (double width, normal height):

- Sprite 0 = left half of star (X=52, Y=139)
- Sprite 1 = right half (X=76, Y=139)
- Same render script with `--quadrant 0` and `--quadrant 1` for left/right halves
- 2 KB data at `$2800` + `$2C00`
- EFO: `'P', $28, $2F`
- Only 2 sprite DMA slots per scanline — no CPU timing concern

## 12-lobe star shape

In `tools/render_kloot_star.py`, the lobe count is controlled by the frequency multiplier in `star_radius`:

```python
# Current — 4 lobes (cos(2*theta) has period π → 2 cycles in 2π = 4 lobes)
big = abs(math.cos(2.0 * theta)) ** curve

# 12 lobes — cos(6*theta) has period π/3 → 6 cycles in 2π = 12 lobes
big = abs(math.cos(6.0 * theta)) ** curve
```

Suggested starting params for 12 lobes: `--inner 2.0 --curve 3.0 --outer 11.0 --frames 16`. Run with `--preview` to eyeball before building.

To make it a CLI knob:

```python
p.add_argument("--lobes", type=int, default=4,
               help="Number of star points (default: %(default)s)")
# In star_radius:
freq = args.lobes / 2.0
big = abs(math.cos(freq * theta)) ** curve
```

---

## Stage F — Twin stars crossing (sine-based orbit)

### What changed
Two independent 4-sprite Kloot stars cross each other. Star 1 (sprites
0-3) keeps the original brown ($09); star 2 (sprites 4-7) is cyan
($0E). Both share the same pre-rendered 24-frame zoom+rotation shape
data at `$2000-$37FF` but advance through it at independent rates via
separate `kloot_shape_1` / `kloot_shape_2` counters, so lobe angles
drift apart visually.

### Orbital motion
A 256-byte sine table at `$0B00` (page-aligned) supplies both X and Y
offsets. Each frame, two independent phase counters advance:

```
star1_phase += ORBIT_SPEED_1   (= 1 → ~5 s/cycle)
star2_phase += ORBIT_SPEED_2   (= 2 → ~2.5 s/cycle)
```

The sin_tab lookup gives the orbital centre offset; cosine is derived
by offseting +64 into the table (quarter cycle):

```
starN_cx = sin_tab[phase] + KLOOT_X_CENTRE
starN_cy = sin_tab[phase + 64] + KLOOT_Y_CENTRE
```

Each star's 4 sprites are then positioned at `starN_cx ± KLOOT_DX`
for X and `starN_cy ± KLOOT_DY` for Y, where `KLOOT_DX=24`,
`KLOOT_DY=21` are the fixed quad half-dimensions.

### Priority
VIC's natural rule (higher sprite number = in front) means star 2
always renders on top when they cross. No manual priority changes
needed.

### EFO
Widened from `'P', $08, $A` to `'P', $08, $0B` to cover the new
256-byte sin_tab page.

### Priority swap
The VIC always renders higher sprite numbers on top. To alternate
depth, a `swap_flag` toggles which star owns sprites 0-3 vs 4-7.
The toggle triggers when bit 6 of the phase difference
(`star2_phase - star1_phase`) transitions — this happens every
~64 frames at the point of maximum separation on the orbits (stars
~90° apart, clearly separated). The swap is invisible because the
stars are far apart; by the next crossing, the depth order has
reversed. Sprite colours follow the star identity, not the hardware
slot, so brown always belongs to star 1 and cyan to star 2.
`
