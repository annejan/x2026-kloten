# Timing — outline-64

All values are approximate; everything is subject to change as
effects and music evolve.

## MCP-measured timings (19 May 2026)

PAL 50 fps, VICE x64sc, measured via polling `$F6` every ~3 s from
autostart:

| Time (s) | `$F6` | Part |
|----------|-------|------|
| 0–51 | `$00` | screenfill → intro — `$F6` is `zp_outro` in intro, stays 0 until outro starts |
| 51–54 | `$00`→`$1A`→`$66`→`$B2` | Transition cluster — intro outro sweeps `zp_outro` 0→`$F0`, triggers interlude |
| 54–66 | `$66`→`$B2`→`$3C` | Rapid — interlude + sinus (fast `$F6` update), then greets loads |
| 66–87 | `$01`→`$03`→`$05`→`$08`→`$0A`→`$0C`→`$0E` | **Greets** — slow beat-counter increment (every ~0.48 s) |
| 90 | `$00` | Transition to coda → end (`$F6` reset) |

**Greets visible window: ~21 s** (beat 1→30 of 32).
Scroll advances 1 char every 6 frames → ~8.3 chars/s.
At 21 s ≈ 175 chars shown, roughly 20% of message visible before
transition to coda. Bumped to SCROLL_DELAY=12 (4.2 chars/s) for
readability — same total chars shown (~88 chars over 21 s ≈ 10
lines of ~30).

## Frame / tick basis

| Unit | Rate | Per |
|------|------|-----|
| PAL frame | 50 Hz | 20 ms |
| Intro tick (`zp_intro`/`zp_outro`) | 25 Hz | 40 ms (every 2 frames) |
| Beat (`zp_beat_count`) | ~2.08 Hz | 24 frames (~0.48 s) |

## Part chain

```
screenfill ──5.6s──→ intro ──73s──→ interlude ──7.5s──→ sinus ──5s──→ greets ──15s──→ coda ──10s──→ end (loops)
```

| Part | Duration | Cumulative | Transition ZP | Trigger |
|------|----------|------------|---------------|---------|
| screenfill | 5.6 s | 5.6 s | `$06` (HOLDCNT) | `06 = 00` |
| intro | 73.3 s | 78.9 s | `$F6` (zp_outro) | `F6 = F0` |
| interlude | 7.7 s | 86.6 s | `$F6` (zp_beat_count) | `F6 = 10` |
| sinus | 5.0 s | 91.6 s | `$F6` (zp_timer) | `F6 = 30` |
| greets | 15.4 s | 107.0 s | `$F6` (zp_beat_count) | `F6 = 20` |
| coda | 10.0 s | 117.0 s | `$F6` (zp_timer) | `F6 = 30` |
| end | loops | — | (none) | `stay` |

**One-pass runtime: ~1 min 57 s** from boot to looping credits.

---

## Part 1 — screenfill (`parts/screenfill/`)

| When | Event | Detail |
|------|-------|--------|
| -0.2 s | bootstrap-blank load | Pefchain's auto-inserted leading blank effect runs `lda #$00 sta $D011/$D020/$D015` — display off, ~270 ms while screenfill loads. |
| -0.0 s | **prepare** | Runs in main context after the load completes, before switchover. Restores BASIC: bank 0, $D011=$1B, $D018=$15, border $0E, bg $06, sprites off. BASIC text reappears briefly. |
| 0.0 s | setup | $D018→$17 (chargen swaps to lowercase ROM, BASIC text re-renders in lowercase). Build char table, init ripple counters. |
| 0.0–2.6 s | **Radial fill** | 16 rings × 8 frames = 128 frames. DEFEEST characters bloom over the BASIC screen. Border stays light-blue ($0E). |
| 2.6 s | **Ripple starts** | RADIUS hits 16 — one-shot border $0E → $06 (NOT per-frame, would clobber the late snap). HOLDCNT = 150. |
| 2.6–4.0 s | **Ripple, blue border** | Concentric colour waves from screen centre. HOLDCNT counts down 150 → 86. |
| 4.0–4.3 s | **Fade begins** | HOLDCNT < 85. Every 8 frames the text palette steps through `fadetab` ($01→$0F→$0C→$0B→$00 etc.). |
| 4.3 s | **bg + border snap together** | HOLDCNT = 72 (mid-fade, after 1 palette tick). Both write $00. Rings continue fading visibly on a black bg for the remaining ticks at 64 & 56. |
| 4.3–5.6 s | **Tail / hold** | All-black with the final palette ticks completing the ripple fade. |
| 5.6 s | **HOLDCNT = 0** | pefchain transitions to intro. |

