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

```
screenfill ──5.6s──→ intro ──73s──→ interlude ──15s──→ sinus ──5s──→ greets ──15s──→ end (loops)
```

| Part | Duration | Cumulative | Transition ZP | Trigger |
|------|----------|------------|---------------|---------|
| screenfill | 5.6 s | 5.6 s | `$06` (HOLDCNT) | `06 = 00` |
| intro | 73.3 s | 78.9 s | `$F6` (zp_outro) | `F6 = F0` |
| interlude | 15.4 s | 94.3 s | `$F6` (zp_beat_count) | `F6 = 20` |
| sinus | 5.0 s | 99.3 s | `$F6` (zp_timer) | `F6 = 30` |
| greets | 15.4 s | 114.7 s | `$F6` (zp_beat_count) | `F6 = 20` |
| end | loops | — | (none) | `stay` |

**One-pass runtime: ~1 min 55 s** from boot to looping credits.

---

## Part 1 — screenfill (`parts/screenfill/`)

| When | Event | Detail |
|------|-------|--------|
| 0.0 s | setup | Build char table, init ripple counters. Border = BASIC light-blue ($0E). |
| 0.0–2.6 s | **Radial fill** | 16 rings × 8 frames = 128 frames. DEFEEST characters bloom over the BASIC screen. |
| 2.6 s | **Ripple starts** | RADIUS ≥ 16. Border drops to blue ($06). HOLDCNT = 150. |
| 2.6–4.3 s | **Ripple, blue border** | HOLDCNT → 85. Concentric colour waves from screen centre. |
| 4.3 s | **Snap to black** | HOLDCNT = 85. BG + border → black ($00). |
| 4.3–5.6 s | **Text fadeout** | ripple_palette steps through fadetab every 8 frames. |
| 5.6 s | **HOLDCNT = 0** | pefchain loads intro part. |

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

32 beats × 24 frames = 768 frames = **15.36 s**.

| Beat | Time | Event |
|------|------|-------|
| 0–23 | 0–11.5 s | Pad-only: V1 bass muted ($D404 = 0). Plasma + raster bars. |
| 24 (BUILDUP_BEAT) | 11.5 s | V1 bass re-enabled. LP filter sweep starts at cutoff=$40. |
| 24–31 | 11.5–15.4 s | Filter cutoff += $18 per beat: $40 → $58 → $70 → … → $FF. |
| **32 (= $20)** | **15.4 s** | pefchain loads sinus. |

Per-frame: plasma (half rows updated), music, beat phase, raster bars.

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
| **32 (= $20)** | **15.4 s** | pefchain loads end. |

Only ~128 of 864 text characters scroll through before the
32-beat limit triggers the transition.

---

## Part 6 — end (`parts/end/`)

Loops forever (`stay`). One credit cycle:

| Frame | Time | Event |
|-------|------|-------|
| 0 | 0 s | Text-mode credit roll. SID vol = 0, screen/text black. |
| 0→99 | 0→2.0 s | **Fade-in**: zp_fade 0→99. SID vol ramps $00→$0F. Text invisible (color RAM = $00). |
| 99 (TEXT_REVEAL) | 2.0 s | Color RAM painted with gradient. Credit text visible. |
| 2.0→32.7 s | **Credit scroll** | yscroll every 4 frames; hardware scroll every 32 frames (next credit line pulls in). 48 rows × 32 frames ≈ 30.7 s per full cycle, then loops. |

Music: 128-step chord/lead cycle × 24 frames/step = 61.4 s per
cycle. LP filter on (re-asserted every frame).
