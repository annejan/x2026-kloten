# Score baseline — what plays where, with the actual numbers

> 2026-05-21 snapshot of the demo's musical state. Captured live via
> VICE-MCP at commit `058183f`. Reach for this doc when you want to
> discuss the score with someone who knows music — or with future-you
> when deciding what to change. Companion to:
> [`music-theory.md`](./music-theory.md) (theory + voicings),
> [`sound-arc.md`](./sound-arc.md) (filter routing details),
> [`narrative-arc.md`](./narrative-arc.md) (story + visual sync).

## TL;DR (one-paragraph elevator pitch)

Static A-minor chord loop (Am→Em→F→G, 8 bars each, ~125 BPM) running
on intro's `my_music_play` resident in RAM. Three SID voices: punchy
pulse bass walking through octaves, sharp pulse lead playing a 128-step
melody in four 15-second phrases (sparse → 8ths → high climb → descend),
and a peak-volume arp that re-pitches every frame to imply the chord.
A K-S-K-S drum kit on V3 with a V1 sub-bleed adds rhythm from intro's
outro onward. The whole demo cycles the same harmony for ~130 seconds;
all musical interest comes from filter sweeps, voice muting, V3
timbre flipping pulse↔triangle, and dynamic arrangement. End credits
re-init SID for a slow 4× tempo pad reprise, no drums, lunch is over.

## The seven parts at a glance

| # | Part | Time | Trigger out | What plays musically |
|---|------|------|-------------|----------------------|
| 1 | screenfill | ~3 s | `$06 == 0` (HOLDCNT drained) | **silence** — SID untouched |
| 2 | intro | ~30 s | `$f6 == $F0` (zp_outro saturated) | full mix builds: arp → +lead → +bass → +drums |
| 3 | interlude | ~7.7 s | `$f6 == $10` (16 beats × 24 frames) | pad-only ~2.9 s, buildup ~4.8 s with LP sweep |
| 4 | sinus | ~5 s | `$f6 == $30` (frame counter stall) | LP cutoff closes, drums silent, vol fades |
| 5 | greets | ~77 s | `$f6 == $a0` (160 beats) | climax: full mix + V2-filtered "wah" on lead |
| 6 | coda | ~32 s | `$f6 == $30` (32-s timer) | triumphant: full mix held, twin stars dance |
| 7 | end | forever | (none — `stay`) | own player, 4× slower pad reprise + LP mood LFO |

Total intro→coda is ~155 s; end then loops the credit roll forever.

## Harmonic skeleton

**Key:** A natural minor (Aeolian). No accidentals.

**Progression:** `Am | Em | F | G` (i, v, ♭VI, ♭VII), 8 steps per chord,
6 frames per step, 32 steps per loop = **3.84 s per chord cycle**.
Cycles roughly **34 times** from intro start through coda end.

The progression NEVER changes. All variation comes from arrangement.

## Per-voice configuration

### V1 — bass
- Wave: pulse 12.5% duty (`$D403 = $08`)
- ADSR: `$04 / $61` — A=0, D=4, S=6, R=1 (punchy kick-bass)
- Pattern: `bass_pattern[mu_step & 31]` — 8 entries per chord:
  - Am: `A2 A2 A3 A2 A2 E3 A3 A2`
  - Em: `E2 E2 E3 E2 E2 B2 E3 E2`
  - F:  `F2 F2 F3 F2 F2 C3 F3 F2`
  - G:  `G2 G2 G3 G2 G2 D3 G3 G2`
- Range: A2..G3 (~98..196 Hz) — bass-guitar register
- Octave jump on the 7th step of every chord = syncopated lift
- Hijacked to `N_C1` (~33 Hz) for 1 frame on every drum hit (sub-bleed)

### V2 — lead
- Wave: pulse ~37% duty (`$D40A = $06`)
- ADSR: `$02 / $81` — A=0, D=2, S=8, R=1 (sharp, mid-sustain)
- Pattern: `lead_pattern[mu_step]` — 128 entries = 4 phrases × 32 steps
- Phrase character (15.36 s each):
  1. **Sparse opening** — rests every other step, hook in G bar
  2. **Active 8ths** — wide intervallic leaps, no rests
  3. **High climb** — reaches B4 (highest note) over Em
  4. **Descending resolution** — mostly rests, melody "gives up"

### V3 — arp / drum
- Wave: **pulse 25% duty** OR **triangle** depending on `zp_intro`:
  - `zp_intro >= 240` → pulse (intro)
  - `zp_intro < 240` → triangle, inherited from drum_tick's last write
    (interlude/sinus/greets/coda)
