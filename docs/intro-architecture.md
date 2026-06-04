# Intro architecture — outline-64

Living document for the intro part: the IRQ chain, the FLD logo bounce,
the music routine, and the design rationale. Reflects the **shipped**
code (verified against `parts/intro/intro.asm` 2026-06-04). Several
fancier ideas were prototyped and reverted — see the "tried + reverted"
note below and `docs/dilemmas.md` before reaching for them again.

## IRQ chain layout

PAL 50 Hz, 312 raster lines × 63 cy = **19,656 cy/frame**. The intro is
a **4-IRQ raster chain**; each handler points `$FFFE/$FFFF` at the next
one and writes `$D012` before `RTI`. Spindle points `$FFFE` at
`interrupt` (= `irq_close`) when the part starts; the chain then
self-perpetuates:

```
$F9 ──irq_close──> $01 ──irq_open──> $3B ──irq_fld──> $80 ──irq_bars──> $F9
```

| Stage (raster) | Work |
|---|---|
| `irq_close @ $F9` → `irq_open @ $01` | 24-row mode (`$D011 = $33`, opens the bitmap border); mask `SPR_EN` with `%11111000` so balls 0-2 stay OFF across the vblank wrap (Y-wrap duplicate fix); then — once `zp_intro ≥ T_SCROLLER` — `update_bmp_scroll` (~2400 cy) + `update_scroll_colors`. Runs in the bottom-border / vblank window (~4000 cy). |
| `irq_open @ $01` → `irq_fld @ $3B` | 25-row mode (`$D011 = $3b`); `calc_active_count` + re-enable the active sprites; `inc zp_frame`; tick `zp_intro` / `zp_outro` (every 2 frames); fade-in bg ramp (first 16 ticks); `reveal_column` (logo wipe); `move_sprites`. ~57 lines / ~3600 cy of slack before the FLD. |
| `irq_fld @ $3B` → `irq_bars @ $80` | the single top FLD (below), then **`jsr my_music_play`** once, then chain. |
| `irq_bars @ $80` → `irq_close @ $F9` | raster-locked bar loop `$80 .. BAR_BOT` (`BAR_BOT = $ec`): `cpy VIC_RASTER` wait, then `stx $D021` / `$D020` from `bar_palette[(zp_frame/2) + y]` (page-aligned 512-byte palette, self-modified lo-byte for per-frame drift). CPU is busy here the whole bars zone. Gated OFF until `zp_intro ≥ T_BARS`, and again once `zp_outro ≥ T_OUTRO_BARS`. |

## FLD — single top logo bounce

`irq_fld` fires at `$3B` (row 1's natural badline); row 0 (the scroller)
has already displayed at `$33..$3A`. It reads `K = bounce_total[zp_frame]`,
where `bounce_total = round(14 + 14·sin(...))`, so **K ranges 0..28**, then:

1. waits for the raster to leave `$3B` (→ `$3C`);
2. **first write**: `$D011 = $3D` (BMM+DEN+RSEL, **yscroll = 5**) at `$3C`
   cycle ~11 — *before* VIC's cycle-14 badline check, so no badline at `$3C`;
3. loops K-1 times — each line `cmp VIC_RASTER` to re-sync, then
   `lda $D011 / clc / adc #1 / and #7 / ora #$38 / sta $D011` at cy ~24
   (AFTER cy 14). The previous line's yscroll now matches *this* line's
   `line%8` at cy 14 → a **spurious badline** fires, restarting the row
   with VCBASE pinned. After K writes, row 1 has been stretched K times
   and rows 2+ slide down K px. The logo (row 8) bounces `$73 .. $73+K`.

The per-line `cmp VIC_RASTER` re-sync makes the loop tolerant of sprite-DMA
cycle theft, so no stable-raster wrapper is needed at K ≤ 28.

## Music architecture

`my_music_play` is a **single monolithic routine** installed at **`$119E`**
(via intro's EFO `'M', $9e, $11` tag). Intro calls it **once per frame
from `irq_fld`**, right after the FLD loop; every inheritor part
(`interlude`, `greets`, `coda`) calls the same `$119E` from its own IRQ.
There is no critical/step split — it is one routine.

Per call, in order: master volume (derived from `zp_intro`), V1 bass,
V2 lead, V3 arp, and the V3 drum trigger + tick. Voice writes are gated by
`zp_intro` thresholds (`T_BALLS` 40 / `T_BARS` 120 / `T_SCROLLER` 240 — see
`docs/sound-arc.md` and `docs/music-theory.md`) and `zp_outro` (drums arm
once the outro begins). The step grid advances `mu_step` (`$1148`) once
every **`STEP_FRAMES = 6`** frames via the `mu_frame` (`$1149`) counter;
V1/V2 read their patterns at `mu_step`, V3 arps within the current chord.

`my_music_play` ends with `JMP (lyric_vec)` (`$12B9`, default an `RTS`
stub) so any part can install a zero-drift music-synced callback — coda
uses the live drum state this way (see `docs/timing.md`).

Music symbols (intro.sym): `mu_step=$1148`, `mu_frame=$1149`,
`my_music_init=$114a`, `my_music_play=$119e`, `drum_state=$12bc`,
`drum_offset=$12bd`, `drum_table=$12be`.

References: codebase64
[SID programming](https://codebase.c64.org/doku.php?id=base:sid_programming)
(player structure) and
[Interrupts](https://codebase.c64.org/doku.php?id=base:interrupts)
(raster-driven IRQ-chain state machine — each IRQ swaps `$FFFE/$FFFF`
before `RTI`).

## Sprite priority

`$D01B` (`SPR_FORE`, set-bit = sprite *behind* foreground bitmap pixels)
layers the 8 balls relative to the bitmap logo so some pass behind it and
some in front — part of the layered look. Sprite Y is split into zones
(`sine_top` / `sine_mid` / `sine_bot`); the mid zone is floored at Y ≥ 90
to keep mid sprites OUT of the FLD zone, since per-line sprite DMA on FLD
lines would steal the cycles the yscroll writes need.

## Tried and reverted (do not reach for these blind)

- **Symmetric top+bottom FLD** (Jesder/ranzbak pattern, `K_max` constant,
  bottom FLD doing `K_max − K` writes to nail fixed-Y text below the logo)
  — reverted; the bottom FLD's first-write increment didn't match the top
  FLD's, breaking the spurious-badline chain. See `docs/dilemmas.md`.
- **Stable-raster double-IRQ** (Mäkelä / JackAsser, a `$59` trampoline +
  `tsx/cli/nop` alignment) to push `K` past 28 — reverted; it stabilised
  the entry cycle but not in-loop mid-sprite DMA, so the logo still tore.
  The path to higher K is sprite-free FLD lines, not a stable raster.
- **Split music** (`my_music_critical` / `my_music_step`) — never shipped;
  `my_music_play` stayed monolithic.

## Wishlist for the X2026 sprint

- **K-ramp-down outro** — ease the wipe-out by ramping `K_max` toward 0
  over the outro window so the logo settles instead of stopping mid-arc.
- **Dynamic mid-sprite priority** — flip `$D01B` for a sprite's specific
  Y range via an extra raster IRQ to remove ball/logo occlusion (~50 cy).
- **Sprite-free FLD lines** — raise the mid-sprite Y floor above the FLD
  zone (or raster-toggle `SPR_EN` across it) to unlock K > 28 cleanly.
