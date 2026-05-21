# Sound arc — how music flows across the seven parts

> Companion to [`narrative-arc.md`](./narrative-arc.md). That doc
> describes the story + visual beats; this one is the music + SID
> register side of the same arc. Both lock in step — every text
> reveal sits on an audio shift, every visual climax has a music
> moment under it.

## TL;DR

Intro owns the music. Its **tables and play routine stay resident in
RAM** for the rest of the demo (intro EFO claims `'P', $10, $12`; every
subsequent part declares `'I', $10, $12` so pefchain doesn't overwrite
them). Interlude, sinus, greets, and coda all call into intro's
`my_music_play` at `$119E` from their per-frame IRQ, so the chord
progression + lead + arp drift through six of the seven parts with no
discontinuity. End is the exception — it runs its own `end_music_init`
+ player for the credit-roll reprise.

The interesting parts are the **per-part SID register management
overlays** on top of that continuous music.

## The arc

| Part        | What you hear                                                       |
|-------------|---------------------------------------------------------------------|
| screenfill  | (silence — SID untouched, music engine isn't running yet)           |
| intro       | Bass + lead + arp build in. Drums kick in late (when `zp_outro != 0` — intro's outro animation starts, ~20 s in). K-S-K-S backbeat: V3 paints kick (triangle pitch slam) and snare (low-noise + triangle body) alternating on the quarter; V1 bass-bleeds N_C1 (~33 Hz) sub under both. |
| interlude   | Pad-only first ~2.9 s (V1 muted, line A "FOR YEARS…" typewriter reveals over 2.8 s). Last ~4.8 s buildup: V1 returns, LP cutoff ramps up with **V1 + V2 both routed through the filter** (res $2) so the bass AND lead open up together, sprite-letter "SPARKED" drops with border flash, drums continue from intro. |
| sinus       | **Breakdown.** LP filter closes — and now actually closes audibly because V1 + V2 are routed through it ($D417 = $23, res $2). Cutoff ramps $70 → $08 over the duration; vol fades over the last 50 frames. Drums silent (sinus zeros `$F6 = zp_outro` — the gating byte). The eye of the storm before the drop. |
| greets      | **Climax / drop.** Drums return (greets' setup re-arms `$F6`), full mix + lead + arp. V2 (lead) routed through LP filter ($D417 = $42, res $4) with a slow cutoff "wah" — `zp_wobble_pos` OR'd with $40 ramps $40..$FF over 5 s breathing the melody. DYCP scroller tells the personal arc on top of the loudest moment. |
| coda        | **The trophy — triumphant.** Setup sets `$F6 = $01` so the K-S-K-S drum kit from intro's `my_music_play` keeps firing through the whole part (kick + snare alternating on V3, V1 bass-bleed sub-thump on every hit). Setup ALSO sets `$F8 = $80` to restore intro's `zp_intro` after interlude's `zp_plasma_tgl` clobber — high enough that V1 bass and V2 lead freq writes fire (T_BARS=120) but low enough that V3 ctrl is NOT re-gated to pulse every frame (T_SCROLLER=240), so V3 keeps the **mellow triangle arp timbre** that drum_tick left behind. `$D417 = $42` (V2 routed through LP) is inherited from greets unchanged — coda continues greets' filtered-lead character with the cutoff frozen at greets' last value (no wobble modulation in coda itself). This is the LOUDEST moment of the demo — full mix held aloft for ~32 s while the twin Kloot stars dance behind the title. (Earlier coda had a dedicated sparse V3 thump at ~60 BPM, but the K-S-K-S kick already IS a triangle pitch-slam thump and the bass-bleed already IS the sub body, so the dedicated layer was redundant — pulled.) |
| end         | `end_music_init` re-inits SID for slow chord/lead reprise: V1+V2+V3 all routed through LP filter ($D417=$07), V1 walks bass_pattern at END_STEP_FRAMES=24 (4× slower than intro's 6), V2 plays lead_pattern at the same slow tempo, V3 arps within the current chord changing every 4 frames. Cutoff baseline $60 (raised from $30 for a brighter, more ethereal feel) with a slow mood LFO breathing between "clean" and "dark" filter sweeps. No drums. The credit-roll outro. |

## Why my_music_play is special

It runs on **every** part from intro onward via the inherited address
`$119E`. That means decisions baked into `my_music_play` propagate to
every part that calls it. The most important one:

```kickass
// in my_music_play
lda zp_intro                ; counter that saturates at $FF in intro
lsr / lsr / lsr             ; vol = intro >> 3 (caps at $1F)
cmp #$10
bcc !vin_ok+
lda #$0F                    ; clamp to $0F (max SID vol)
!vin_ok:
sta $D418                   ; SID master volume
```

**Critical pitfall** (we've shipped this bug already, don't redo it):
There used to be a `vol_out = zp_outro >> 3` subtraction before the
`sta $D418`, intended to fade the master volume out during intro's
outro animation. The problem: `zp_outro` saturates at `$F0` and stays
there for the rest of the demo. So once intro's outro completes:

- `vol_in - vol_out = $0F - $0F = 0` → SID muted
- Interlude and greets both call `my_music_play` every frame → both
  silently muted, every frame
- Interlude's `setup` writes `$D418 = $1F` once, then the first
  `my_music_play` call wipes it back to 0

If you ever need an audio fade-out, do it **outside** `my_music_play`
and gate it on a counter that ONLY ticks in the relevant part. Don't
modify shared resident code with global side effects.

## `zp_intro` thresholds gate the per-voice writes

`my_music_play` reads `$F8` (zp_intro) and uses three thresholds to
decide which voices to actually write each frame:

| Threshold | Constant | Behaviour above the threshold |
|-----------|----------|------------------------------|
| 40 | `T_BALLS` | V2 lead freq write fires at step boundaries |
| 120 | `T_BARS` | V1 bass freq write fires at step boundaries |
| 240 | `T_SCROLLER` | V3 ctrl re-written to **pulse + gate** (`$41`) every frame |

Intro saturates `$F8` to `$FF` over ~10 s, so all three gates are open
through intro's late phase. But **interlude reuses `$F8` as
`zp_plasma_tgl`** (zeros it on setup, increments per IRQ). By the
time we reach sinus / greets / coda, `$F8` holds whatever value
plasma_tgl happened to land on (typically `$80`-ish in greets after
interlude's 7.7 s run).

That's load-bearing! With `$F8` between `T_BARS` (120) and
`T_SCROLLER` (240):
- V1 + V2 patterns walk normally
- V3 ctrl **is NOT re-gated to pulse** each frame, so V3 keeps the
  triangle ctrl byte that `drum_tick` last wrote → **V3 arp sounds
  as a mellow triangle**, not a pulse

That triangle-arp timbre is a big part of why greets reads as
"flowing musically" rather than as a busy three-pulse mix. Coda
deliberately sets `$F8 = $80` in setup to inherit the same triangle
timbre under the held title. Slamming `$F8 = $FF` instead (which we
tried briefly) re-armed V3's pulse waveform every frame and made the
arp clash sonically against the V2 lead — the listener heard it as
"different notes / different key" even though the pitches matched
the chord.

See [`docs/music-theory.md`](./music-theory.md) — "V3 timbre is
controlled by `zp_intro`" for the four-row pitfall table.

## The $D418 filter-mode contract

`$D418` packs two unrelated things:

| Bits | Meaning                                            |
|------|----------------------------------------------------|
| 0-3  | Master volume (0-15)                               |
| 4    | LP filter mode                                     |
| 5    | BP filter mode                                     |
| 6    | HP filter mode                                     |
| 7    | Cut V3 to output (V3 muted if set)                 |

`my_music_play` writes a vol-only value (bits 4-7 = 0). So any part
that needs LP/BP/HP mode active must **re-write `$D418` after the
`jsr INTRO_MUSIC_PLAY` call, every frame**:

```kickass
jsr INTRO_MUSIC_PLAY
lda #$1F                ; LP mode (bit 4) + vol 15
sta $D418
```

See `parts/interlude/interlude.asm` — its build-up filter sweep relies
on LP mode being asserted every frame.

## Drums in `my_music_play`

Percussion lives inside intro's `my_music_play` and propagates to
every later part that calls it (interlude / greets — sinus and coda
also call it, but their setups zero `$F6` so the resident drum gate
stays closed there. Coda then layers its OWN V3 kick on top, owning
the voice for the entire part).

### K-S-K-S kit (since 2026-05-20)

The original "single rumble" kick has been replaced by a two-drum
kit built from a 16-byte table (`drum_table` at the end of intro's
music segment). Both drums share the same DRUM_LEN=4 window, the
same V1 sub-bass layer, and the same gate-on-throughout / peak-ADSR
pattern — the character difference is the V3 voicing.

```
drum_table:
    ; KICK rows (offset 0) — pure triangle pitch slam, no noise.
    .byte $11, $10   ; triangle, ~250 Hz
    .byte $11, $04   ; ~62 Hz
    .byte $11, $02   ; ~30 Hz sub
    .byte $11, $02   ; hold sub
    ; SNARE rows (offset 8) — low-noise transient + triangle body.
    .byte $81, $20   ; low noise, ~500 Hz
    .byte $11, $10   ; triangle, ~250 Hz
    .byte $11, $05   ; ~80 Hz
    .byte $11, $03   ; ~50 Hz
```

Architecture:

```kickass
; --- DRUM trigger (at step boundary, every 4th step = ~125 BPM) ---
lda zp_outro
beq !drum_done+       ; drums gated: only fire if zp_outro != 0
lda mu_step
and #$03
bne !drum_done+

; Pick kick (offset 0) or snare (offset 8): bit 2 of mu_step splits
; even/odd quarters, ASL'd to byte-offset into the 16-byte table.
lda mu_step
and #$04
asl
sta drum_offset

lda #DRUM_LEN
sta drum_state

; V1 BASS-BLEED — N_C1 sub-bass thump on EVERY hit. Replaces the
; bass-pattern note at this step; V1's punchy $04/$61 ADSR shapes it.
; Where the actual low-end weight comes from — a 3-voice chip can't
; afford to leave the kick on a single voice.
ldx #N_C1
lda sid_freq_lo,x / sta $D400
lda sid_freq_hi,x / sta $D401
lda #$40 / sta $D404   ; gate off → release prior bass note
lda #$41 / sta $D404   ; gate on → fresh attack of sub-bass thump

!drum_done:

; --- DRUM tick (every frame, end of my_music_play) ---
lda drum_state
beq !drum_skip+
dec drum_state
lda #DRUM_LEN-1
sec / sbc drum_state
asl                    ; phase × 2 bytes/row
clc / adc drum_offset  ; + kick/snare offset
tay
lda drum_table,y   / sta $D412   ; ctrl (gate stays on throughout)
lda drum_table+1,y / sta $D40F   ; V3 freq hi
lda #$00 / sta $D40E
!drum_skip:
```

The state bytes `drum_state` + `drum_offset` live in intro's music
segment (around `$128A`), so every part inheriting `'I', $10, $12`
sees the same state.

### Why the kit is built this way

- **V3 alone can't paint a kick** — it's competing with V2 lead and
  the arp it shares its voice with. The V1 bass-bleed adds the sub
  that makes the kick read as a hit, not a thin click. Pattern from
  the codebase64 Macro Player (Geir Tjelta / Jeroen Tel) and the
  Prince-of-Persia SFX routine.
- **Peak-ADSR throughout** — kick rides at full volume because the
  arp's $00/$F0 envelope is left untouched. Punch comes from waveform
  contrast and pitch sweep, not envelope dynamics. The post-kick arp
  $41 (pulse+gate) write swaps waveform with gate held on → no
  envelope retrigger, no attack ramp, no audible seam.
- **Triangle, not sawtooth** — sawtooth's all-harmonics buzz reads as
  "head punch" (high frequencies); triangle's odd-harmonics-only +
  1/n² rolloff keeps the energy in the belly band where the kick
  belongs.
- **Bass note sacrificed every 4th step** — V1 plays the sub-thump
  instead of the scheduled bass note on kick steps. 3 of every 4
  bass notes survive; kicks land on the quarter. Cost worth paying.

### The `zp_outro != 0` gate

Drums fire only when `zp_outro` is non-zero. This means:

- Intro's first ~20 s: `zp_outro = 0` → no drums (clean buildup)
- Intro's outro animation (sprites despawn, etc.): `zp_outro` ticks
  from `1` toward `$F0` → DRUMS ENTER LATE
- Interlude/greets: `$F6` repurposed as their own counters but
  always > 0 once setup runs → drums continue
- Sinus: setup zeros `$F6` (which is `zp_timer` there), kept at 0
  until the very last frame → **resident drums silent** = the comedown
- Coda: setup zeros `$F6` (also `zp_timer`) → **resident drums silent**,
  but coda runs its own V3 kick state machine that overrides the arp
  every frame
- End: doesn't call `my_music_play` (uses its own routine) → no drums

### Why this gating works for "cohesive music"

Story interleave depends on this:
- Sad pad in interlude (after a brief drum exit at transition):
  drums quickly return at beat 1 because `$F6` ticks to 1 fast
- Greets climax: drums in their natural place
- Sinus visual breather: drums genuinely STOP for ~5 s, giving the
  ear a moment before end's reprise

## Per-voice muting trick

`my_music_play` re-writes V1/V2/V3 freq + control at chord-step
boundaries (every `STEP_FRAMES = 6` frames). Between boundaries the
voices play whatever you last wrote.

To mute one voice without modifying the music engine:

```kickass
jsr INTRO_MUSIC_PLAY    ; engine may have just gated a new bass note
lda #$00
sta $D404               ; force V1 control = 0 (no wave + gate off)
```

The voice stays silent because the engine only writes new control on
step boundaries; we squash it again every frame in between. Crucially
**do NOT zero `$D405`/`$D406` (AD/SR)** if you intend to un-mute
later — the envelope shape needs to survive so the bass sounds right
when it returns. Set ADSR once in intro's `my_music_init`; leave it
alone elsewhere.

## Inter-part transitions

There's no audio fade between parts — the music carries continuously.
The "feeling of transition" is carried by:

- **Drums ENTERING late in intro** (when `zp_outro` arms — the
  outro cascade visually mirrors the audio escalation)
- **Visual cascade in intro's outro** (sprites despawn one by one,
  bars off, logo un-wipes)
- **V1 mute + typewriter "FOR YEARS NO TIME FOR BREADBIN CODE" on
  interlude's plasma** — sudden bass drop + the human's confession,
  char by char during the pad phase. The story's line 1 lands here.
- **V1 return + LP cutoff sweep (V1 + V2 both filtered) + sprite-letter
  "SPARKED" drop on the buildup beat** — story line 2 (the AI's
  answer, drops as 8 hires sprites from above, white border flash
  on landing) lands exactly when the filter opens and the bass
  returns. The two-line joke is complete *as* the music opens up.
- **Drums STOP + LP filter close + vol fade in sinus** — the
  breakdown / breather, the calm before the drop. Visual is a
  hypnotic sine wobble of repeating DEFEEST text. The LP close is
  now audibly closing the bass + lead because V1 + V2 are routed
  through the filter ($D417 = $23) — previously the cutoff sweep was
  silent because no voices were routed.
- **DYCP scroller + LP-filtered lead "wah" telling the full story in
  greets** — the climax with drums returning + bass + filtered lead
  ($D417 = $42, V2 through filter w/ res $4) + arp. The cutoff
  follows `zp_wobble_pos | $40` so the melody breathes 5 s/cycle in
  step with the visual DYCP motion, on top of the loudest moment of
  the demo.
- **Coda's full K-S-K-S kit under "KLOTEN MET DE BROODTROMMEL"**
  — the triumphant moment. Drums from intro's resident kit
  CONTINUE into coda (setup sets `$F6 = $01`); the kick + snare
  + V1 bass-bleed all carry through the held title for ~32 s.
  Visually: twin Kloot stars dancing on wide orbits + parallax
  PETSCII starfield + title held steady. Loudest moment of the
  demo, by design — the audience hears, sees, *gets it*.
- **end's own `music_init` re-init** with PWM + filter sweep for the
  credit roll reprise — quiet, no drums, settles to the title card.
  Lunch is over.

If you're tweaking the score, work WITHIN this rhythm rather than
adding hard cuts. Volume drops anywhere on the resident path leak
into every later part.

## End-credits darkening (post 2026-05-21, PR #31)

Before PR #31 (coda parallax starfield), the end credits read as
*clear, calm, perfect* — V3 PWM (pulse hi 4..11) and LP filter
cutoff sweep ($20..$58, 90° out of phase) doing the "gentle phaser
tone on the arp" that end.asm:983-985 documents intentionally.

After PR #31 lands, the **same end.asm code** plays noticeably
darker / more flanger-y — the gentle phaser turns into something
closer to a chorus or detuned-doubling effect. A/B comparison
(`/tmp/outline-64-main.d64` vs `/tmp/outline-64-parallax.d64`,
2026-05-21) confirms the difference is real and reproducible.

**Root cause is not in end.asm itself.** `end_music_init` does a
full SID-register clear at lines 911-915 before any play, so no
voice state can leak in from coda. The change must come from
upstream pefchain load order or RAM contents the player reads
indirectly. The two things PR #31 changed that could plausibly
ripple this far:

- **Coda's `'P'` tag widened from $08-$0B to $08-$0F**, honestly
  claiming the 8 pages it actually uses (the old narrower claim was
  a latent bug — pefchain had been silently overwriting $0C-$0E
  during coda). Pefchain's load schedule for end's payload very
  likely shifts as a result, which can change which page-fragments
  of end's data are streamed in vs already-resident when end's
  setup runs.
- **Coda's IRQ now writes screen RAM every half-rate tick** (parallax
  star erase + redraw) instead of only colour RAM (the old static
  twinkle). This in itself shouldn't reach end's audio path, but
  the combined IRQ-cycle-budget shift may affect Spindle's
  background-load progress at the coda → end handoff.

### Mood LFO — clean↔dark breath (shipped 2026-05-21)

The polish from the bullet list below has been built. `end_music_play`
now:

- Maintains a `mood_phase` byte incremented at frame/4 (~12.5 Hz tick)
- Reads `wave_xscroll[mood_phase + $C0]` so phase 0 lands at the
  sine trough → depth 0 → credits **start fully clean** for the first
  few seconds before drifting toward dark
- Scales the filter cutoff sweep amplitude: `amp = 4 + (depth >> 1)`
  (4..7) and the offset `$60 - depth` ($60..$59 — bumped from the
  original $30 baseline to $60 on 2026-05-21 for a brighter, more
  ethereal credit roll). The result is a slow ~20 s breath between
  the clean and dark filter moods.

### V1 walks `bass_pattern` (shipped 2026-05-21)

`end_music_play`'s V1 freq write used to read the chord root from
`arp_notes[chord*4]`, so the bass camped on one pitch for the 8 step
boundaries each chord held — read as a stuck single-note drone.
Switching to `bass_pattern[mu_step & 31]` (32-entry table with octave
jumps every 3rd step, e.g. Am: `A2 A2 A3 A2 A2 E3 A3 A2`) gives the
bass natural motion every step (~480 ms) without becoming busy. Same
fix as intro's bass; just at end's 4× slower tempo.