- ADSR: `$00 / $F0` — A=0, D=0, S=15, R=0 (peak, held forever)
- Arp: cycles root → 3rd → 5th → octave at 50 Hz, indexed by `mu_step`
  for current chord
- Drum mode: V3 hijacked for 4 frames per kick / snare from `drum_table`:
  - Kick: triangle pitch slam 250→62→30→30 Hz
  - Snare: low-noise transient + triangle body 250→80→50 Hz
- K-S-K-S backbeat at quarter notes (every 4th step boundary)

## Per-part SID state — measured live 2026-05-21

Captured via VICE-MCP after running the demo from boot. Values are
representative snapshots (not exact frame timing).

### Intro (mu_step ~69, $F8 saturating)
```
V1 = 168 Hz (E3 pulse)   ADSR $04/$61   gate=1
V2 = 335 Hz (E4 pulse)   ADSR $02/$81   gate=1
V3 = 168 Hz (E3 pulse)   ADSR $00/$F0   gate=1
$D417 = $00 (no filter routing)   $D418 = $0F (no LP mode)
```

### Interlude buildup / sinus (mu_step ~121, post-buildup)
```
V1 = 99 Hz (G2 pulse)    same ADSR
V2 = 199 Hz (G3 pulse)   gate=0 (just released)
V3 = 99 Hz (G2 triangle) ← already triangle from drum tail
$D417 = $23 (V1+V2 routed, res $2)   $D418 = $1F (LP on)
cutoff hi = $56 (mid-range)
```

### Greets (mu_step ~78, mid-section)
```
V1 = 168 Hz (E3 pulse)
V2 = 335 Hz (E4 pulse)
V3 = 84 Hz  (E2 triangle)
$D417 = $42 (V2 only routed, res $4)   $D418 = $1F (LP on)
cutoff hi = $71 (modulated by zp_wobble_pos, "wah")
```

### Coda (mu_step ~114, late phrase 4)
```
V1 = 177 Hz (F3 pulse)
V2 = 266 Hz (C4 pulse)   ← routed through LP
V3 = 89 Hz  (F2 triangle)
$D417 = $42 inherited from greets   $D418 = $1F
cutoff hi = $4c (FROZEN, no wobble in coda)
$F8 = $80 (gates V1/V2 on, V3 stays triangle)
```

### End credits (own player, separate config)
```
V1: pad ADSR $71/$fa (A=7 slow attack, S=15, R=10)
V2: pad ADSR $51/$f9
V3: ADSR $11/$f8 (fast attack arp)
$D417 = $07 (V1+V2+V3 all routed)   $D418 = $1F (LP on)
cutoff sweep: amp × wave + offset = $60..$8A clean
              $59..$83 dark (modulated by 20-s mood LFO)
END_STEP_FRAMES = 24 (4× slower than intro)
```

## Timing facts

| Unit | Frames | Time | Note |
|------|--------|------|------|
| PAL frame | 1 | 20 ms | hardware |
| Chord step | 6 | 120 ms | `STEP_FRAMES` in intro |
| Beat (4 steps) | 24 | 480 ms | quarter note (125 BPM) |
| Chord (8 steps) | 48 | 960 ms | ~2 bars |
| Full progression | 192 | 3.84 s | Am→Em→F→G once |
| Lead phrase | 192 | 3.84 s | 32 lead notes |
| Full melody | 768 | 15.36 s | 4 phrases |
| Drum cycle | 24 | 480 ms | K-S-K-S = 1 quarter per drum |
| Coda hold | 800 (half-rate) | 32 s | `N_FRAMES` in coda.asm |
| End step | 24 | 480 ms | `END_STEP_FRAMES`, 4× slower |
| End full progression | 768 | 15.36 s | once through Am-Em-F-G |
| End mood LFO | ~5120 | ~20 s | clean ↔ dark breath |

## Per-part audio config matrix

| Part | $D417 | LP mode | Cutoff $D416 | Drums | V3 timbre | $F8 source |
|------|-------|---------|--------------|-------|-----------|------------|
| screenfill | — | — | — | — | — | (SID off) |
| intro | $00 | off | — | enter at zp_outro | pulse | saturates 0→$FF |
| interlude pad | $00 | on | $00 | continues | pulse → triangle | reset to 0, ticks up |
| interlude build | $23 (V1+V2) | on | $40→$FF sweep | continues | triangle | ticks up |
| sinus | $23 (V1+V2) | on | $70→$08 close | OFF | triangle | inherited |
| greets | $42 (V2) | on | wobble_pos\|$40 (~$40..$FF wah) | on | triangle | ~$89 inherited |
| coda | $42 inherited | on | frozen at greets' last value | on | triangle | $80 (deliberate) |
| end | $07 (all 3) | on | mood-LFO $60..$8A baseline | OFF | pulse | own player |