---

## Part 2 — intro (`parts/intro/`)

### Intro phase (build-up, tick 0→255 ≈ 0→10.2 s)

| Tick | Time | Event | Detail |
|------|------|-------|--------|
| 0 | 0.0 s | setup | Chargen copy, sprite init, music init. Visuals all off/hidden. |
| 0→16 | 0→0.6 s | **BG fade-in** | `fade_bg` table: $D021 ramps $00 → logo_bg. |
| 40 (T_BALLS) | 1.6 s | **Balls start** | Sprite 0 appears. V2 (lead) gates on. |
| 40→96 | 1.6→3.8 s | **Ball cascade** | 1 new sprite every 8 ticks. All 8 on by tick 96. |
| 120 (T_BARS) | 4.8 s | **Bars appear** | Rainbow rasterbars $80..$EB. V1 (bass) gates on. SID vol = $0F (full). |
| 200 (T_LOGO) | 8.0 s | **Logo wipe** | 1 new column revealed per tick. |
| 240 (T_SCROLLER) | 9.6 s | **Scroller starts** | Bitmap row 0 scroller activates. V3 (arp) gates on. |

### Outro phase (triggered when scroll_text hits $FF)

| Tick | Time | Event |
|------|------|-------|
| 0 | ~63.7 s | zp_outro = 1. Scroller shifts but no advance. |
| 40 (T_OUTRO_LOGO) | ~65.3 s | Logo un-wipe: columns hidden right→left. |
| 120 (T_OUTRO_BARS) | ~68.5 s | Bars switch off. |
| 176 (T_OUTRO_BALLS) | ~70.7 s | Sprite 7 despawns first; one every 8 ticks. |
| 240 (T_OUTRO_DONE = $F0) | **~73.3 s** | pefchain loads interlude. |

### Scroll text blocks (338 chars total)

| Block | Mode | Direction | Chars | Content |
|-------|------|-----------|-------|---------|
| 1 | 0 | left | 132 | "deFEEST presents…" + "Anus and Claude Opus 4.7…" |
| 2 | 1 | right | 107 | "Open borders, FLD-bounce logo…" |
| 3 | 2 | zig-zag | 99 | "Greetings to everyone who still codes the breadbin…" |

Advance rate: 8 frames/char. Blocks separated by `$FE` sentinel
characters; end-of-text = `$FF` triggers outro.

---

## Part 3 — interlude (`parts/interlude/`)

16 beats × 24 frames = 384 frames = **7.68 s** (loosened from 10 beats × 20).

| Beat | Time | Event |
|------|------|-------|
| 0–5 | 0–2.9 s | Pad-only: V1 bass muted ($D404 = 0). Plasma + line A typewriter "FOR YEARS NO TIME FOR BREADBIN CODE" reveals over 2.8 s. |
| 5 | 2.9 s | Line A fully revealed. ~0.1 s reading time before buildup. |
| 6 (BUILDUP_BEAT) | 2.9 s | V1 bass re-enabled. LP filter sweep starts at cutoff=$40. Raster bars appear. SPARKED sprite letters begin fly-in. |
| 7–15 | 3.4–7.2 s | Filter cutoff += $16 per beat: $40 → $56 → $6C → … → $FF (saturates at beat ~12). SPARKED settles at beat ~7, bounces, white border flash on landing. |
| 15 | 7.2 s | SPARKED letters fly out. |
| **16 (= $10)** | **7.7 s** | pefchain loads sinus. |

Per-frame: plasma (half rows updated), music, beat phase, raster bars, border flash on SPARKED landing.

---

## Part 4 — sinus (`parts/sinus/`)

250 frames = **5.0 s**.

