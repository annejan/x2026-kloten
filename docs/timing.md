# Timing — outline-64

All values are approximate; everything is subject to change as
effects and music evolve.

## Frame / tick basis

| Unit | Rate | Per |
|------|------|-----|
| PAL frame | 50 Hz | 20 ms |
| Intro tick (`zp_intro`/`zp_outro`) | 25 Hz | 40 ms (every 2 frames) |
| Beat (`zp_beat_count`) | ~2.08 Hz | 24 frames (~0.48 s) |

## Part chain

### Measured timeline (VICE-MCP, 2026-06-04 — real-time full pass)

Per-part durations measured live (reset → autostart → `$D018`/`$F6`/`$D015`
transition sampling + per-part screenshot confirmation), `t=0` at autostart.
Note that pefchain inserts blank-filler effects between parts to mask the
disk load, so the "perceived" gap between transitions can be larger than
the part's own internal duration — the biggest blank gap (and the bulk of
interlude's ~26 s) sits around the ~8 KB koala stream into greets.

```
boot+screenfill ─~8s─→ intro ─~59s─→ interlude (plasma+SPARKED+fire) ─~26s─→ greets ─~51s─→ coda ─~16s─→ end (loops, space→friet)
```

| Part | Start (t) | Duration | Sets `$D018` | Transition trigger |
|------|-----------|----------|--------------|---------------------|
| boot + screenfill | 0 s | ~8 s | `$15`→`$17` | `$06 == $00` (HOLDCNT) |
| intro | ~8 s | **~59 s** | `$19` (bitmap mode) | `$F6 == $F0` (zp_outro saturated) |
| interlude | ~67 s | **~26 s** (plasma+SPARKED ~17 s, fire ~9 s, incl. pre-greets load gap) | `$15` (plasma) → `$17` (fire) | `$F6 == $30` (fire timer) |
| greets | ~93 s | **~51 s** (scroll-driven KLOTEN landing) | `$19` (bitmap mode, koala) | `$F6 == $82` |
| coda | ~144 s | **~16 s** | `$15` (chargen $1000) | `$F6 == $30` (timer) |
| end | ~161 s | loops (1 credit cycle ~45 s) | `$1D` (chargen $3000) | (none — `stay`; space triggers friet easter egg) |

**Boot → end-credits start: ~2:41.**
**Boot → first full credit cycle done: ~3:26 (= minimal demo length** —
a viewer has seen everything once by here**).** One credit cycle ≈ 45 s
(71 credit rows × 32 frames).

> Drift vs the 2026-05-21 numbers: interlude grew ~13→~26 s (mostly the
> pre-greets blank-filler load gap), coda shrank ~30→~16 s, and the end
> credit cycle is ~45 s, not ~30.7 s. The intro-section "outro done ~73 s"
> figures below are also stale (the intro now ends ~67 s).

Music stays continuous across every part-to-part blank-filler because
intro installs `my_music_play` via the EFO `'M', $9e, $11` tag — see
[`docs/sound-arc.md`](./sound-arc.md) "Music continuity through load
gaps" for the mechanism. Each non-intro part has a `musichook:` label
holding a `bit $0000` placeholder that pefchain rewrites to
`jsr $119e` at link time; the auto-inserted blank-fillers between
effects use the same callmusic mechanism, so SID never goes silent.

Greets is **scroll-driven** (not pure-time): the IRQ forces `$F6 =
SETTLE_BEAT` the moment `scroll_pos` reaches the "KLOTEN" punchline
in the message. Settle holds for ~1.9 s of centred KLOTEN before
pefchain transitions to coda. Add/remove names in the message and
the part length tracks automatically.

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

## Part 3 — interlude (`parts/interlude/`) (includes merged fire phase)

Two phases inside one pefchain part:
- **Plasma phase** (beats 0–15, ~7.7 s): typewriter text + SPARKED drop
- **Fire phase** (250 frames after beat 16, ~5 s): colour-RAM fire + manifesto banner

Total: ~12.7 s.

### Plasma phase (beats 0–15)

