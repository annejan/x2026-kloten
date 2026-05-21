# Kloten met de broodtrommel

A C64 demo by **deFEEST**, releasing at **X2026**. Work started at
Outline 2026; about three weeks of development total. Written by
Augurk/deFEEST, Kloot/deFEEST, TL-Buis/deFEEST,
Anus/deFEEST, Ranzbak/deFEEST, Cinder/deFEEST. KickAssembler 6510 source, tested on VICE x64sc (PAL).

The arc: a human (`Anus/deFEEST`) hadn't had time to code the
breadbin in years. Sat down one evening with `Kloot` (a Claude AI
pair-programmer). Three weeks later this is what came out.

## How this was built

Pair-coded with Claude in a live editor / emulator loop. The general
shape of the process:

- **Tight feedback cycle.** Every change rebuilds the `.d64` (`./build.sh`)
  and autostarts it in a custom VICE-MCP build (`./run-mcp.sh`). Claude
  drives VICE through the MCP server — screenshots, register reads,
  memory dumps, breakpoints — so visual + cycle-level verification is
  part of normal editing, not a separate "test step". When something
  freezes the demo, the first debug move is usually `vice.registers.get`
  + `vice.memory.read` to see exactly which 12 bytes got corrupted and
  why (see e.g. the `feedback-kickass-hi-byte-precedence` memory note —
a `>label + N` parser-precedence trap that spread DEFEEST screencodes
through all 64 KB of memory).
- **Claude keeps a persistent memory** of the project's anchor commit,
  toolchain quirks, raster-bar timing rules, sprite write windows,
  Spindle script byte-counts, KA syntax gotchas, etc. — so re-discovered
  knowledge from session N is available in session N+1 without rereading
  the entire codebase.
- **Codebase64 is the reference manual.** Whenever a new effect is
  designed (FLD, raster bars, palette fades, water ripple, etc.) the
  first stop is the [Codebase64 VIC effects index][cb64] and the
  [6502/6510 math routines][cb64math]. Cycle counts and edge-case
  warnings come from there; the code is then specialised to the
  particular demo memory layout.
- **Spindle 3.1 / pefchain** does all the linking and background-loading.
  Each part is its own `.pef` with an `EFO2` header that declares which
  memory pages it owns, what its `setup`/`interrupt`/`fadeout` entry
  points are, and which zero-page bytes it touches. Pefchain runs an
  NMI-driven loader during one part to stream the next part into RAM,
  so transitions are seamless when memory layouts don't collide.
- **Git is the prompts log.** Each meaningful change is committed and
  pushed (durable authorization — no per-commit confirmation), so the
  log of "what we decided and when" lives in commit messages rather
  than a separate journal.

[cb64]: https://codebase.c64.org/doku.php?id=vic:demo_programming
[cb64math]: https://codebase.c64.org/doku.php?id=base:6502_6510_maths

## What's in the demo

Seven parts loaded by [Spindle 3.1][spindle] via pefchain. Each one
auto-advances on a timer / state condition — no space key, no manual
trigger. The end card is the only "stay" loop.

[spindle]: https://hd0.linusakesson.net/spindle.php

### Part 1 — `parts/screenfill/screenfill.asm` (loading screen)

- **Animated radial deFEEST bloom.** Setup precomputes a 1024-byte
  `char_table` (each cell's final deFEEST character, picked by a rotating
  bit-mask sweep over upper/lower case). Interrupt then reveals the text
  ring-by-ring: every 6 frames, all cells whose `dist_table` value
  equals the current `RADIUS` get copied from `char_table` into screen
  RAM. 16 rings ≈ 1.9 s of bloom.
- **Water-ripple colour cycle.** After the fill, ~3 s of palette cycling
  on colour RAM. The same 1024-byte radial-distance map now indexes a
  16-entry palette shifted by a phase counter each frame, so concentric
  rings appear to expand outward from centre.