## What's working well

1. **Continuous music across 6 parts** via resident `my_music_play` —
   no audible discontinuities, no cuts, just timbre shifts.
2. **Aeolian never resolves** — fits the demo's "open ending" arc.
3. **V3 timbre flip** (pulse → triangle from interlude onward) is the
   single biggest sonic transition; happens "for free" because of how
   drum_tick + `T_SCROLLER` gate interact.
4. **Drum entrance at intro's outro** maps perfectly onto the visual
   cascade of sprites despawning.
5. **End credits feel different** (own player, slower tempo, all-voice
   LP) so it reads as a clear "outro" musically, not just "loop again".

## Known weaknesses / room for "more epic"

1. **Static chord progression for 130 s.** No substitutions, no
   variations, no key changes. A musician's likely first comment is
   "where's the bridge?". Options:
   - Substitute Am→C in one cycle for a brief major lift
   - Drop the F chord for E (a real V) on one cycle for a stronger pull
   - Modulate up a step (A minor → B minor) just before coda for a
     "trophy" key change

2. **Drum pattern is monolithic K-S-K-S.** Same quarter-note backbeat
   from intro outro through coda. Could add:
   - 8th-note hi-hat ghosts (steal V3 between arp frames)
   - Snare flam / ghost notes on the off-beats
   - Drop drums for 4 beats before SPARKED reveal (interlude)
   - Half-time feel in coda (kick on 1, snare on 3) for "stadium" weight

3. **Coda's cutoff is frozen.** Currently inherits greets' last value.
   Could add a SLOW wobble (much slower than greets', e.g. 32 s
   cycle to match the part length) so the lead breathes during the
   long title hold without being busy.

4. **Lead phrase 4 is mostly rests.** Intentional ("the melody gives
   up"), but for coda we cycle through this phrase too — the trophy
   moment shouldn't feel sparse. Options:
   - Force coda to phase-lock onto phrase 2 or 3 (active 8ths / high
     climb) for its 32-second hold
   - Add a fifth "coda phrase" to lead_pattern (would need 32 more
     bytes in `$10C8`+)

5. **No countermelody.** V3 always plays the arp; V2 always plays the
   lead. A musician might want a second melodic voice (call/response),
   but with 3 SID voices and one already gated to drums, there's no
   room without sacrificing the arp.

6. **No section dynamics within parts.** Within greets' 77 s, the
   only intra-part variation is the lead cycling phrases — chord and
   rhythm are constant. A "drop-and-build" within greets (e.g. drums
   stop for 4 beats halfway through the scroller) would add narrative.

7. **Tempo is fixed at ~125 BPM throughout.** End credits is 4×
   slower but that's a hard cut. A 5-second decel into end would give
   the credit roll more gravity.

## What we'd need to test on hardware

(If you're going to a music-knowledgeable friend, also mention:)

- 6581 vs 8580 SID — the demo TARGETS 8580 for filter
  reproducibility, but ~half of real C64s ship with 6581. Filter
  cutoff values will sound different on 6581 (analog drift).
- PAL vs NTSC — STEP_FRAMES = 6 at 50 Hz PAL = 120 ms; on NTSC's
  60 Hz that becomes 100 ms = ~150 BPM. Demo is PAL-only.
- Real speakers — sub-bass `N_C1` (~33 Hz) is below most laptop
  speakers' fundamental, so the kick weight depends on having a
  bass reflex port or sub.

## Code entry points for further work

- Score data: `parts/intro/intro.asm:585-632` — chord_per_step,
  arp_notes, bass_pattern, lead_pattern
- Music player: `parts/intro/intro.asm:689-875` — `my_music_play`
- Drum kit: `parts/intro/intro.asm:806-908` — drum trigger + tick
  + drum_table
- End credits player: `parts/end/end.asm:910-1126` —
  `end_music_init` + `end_music_play`
- Per-part SID overrides: each part's `setup` + `interrupt` writes
  to `$D417`/`$D418`/`$D415`/`$D416` after `jsr INTRO_MUSIC_PLAY`