| Beat | Time | Event |
|------|------|-------|
| 0 | 0 s | Setup: V3 muted via `$D418` bit 7 (no drums, no arp), V1 muted via `$D404 = 0` (no bass) → ONLY V2 lead audible. `mu_step` forced to 32 (phrase 2 = active 8ths) so the lead is moving under the typewriter. V2 PWM modulated via `zp_xphase` for a phaser feel. |
| 0–5 | 0–2.9 s | Pad-only: solo V2 lead with PWM phaser + plasma + **typewriter with typo**. Types "FOR YEARS NO TIME FOR BREADBIN **LOVE**", hesitates 60 frames (~1.2 s, cursor blinks rapidly), backspaces 4 chars (5 frames each), then types "**CODE**" correctly. The machine confesses but stumbles on the last word — the hesitation IS the narrative. State machine: LA_TYPING → LA_TYPO → LA_PAUSE → LA_BACKSPACE → LA_RETYPE → LA_DONE. |
| ~5 | ~2.9 s | Line A fully revealed (with correction). ~0.1 s reading time before buildup. |
| 6 (BUILDUP_BEAT) | 2.9 s | `$D418` bit 7 clears = V3 on (K-S-K-S kit + arp slam back in). V1 bass re-enabled. LP filter sweep starts at cutoff=$70. Raster bars appear. SPARKED sprite letters begin fly-in. |
| 7–15 | 3.4–7.2 s | Filter cutoff += $16 per beat: $70 → $86 → $9C → … → $FF (saturates). SPARKED settles at beat ~7, bounces. **On the exact landing frame: 1-frame SID silence** (`$D418 = $00` for one frame, then full volume slams back) + 5-frame white border flash. Lightning before thunder. |
| 15 | 7.2 s | SPARKED letters fly out. |
| **16** | **7.7 s** | `fire_irq` takes over — fire phase begins inside the same interlude part. |

### Fire phase (frames 0–249 after beat 16)

Merged from the former standalone `parts/hush/` part (commit `0d8dca5`).

| Frame | Time (from fire start) | Event |
|-------|----------------------|-------|
| 0 | 0 s | `fire_init`: screen filled with $A0 (solid block), banner rows 10-12 overlaid with msg_phase1, colour RAM set to $06 dark blue. Sprites disabled. VIC switches to hires text mode ($D018=$16). LP filter init ($D417=$23, cutoff=$70). |
| 0→249 | 0→5.0 s | Colour-RAM fire engine: row-alternating propagation through 7-step `sbctab` palette chain, drifting wave_palette seed at row 24, banner rows skipped (locked colour) until frame 160. |
| 0→249 | 0→5.0 s | LP filter cutoff close: $70→$08 over 250 frames. |
| 120 | 2.4 s | Phase swap: msg_phase2 written to banner; colour RAM flipped to $0E light blue; 1-frame white-border flash. |
| **160** | **3.2 s** | **Fire eats the banner**: `banner_exposed` flag set → fire propagation no longer skips rows 10-12. Heat crawls up from row 13 into the text cells, overwriting their colour RAM. The message is literally consumed by its own fire. |
| 200→249 | 4.0→5.0 s | Volume fade: SID vol $0F→$00 over last 50 frames. |
| **250** | **5.0 s** | `$F6 = $30`; pefchain transitions to greets. |

Per-frame: `my_music_play` (drums keep firing via inherited `$F6` gate),
fire propagation (~11 k cy with row alternation, fits 50 Hz budget),
LP filter re-assertion.

---

## Part 5 — greets (`parts/greets/`)

**Scroll-driven** ≈ 50 s (~514 chars at 9 px/frame ≈ 11.3 chars/sec
through the message, then a 4-beat KLOTEN landing = +1.9 s).

Background: multi-colour koala bitmap (peephole / vignette around
the sprite row) loaded from `parts/greets/backdrop.kla`. Sprite font
relocated to `$0800-$0FFF` so `$2000-$3FFF` is free for the bitmap.