| Frame | Time | Event |
|-------|------|-------|
| 0 | 0 s | Setup: text mode, chargen ROM at $1000, screen $0400, border black. |
| 0 | 0 s | Screen filled with repeating "DEFEEST" (1024 cells via `defeest_codes` table). Colour RAM = light cyan ($03). |
| 0→249 | 0→5.0 s | Per-scanline `$D016` fine scroll wobble (sine table 0–7 px, OR'd with `$08` to preserve CSEL). Border + bg colour cycling per scanline. |
| 0→199 | 0→4.0 s | LP filter sweep: cutoff $70→$08 over 200 frames. Re-asserted after each `my_music_play`. |
| 200→249 | 4.0→5.0 s | Volume fade: SID vol $0F→$00 over last 50 frames. Border/bg also snap to black. |
| **250** | **5.0 s** | `irq_top` sets zp_timer = `$30`; pefchain's `f6 = 30` condition fires. |

Per-frame: `my_music_play` (drums silent in sinus because setup
zeroed `$F6` so `zp_outro` gate fails), LP filter re-assertion,
colour cycling, sine-table application to `$D016`. The repeating
DEFEEST text connects visually back to the screenfill bloom that
opened the demo — a sinus-style swimming-text effect over the
inherited intro chords.

**EFO ownership**: `'P', $08, $0C` claims all 5 pages of code +
sine_tab + col_tab + bg_tab. Earlier `'P', $08, $08` caused
pefchain to overwrite sinus's tables with its driver wait-loop;
see `docs/pefchain-notes.md`.

---

## Part 5 — greets (`parts/greets/`)

32 beats × 24 frames = **15.36 s**.

| Beat | Time | Event |
|------|------|-------|
| 0 | 0 s | 8 X-expanded sprites show 8-char window of greetings text. |
| Each beat | every 0.48 s | Kick on V3 (10-frame pitch sweep). Music V1+V2 play naturally. |
| 0–31 | 0–15.4 s | Text advances 1 char per 6 frames. DYCP sine wobble per sprite. |
| **32 (= $20)** | **15.4 s** | pefchain loads coda. |

Only ~128 of 864 text characters scroll through before the
32-beat limit triggers the transition.

---

## Part 6 — coda (`parts/coda/`)

`N_FRAMES = 250` half-rate ticks (~10.0 s at the 25 Hz subtick divider).

Four-sprite Kloot star: sprites 0-3 form a 2×2 grid, each X+Y-expanded
(48×42 on screen, source 24×21). Four quadrant data files at
`$2800`/`$2C00`/`$3000`/`$3400`, sprite bases `$A0`/`$B0`/`$C0`/`$D0`.

| Frame | Time | Event |
|-------|------|-------|
| 0 | 0 s | Setup: text mode, ROM uppercase chargen at `$1000`, screen `$0400`. Title text painted on rows 11 and 13. V3 ADSR pre-loaded with kick shape (`AD=$08, SR=$00`). `$F6` zeroed → drums from intro's `my_music_play` silenced. All 4 sprites enabled (`$D015=$0F`) but initially collapsed at screen centre `(160,128)`. |
| 0 → ~30 | 0 → ~1.2 s | **Stage D animate-in**: sprites explode outward from centre to final positions (TR/TL/BL/BR at KLOOT_X_{LEFT,RIGHT} / KLOOT_Y_{TOP,BOT}). Position interpolation via separate tables per quadrant. |
| 0 → 249 | 0 → 10.0 s | **Stage C breath modulation**: collective scale + position bob from a 256-entry sine table. Y-position bob synced to kick phase. |
| 0 → 249 | 0 → 10.0 s | **Per-quadrant petal shape**: lobe curvature modulates per frame per quadrant, creating asymmetric petal shapes. |
| ~26 raw = zp_frame 13 | ~0.52 s | First audible V3 kick (after 25-frame lead-in countdown). Kick fires every 50 raw frames thereafter (~60 BPM). |
| each zp_frame tick | 25 Hz | All 4 sprite pointers advance in lockstep: `kloot_shape = (kloot_shape + 1) & $0F`. 16 frames × 4-fold symmetry = seamless 360° visual rotation in ~0.64 s. |
| 0 → 249 | 0 → 10.0 s | Border colour cycles through `col_tab` (256-entry slow sine). Colour RAM star-field twinkles in top 5 rows. |
| **250** | **10.0 s** | IRQ writes `$F6 = $30`, border snaps to black, `$D015 = $00` hides sprites; pefchain's `f6 = 30` fires, end loads. |

Per-frame: `INTRO_MUSIC_PLAY` (chord pad + lead on V1/V2), then
`coda_kick` on V3 (10-frame pitch sweep, hard restart each beat).
`zp_subtick` toggles each IRQ; only every second IRQ increments
`zp_frame`.

**EFO ownership**: `'P', $08, $0A` (code + col_tab, 3 pages). `'P', $28,
$37` (all 4 quadrant star data: `$2800-$2BFF` TR, `$2C00-$2FFF` TL,
`$3000-$33FF` BL, `$3400-$37FF` BR — 16 pages). `'I', $10, $12` inherits
intro's music. Four quadrant `.bin` files passed separately to `mkpef`
via `build.sh` instead of one large contiguous PRG, avoiding zero-padded
gaps across greets' memory.

---

## Part 7 — end (`parts/end/`)

Loops forever (`stay`). One credit cycle:

| Frame | Time | Event |
|-------|------|-------|
| 0 | 0 s | Text-mode credit roll. SID vol = 0, screen/text black. |
| 0→99 | 0→2.0 s | **Fade-in**: zp_fade 0→99. SID vol ramps $00→$0F. Text invisible (color RAM = $00). |
| 99 (TEXT_REVEAL) | 2.0 s | Color RAM painted with gradient. Credit text visible. |
| 2.0→32.7 s | **Credit scroll** | yscroll every 4 frames; hardware scroll every 32 frames (next credit line pulls in). 48 rows × 32 frames ≈ 30.7 s per full cycle, then loops. Full uppercase A-Z font with custom Å glyph at screencode `$5B`. |

Music: 128-step chord/lead cycle × 24 frames/step = 61.4 s per
cycle. LP filter on (re-asserted every frame).

---

## Debugging notes — MCP session (May 2026)

### Greets message dead zone

pefchain splits greets into two load segments at `$84FF`/`$8500`
(the build sector map shows them separately). The first segment
(`$8000-$84FF`, 1280 bytes) is **not fully written** — pages
`$83-$84` (`$8300-$84FF`) retain whatever data the prior part
(interlude) left there. This included interlude's `wave` table
at `$8300`, which overwrote the first ~436 characters of the
scroller message at `$834C`.

**Fix** (PR `b77e97e`):
  - Added `* = $8500` before `message:` so the scroller text
    lands in the second (correctly-loaded) segment.
  - Expanded EFO claim from `'P', $80, $86` to `'P', $80, $8F`
    so `font_data` at `$8881` is also protected.

**Detection**: Compared PRG data vs VICE memory per page via MCP:
  `$8000`: 226/256 mismatches, `$8100`: 253/256, `$8200`: 212/256,
  `$8300`: 256/256, `$8400`: 247/256, `$8500`: 0/256, `$8600`: 0/256.
  Pattern at `$8300` matched interlude's `wave` table byte-for-byte.

### Spindle NMI clobbering sprite pointers

`$07F8-$07FF` (sprite pointer area) not claimed in greets' EFO
`'Z'` tag. Spindle NMI writes to `$07F8-$07FF` between ticks,
resetting all 8 sprite pointers to `$A0` → `$2800` (coda's Kloot
star data, not greets' font at `$2000`).

**Fix**: `jsr update_sprite_ptrs` every frame in the IRQ handler
to re-write pointers after each NMI. Old fix, still required.

### VICE-MCP warp mode

`WarpMode=1` in resources (`vice.machine.config.set`) runs
as fast as the host allows (not 4× — more like 100×). Use
`Speed=400` + `WarpMode=0` for a predictable 4× warp.

Write checkpoints (`store=true`) on ZP/memory addresses are
frequently hit but do not reliably stop execution under warp.
Use `vice.execution.pause` + polling for part detection instead.

`vice.run_until` with `cycles` param is listed as "not yet
implemented" but `address` param works.