- **Fade to black.** Last ~1.7 s snaps bg+border `$06 → $00` (no `$0B`
  intermediate; on new-VIC `$0B` is brighter than blue, see
  [COLFADE v2](https://codebase.c64.org/lib/exe/fetch.php?media=vic:colfade_v2.pdf))
  and walks the ripple palette through a hue-stable fadetab to black.
- Transition: pefchain advances when `$06` (= `HOLDCNT`) hits 0.

### Part 2 — `parts/intro/intro.asm` (the demo)

- **Open top/bottom borders** via the canonical HCL polling trick
  (`$d011` 24/25-row toggle in IRQs at line `$f9` and `$01`).
- **Multicolour bitmap "deFEEST" logo** mid-screen (160×200 Koala, encoded
  from a PNG by `tools/png_to_koala.py`). Wipes in column-by-column from
  the left via `reveal_column`, then floats on a flexible-line-distance
  bounce.
- **FLD logo bounce** — anchor-style "late write" pattern at line `$3B`.
  Per-frame `K = bounce_total[frame]` writes increment `$D011`'s yscroll
  after VIC's cycle-14 check, so each line's badline check sees the
  previous write and fires a spurious badline. Smooth 0..28 px bounce,
  3× sine frequency.
- **Bitmap scroller** at the very top, bitmap row 0 (lines `$33..$3A`).
  Cycles through three scroll modes via `$fe` sentinels in `scroll_text`:
  - mode 0 — all rows shift left (right-to-left, normal reading)
  - mode 1 — all rows shift right (left-to-right "deFEEST classic"); the
    advance walks `zp_text_ptr` **backwards** through block 2 so the
    source still reads forward
  - mode 2 — zig-zag (even pixel rows shift left, odd rows shift right)

  1 px/frame via 40-cell ROL/ROR chains. Per-cell rainbow colour-RAM
  cycle every frame so the letters flow through hues. Sprites 0-2 have
  their foreground-priority bit set, so the rainbow strokes overdraw
  the balls swinging through the scroller row.
- **Rainbow rasterbars** wrapping the logo. The bar IRQ at line `$80`
  polls `$d012` and writes both `$d021` (background, behind the bitmap's
  transparent pixels) and `$d020` (border / side stripes) per scanline
  from a page-aligned 512-byte palette. 21-cy tight loop fits within the
  bad-line CPU budget.
- **Eight X+Y-expanded "koorballen" sprites** bouncing on sine paths —
  three in the open top border, three in the display (Y range 90..200,
  clear of the FLD zone), two in the open bottom border. Sprites 0-2
  are disabled in `irq_close` to hide their Y+256 wrap-around duplicates.
- **Custom 3-voice SID music** — bass pulse, lead pulse, sustained arp
  over a 32-step Am-Em-F-G chord progression with a 128-step lead melody.
  Music tables are resident at `$1000-$125D` so later parts can call
  intro's `my_music_play` to keep the theme drifting through transitions.
- **Sequenced intro/outro** (driven by `zp_intro`/`zp_outro`, 25 Hz tick,
  saturating at `$ff`):

  | tick | const         | event                                   |
  | ---- | ------------- | --------------------------------------- |
  |   0  |               | logo bg + scroller hidden, SID muted    |
  |  40  | `T_BALLS`     | sprite 0 appears (then 1 every 8 ticks) |
  | 120  | `T_BARS`      | rasterbars on; V1 bass gate fires       |
  | 200  | `T_LOGO`      | logo wipe-reveal begins (40 columns)    |
  | 240  | `T_SCROLLER`  | scroller fade-in; V3 arp gate fires     |

  Outro reverses it: scroller drain, logo un-wipe, rasterbars off,
  sprite cascade out (7 → 0), then `zp_outro` hits `T_OUTRO_DONE = $f0`
  and pefchain advances.

### Part 3 — `parts/interlude/interlude.asm` (breather)

- **Text-mode plasma** over the full screen (half the screen updated per frame).
  Uses `$D012` raster position + sine (beat-phase-modulated) to generate
  per-row colour and character values into `$0400` / `$D800`.
- **Six raster bars** on the bottom border using a short IRQ chain.
- Calls intro's resident `my_music_play` so the chord + lead drift
  continues. V1 (bass) is muted every frame for a pad-only feel.
- Last 8 beats: V1 re-enabled, LP filter sweep ($40→$FF) as build-up.
- Beat counter at `$f6` ticks every 24 frames. After 16 beats (~7.5 s)
  pefchain advances to sinus.
- Inherits intro's music pages (`'I', $10, $12` in the EFO header) so
  pefchain doesn't overwrite the resident tables.

### Part 4 — `parts/sinus/sinus.asm` (breather)

- **Char-mode sine wobble** — per-scanline `$D016` fine-scroll write from a
  256-entry sine table (range 0–7 px, OR'd with `$08` to preserve CSEL).
- **Repeating "deFEEST" text** filling the whole screen via ROM uppercase
  chargen at `$1000`. Connects back to the screenfill bloom.
- **Colour cycling** — border and background colours step through tables
  per scanline for a flowing wave look.
- **LP filter close** — filter cutoff sweeps from $70→$08 over 200 frames.
  `$D418` re-asserted every frame after `my_music_play` (which would
  otherwise clobber the LP bit with a vol-only write).
- **Volume fade-out** — SID vol $0F→$00 over the last 50 frames.
- **No drums** — sinus's setup zeros `$F6` (its `zp_timer`), which is also
  the gating byte for the percussion in `my_music_play`. Ear-cleansing
  break before the greets climax.
- Frame counter at `$fc` reaches 250 frames (~5 s) and writes `$30`
  to `$f6`; pefchain then advances to greets. **`$fc` not `$f9`** —
  intro's `my_music_play` internally uses `$f9` as its own scratch
  byte (writes it on every JSR), which earlier silently clobbered
  the sinus frame counter so the part never transitioned.
- Inherits intro's music pages (`'I', $10, $12`).
- EFO claims `'P', $08, $0C` (5 pages of code + tables — earlier
  single-page claim caused pefchain to overwrite the colour/sine tables).

### Part 5 — `parts/greets/greets.asm` (greetings scroll)

- **DYCP sprite-font scroll** — 8 X-expanded sprites show a 8-char window
  of greetings text with a per-sprite sine wobble (Y offset ±2 px, X
  offset ±1 px, halved from the original ±3 / ±2 in PR #34 for
  readability). Sprite pointers re-written every frame (Spindle NMI
  clobbers `$07F8-$07FF` between ticks). Priority reversed: sprite 7
  leftmost, sprite 0 rightmost — VIC reads left-to-right for overlap.
- **16-bit `scroll_pos`** so the message can exceed 256 bytes —
  `update_sprite_ptrs` self-modifies the LDA operand each call instead
  of relying on `lda message,y`'s 8-bit Y reach.
- **Kick drums on V3** — pitch-swept noise burst on every beat (driven
  from intro's resident `my_music_play`; gated on `zp_outro != 0` which
  sinus resets, so drums silence in sinus and return here).
- **Fade-then-settle ending.** Three phases of duration: 0..57 s scroll
  at full DYCP amplitude; 57..69 s `zp_damp_shift` ramps 0→5 in
  quarter-beat steps so both wobble (sign-preserving ASR per shift)
  and scroll speed (lookup table `SCROLL_DELAY_TABLE`) decelerate
  together; 69..77 s settle — scroll snaps to `settle_text` (the
  KLOOT punchline), sprites freeze flat at `SPR_Y_BASE`, colour
  cycle keeps shimmering. The deceleration masks the freeze.
- Text advances 1 char per 8 frames (was 12). Greeting tells the
  lunchbox-themed arc ending with KLOOT centred in the held landing.
- Beat counter at `$f6` ticks every 24 frames. After 160 beats (~77 s)
  pefchain advances to coda.
- Inherits intro's music pages (`'I', $10, $12`).
- **Bug fix in PR #32:** `ptr_lookup` maps every non-A-Z char to slot
  `$9A`. Before the fix, `font_data` emitted only the 26 A-Z glyphs
  so slot `$9A` read uninitialised RAM and every space / `.` / digit
  in the message rendered as random pixels ("letters popping in").
  One-line `.fill 64, 0` after the A-Z loop makes the blank slot
  deterministic.

### Part 6 — `parts/coda/coda.asm` (title card)

- **Title card** — "KLOTEN MET DE BROODTROMMEL" on row 11, "A DIGITAL
  LUNCH EXPERIENCE" on row 13. Text mode, ROM uppercase chargen at
  `$1000`. The breather where the story lands between greets' scroller
  and end's credit roll.
- **Twin Kloot stars — 4-sprite 96×84 quads each.** Star 1 (sprites
  0-3, **brown `$09`**) and star 2 (sprites 4-7, **cyan `$0E`**). Each
  is a 2×2 quad of X+Y-expanded 24×21 sprites = 48×42 on screen per
  quadrant, 96×84 total. Both stars share the same pre-rendered shape
  data at `$2000-$37FF` (4 quadrants × 24 frames × 64 B), and each star
  walks its own `kloot_shape_N` counter (0..23) at independent dividers
  (`SHAPE_DIV_1=3`, `SHAPE_DIV_2=2`) so the lobe angles drift apart
  visually.
- **12-lobe Claude-style sparkle with breath** — shapes generated by
  `tools/render_kloot_star.py --lobes 12 --asymmetry 0.4 --seed 42
  --breath 4 --frames-zoom 8 --frames 16` per quadrant. Asymmetric
  random lobe multipliers (seed 42) give the recognisable Claude
  sparkle; without `--asymmetry` the star reads as a smooth radial
  circle. 24 frames per quadrant = 8 zoom (small → full, with rotation
  built in) + 16 steady rotation.
- **Stage F — ping-pong zoom breath.** Each star's shape counter
  walks `0 → 23 → 0` forever via a per-star direction byte
  (`kloot_dir_N`). Forward zooms in then rotates; backward rotates
  in reverse (invisible because 12-fold symmetry) then zooms back
  out. Star 1 starts at shape=0 forward (opens with zoom-in); star 2
  starts at shape=23 backward (opens with zoom-out) so the two breaths
  are naturally out of phase.
- **Twin-star orbits + priority swap.** Each star orbits on a sine
  path indexed by `star{1,2}_orbit_phase` advanced at different speeds
  (`ORBIT_SPEED_1=1`, `ORBIT_SPEED_2=2`). VIC priority rule (higher
  sprite number = in front) means star 2 always renders on top by
  default — a `swap_flag` toggles which star owns sprites 0-3 vs 4-7
  on the bit-6 transition of `(star2_phase - star1_phase)`, so the
  depth alternates at max separation (~64 frames between swaps) and
  is invisible because the stars are far apart at the swap moment.
- **`$D01B` in-front-of-text toggle** — same trigger as the priority
  swap. Stars appear to orbit through the title plane in 3D.
- **Parallax PETSCII starfield** (PR #31) — 32 stars across 4 speed
  tiers (`tier_speed[]={3,5,8,14}` half-rate ticks per move), 4
  distinct chars (`+ * . ,`, fast→slow) and 4 colours
  (white / lt-grey / dk-grey / blue). Per half-rate tick each star's
  countdown advances; on zero the star erases its current col, dec's
  col with wrap `0→39`, draws the tier's char + colour at the new
  position. Title rows 11/13 are never assigned, so drift passes
  above + below the title.
- **Slow border colour cycle** through a 256-entry calm palette
  (black / blue / light-blue / light-grey), driven by
  `col_tab[zp_frame]`.
- **Dedicated V3 kick** — coda "owns" V3 (no arp competing), so it
  sets a real kick ADSR (`A=0, D=8, S=0, R=0`) once in setup and runs
  a hard-restart state machine each beat: gate-off frame → fresh
  gate-on + pitch-swept body. ~60 BPM, simpler than greets' kicks
  because there's nothing to fight with on the voice. See
  [`docs/sid-drums.md`](./docs/sid-drums.md).
- Half-rate divider on `zp_subtick` keeps `zp_frame` ticking at
  25 Hz; after `N_FRAMES = 250` (~10 s) the IRQ writes `$30` to
  `$f6` and pefchain advances to end.
- Inherits intro's music pages (`'I', $10, $12`). Drums from intro's
  `my_music_play` are silenced (`zp_outro` gate stays zero because
  coda's setup zeros `$f6`); only the coda's own V3 kick sounds.
- EFO claims `'P', $08, $0F` for code + `col_tab` + `sin_tab`
  (8 pages — `sin_tab` MUST end before `$1000` or it stomps the
  inherited intro music tables), and `'P', $20, $37` for the
  6 KB of Kloot-star shape data (overlaps end's `$30-$44` claim;
  end's payload is deferred until coda finishes).

### Part 7 — `parts/end/end.asm` (credit roll)

- Custom font copied into bank 0, scrolled smoothly bottom-to-top via
  a row-major `scroll_rows_up` (full 40-byte row writes per chunk so VIC
  never reads mid-row torn cells). Full uppercase A-Z glyphs present,
  including custom Å at screencode `$5B` for "Linus Åkesson".
- Per-row gradient colours; "deFEEST" header pulses through a brightness
  ramp.
- Side rasterbars on the left and right border columns.
- Plays the intro chord/lead theme via referenced constants
  (`MAIN_SID_FREQ_LO` = `$1000`, etc.) — same theme, slower, with PWM
  on V3 + a gentle filter sweep for arp shimmer.
- Transition: `stay` — this part runs forever.

50 Hz PAL, locked.

## Build / run

You need:

- **KickAssembler** (jar in `kickass/KickAss.jar`, [download from theweb.dk](http://theweb.dk/KickAssembler/))
- **VICE** with `x64sc` (`zypper in vice` on openSUSE)
- **Spindle 3.1** — extract `spindle-3.1.zip` into the repo root; `build.sh`
  invokes the prebuilt Linux binaries
  `spindle-3.1/prebuilt-binaries/linux-x86_64/{mkpef,pefchain}`. Download:
  ```
  curl -LO https://hd0.linusakesson.net/files/spindle-3.1.zip
  unzip spindle-3.1.zip
  ```
  (xa65 only needed if you rebuild from source under `spindle-3.1/src/`.)
- Java for the assembler

Build the multi-part disk and run:

```
./build.sh        # produces outline-64.d64
./run-disk.sh     # autostarts the disk in stock x64sc
./run-mcp.sh      # autostarts in a VICE build with the embedded MCP
                  #  server (for driving / inspecting from Claude)
```

## Pefchain — Spindle 3.1 high-level framework

Each part is a `.pef` (packaged effect) with an `EFO2` header pointing
at `setup` / `interrupt` / `fadeout` routines plus memory-page tags.
`pefchain_script` links them in sequence:

```
parts/screenfill/screenfill.pef     06 = 00
parts/intro/intro.pef               f6 = f0
parts/interlude/interlude.pef       f6 = 10
parts/sinus/sinus.pef               f6 = 30
parts/greets/greets.pef             f6 = a0
parts/coda/coda.pef                 f6 = 30
parts/end/end.pef                   stay
```

Each line: `<pef-file> <transition-condition>`. Pefchain background-
loads the next part DURING the current one (via an NMI-driven loader)
so transitions are seamless when memory layouts don't collide. When
they do (e.g. intro claims pages `$04-$09` and screenfill writes to
`$04-$07` for its screen RAM), pefchain inserts a tiny blank-load chunk
during the transition — visible in `./build.sh` output's sector map.

Each condition tells pefchain when to advance:

- `06 = 00` — wait for zero-page `$06` (= screenfill's HOLDCNT) to hit 0.
- `f6 = f0` — wait for `$f6` (= intro's `zp_outro`) to reach `T_OUTRO_DONE`.
- `f6 = 10` — wait for `$f6` (= interlude's beat counter) to reach 16
  (~7.7 s, `TRANSITION_BEAT` in code). Reset to 0 by interlude's setup.
- `f6 = 30` — wait for `$f6` (= sinus' transition byte) to be set to
  $30 by sinus once `$fc` (the actual frame counter, off-music-clobber)
  hits 250. Sinus's setup resets `$f6` to 0.
- `f6 = a0` — wait for `$f6` (= greets' beat counter) to reach 160
  (~77 s). Settle phase kicks in at beat 144 (~69 s); the last ~8 s
  hold the screen on the KLOOT landing. Reset to 0 by greets' setup.
- `f6 = 30` — wait for `$f6` (= coda's `zp_timer`) to be set to `$30`
  by coda's IRQ once its half-rate frame counter hits N_FRAMES
  (~10 s). Coda's setup resets `$f6` to 0.
- `stay`    — never advance (end runs forever).

Spindle 3.1's resident loader sits at `$0200-$02FF` (+ buffer page
`$0300-$03FF` and zero-page `$F4-$F8` during loads). The demo keeps
everything above `$0400`.

### Per-part build

For each part the build pipeline is:

1. KickAssembler `parts/<x>/<x>.asm` → `<x>.prg` + `<x>.sym`.
2. KickAssembler `parts/<x>/<x>_efo_header.asm` with `-binfile` →
   `<x>_efo_header.bin` (raw bytes, no PRG load-addr prefix). The
   header imports `<x>.sym` so it can reference `setup`, `interrupt`,
   and `fadeout` symbol addresses without hardcoding.
3. `cat <x>_efo_header.bin <x>.prg > <x>.efo`.
4. `mkpef -o <x>.pef <x>.efo`.

Then `pefchain pefchain_script -o outline-64.d64` links the whole
thing.

## Intro memory layout (VIC bank 0)

| Range          | Contents                                       |
| -------------- | ---------------------------------------------- |
| `$0200-$03FF`  | **reserved for Spindle 3.1 resident + buffer** |
| `$0400-$07e7`  | Bitmap-mode screen RAM (colour info)           |
| `$07f8-$07ff`  | Sprite pointers                                |
| `$0810-$0a46`  | Main code + IRQs (entry point: `$0810`)        |
| `$0b00-$0b3f`  | Sprite shape data (block `$2c`)                |
| `$1000-$1275`  | Custom 3-voice SID player + patterns          |
| `$2000-$3f3f`  | Logo bitmap (multicolour, 8000 bytes)          |
| `$4000-$47ff`  | Page-aligned tables (palette, sines, bounce)   |
| `$4c00-$53ff`  | Chargen-ROM copy (mixed-case font for scroll)  |
| `$5400-$5bbc`  | Bitmap scroll renderer + scroll text + sprite shape |

> **Trap to remember:** VIC sees the chargen ROM at `$1000-$1fff` in
> bank 0, *not* RAM. Sprite shape data placed there is invisible to
> VIC — VIC reads chargen glyphs as sprite data. Keep sprite blocks
> outside that window.

## Tools

- `tools/png_to_koala.py` — convert a PNG to a 4-colour C64 multicolour
  bitmap (`defeest.kla`). Uses a fixed slot palette
  (black/blue/yellow/white) so every cell has the same 4 colours —
  works for logos with a small palette.
- `tools/koala_to_logo_png.py` — export logo rows 8-16 from a Koala
  as a paletted 320×72 PNG for pixel-editing.
- `tools/logo_png_to_asm.py` — import an edited PNG back to
  `logo_rows.asm`, preserving original screen RAM colour assignments.
- `tools/render_kloot_star.py` — pre-render Kloot star rotation frames.
  Supports `--lobes N` (default 12), `--quadrant N` (0-3 for the 2×2
  quad sprite grid), `--outer`/`--inner` for burst shape, `--curve` for
  lobe curvature.
- `vicemon.py` — stdlib VICE binary-monitor client (originated in the
  Umbra C64 project). Launch VICE with
  `-binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502`
  then `python3 vicemon.py read 0xADDR LEN`, `regs`, `resume`. Kept
  around for one-off CPU/memory pokes; for interactive driving use the
  VICE-MCP build that `run-mcp.sh` launches.

## Credits

- Music: Co-composed 3-voice SID jam (bass + lead + arp), drifts
  through all seven parts
- Logo: defeest.nl
- Assembly: Anne Jan Brouwer with Claude (Anthropic) Opus 4.7
- Thanks: Claude Code, codebase.c64.org, and an endless supply of terrible ideas