| Phase | Event |
|-------|-------|
| 0 s | 8 X-expanded sprites show 8-char window of greetings text over the koala. DYCP wobble ±3 px Y / ±2 px X. Sprite-7 carousel: sprite 7 doubles as the rightmost entering buffer while it's off-screen-left, so chars slide smoothly in from the right edge. SID filter: res $2 (low — clean, not muddy), V2 through LP ($D417=$22), cutoff floor $70 (gentle shimmer, never muffles the lead). |
| Each beat (every 0.48 s) | Beat counter ticks. Bar IRQ chain runs colour bars. V2 lead shimmer via cutoff sweep ($70..$FF). |
| Scroll | Smooth 9 px/frame motion (`SCROLL_SPEED_TABLE[0]`). The whole row shifts left every frame; at each 40-px wrap, `scroll_pos` advances one char and the sprite ptr table shifts. |
| When `scroll_pos` reaches `settle_text - message` (= the position of " KLOTEN " in the message): | IRQ forces `zp_beat_count = SETTLE_BEAT` (=$7E). Settle path snaps the row to centred " KLOTEN ", flat X / Y. |
| +4 beats (~1.9 s) | `zp_beat_count` ticks naturally to `TRANSITION_BEAT` (= $82). |
| **$F6 == $82** | pefchain loads coda. `fadeout` zeros `$D015`. |

Safety fallback if scroll never reaches the end (data corruption /
speed=0): the time-based FADE_BEAT_START ($70 = 53.8 s) / SETTLE_BEAT
($7E = 60.5 s) / TRANSITION_BEAT ($82 = 62.4 s) constants fire on
schedule and the part exits at ~62 s.

Part length is now coupled to message length: add or remove names in
`.text` lines and the part shortens/lengthens automatically.

---

## Part 6 — coda (`parts/coda/`)

`N_FRAMES = 800` half-rate ticks (doc'd as ~32 s at a 25 Hz subtick
divider — but **measured ~16 s** on 2026-06-04, i.e. it's effectively
running at ~50 Hz / 800 frames. Worth a look if coda feels too short).
This is the **triumphant trophy** moment — full K-S-K-S kit + V1 bass
pattern + V2 lead + V3 triangle arp, held under the title for ~32 s
while the twin Kloot stars dance behind it.

Twin 4-sprite Kloot stars: sprites 0-3 (star 1, brown `$09`) and 4-7
(star 2, cyan `$0E`) each form a 2×2 grid, X+Y-expanded (48×42 per
quadrant, source 24×21). Both stars share the 6 KB Stage E shape
data at `$2000-$37FF` (TR/TL/BL/BR at `$2000/$2600/$2C00/$3200`,
sprite-pointer bases `$80/$98/$B0/$C8`, 24 frames each).

| Frame | Time | Event |
|-------|------|-------|
| 0 | 0 s | Setup: text mode, ROM uppercase chargen at `$1000`, screen `$0400`. Title text painted on rows 11, 13, 15 (KLOTEN MET DE COMMODORE / LEARN EXPLORE DISCOVER / RELEASED AT X2026). `$F6 = $01` enables drum gate so intro's K-S-K-S kit fires through the whole part. `$F8 = $80` restores zp_intro between T_BARS and T_SCROLLER so V1+V2 freq writes fire but V3 stays as triangle (drum_tick's last waveform). All 8 sprites enabled (`$D015=$FF`) with twin-star orbit math driving X/Y every frame. Parallax PETSCII starfield seeded (32 stars across 4 speed tiers). |
| 0 → 799 | 0 → 32.0 s | **Stage F ping-pong zoom breath**: star 1 starts at shape=0 dir=forward → opens with zoom-in; star 2 starts at shape=23 dir=backward → opens with zoom-out. `kloot_shape_N` walks 0→23→0 via shared `kloot_advance` subroutine; rotation reverse-loop is invisible (12-fold symmetry). |
| each zp_frame tick | 25 Hz | Independent shape dividers (`SHAPE_DIV_1=3`, `SHAPE_DIV_2=2`) → fundamentally different rotation rates so lobes drift apart. Independent orbital phases (`ORBIT_SPEED_1=2`, `ORBIT_SPEED_2=3`) for the sine-path orbits at `ORBIT_RADIUS=56`. |
| each frame | 50 Hz | Priority swap fires on bit-6 transition of `(star2_phase - star1_phase)` — happens at max separation so invisible. Swaps sprite slot assignments + colour registers (brown stays brown) and toggles `$D01B` so the in-front star alternates ~every 1.3 s. |
| each half-rate tick | 25 Hz | Parallax starfield: each star's tick decrements; on zero the star erases its current col, dec col with wrap 0→39, draws tier char + colour at the new col. 4 tiers × 8 stars; tier speeds 3/5/8/14. |
| each frame | 50 Hz | V2-cutoff LFO: `$d416 = sin_tab[zp_frame] + $a0` so the filtered lead breathes through the held title (sin_tab values ±56 give a $4a..$d8 cutoff sweep — wide-open, bright). |
| 0 → 799 | 0 → 32.0 s | Border colour cycles through `col_tab` (256-entry slow sine). |
| **800** | **32.0 s** | IRQ writes `$F6 = $30`, border snaps to black, `$D015 = $00` hides sprites; pefchain's `f6 = 30` fires, end loads. |

Per-frame: orbit math + sprite-position writes FIRST (so VIC's
per-raster sprite-Y check sees the new positions before raster 52,
preventing the top/bottom-quad gap), then `INTRO_MUSIC_PLAY` (chord
pad + lead + K-S-K-S kit on V3), then `star_field` (parallax tick).
Sprite pointers re-written every IRQ (50 Hz) via a 4-iteration
Y-indexed loop over `sprite_bases` so the Spindle NMI loader can't
drag them away. `zp_subtick` toggles each IRQ; only every second IRQ
increments the 16-bit half-rate frame counter (`zp_frame` + `frame_hi`)
used to compare against `N_FRAMES`.

**EFO ownership**: `'P', $08, $0F` (code + state + col_tab + sin_tab,
8 pages — `sin_tab` MUST end before `$1000` or it stomps the
inherited intro music tables; see `docs/memory-layout.md` "Stage F
note"). `'P', $20, $37` (all 4 quadrants of Kloot shape data:
`$2000-$25FF` TR, `$2600-$2BFF` TL, `$2C00-$31FF` BL,
`$3200-$37FF` BR — 24 pages, 6 KB). `'I', $10, $12` inherits
intro's music. The four quadrant `.bin` files are passed
separately to `mkpef` via `build.sh` instead of one large
contiguous PRG, avoiding zero-padded gaps across greets' memory.

---

## Part 7 — end (`parts/end/`)

Loops forever (`stay`). One credit cycle:

| Frame | Time | Event |
|-------|------|-------|
| 0 | 0 s | Text-mode credit roll. SID vol = 0, screen/text black. |
| 0→99 | 0→2.0 s | **Fade-in**: zp_fade 0→99. SID vol ramps $00→$0F. Text invisible (color RAM = $00). |
| 99 (TEXT_REVEAL) | 2.0 s | Color RAM painted with gradient. Credit text visible. |
| 2.0→~45 s | **Credit scroll** | yscroll every 4 frames; hardware scroll every 32 frames (next credit line pulls in). **71 credit rows × 32 frames ≈ 45 s per full cycle** (measured 2026-06-04, `zp_text_row $f8` 0→70→0), then loops. Full uppercase A-Z font with custom Å glyph at screencode `$5B`. |

Music: 128-step chord/lead cycle × 24 frames/step = 61.4 s per
cycle. LP filter on (re-asserted every frame).

**Friet easter egg**: pressing space during the credit roll copies
an embedded "Friet met Desire" SID player from a stash at `$4E00` to
`$0801` via a relocatable copier at `$0200`, resets VIC + colour RAM +
BASIC to stock C64 state, then `JMP $0810`. The player runs
standalone with synchronised lyrics and beat-reactive text:
no sprites — lyrics on row 12 flash white→yellow→orange→light-red on
every V3 gate edge (5-frame decay), border pulses brown for 2 frames.
Text is the show. Also on the `.d64` as `LOAD "FRIET",8,1` for
standalone use.

## Colocate hook — `lyric_vec` at `$12B9`

`my_music_play` at `$119E` ends with `JMP (lyric_vec)` instead of
`RTS`. The vector at `$12B9` defaults to an `RTS` stub at `$12BB` —
11-cycle no-op. Any part can write its own handler address into
`$12B9`/`$12BA` during setup to get music-synced callbacks. The
handler fires inside `my_music_play` at the same clock as `mu_step`
— zero drift by construction.

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
