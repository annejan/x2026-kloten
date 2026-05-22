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
| interlude   | Pad-only first ~2.9 s: V1 muted, V3 muted via `$D418` bit 7 ("V3 off"), so ONLY V2 lead is audible while line A "FOR YEARS…" types out over 2.8 s — music-box pad under the typewriter confession. `mu_step` forced to 32 in setup so the lead is in phrase 2 ("active 8ths") for movement. V2 PWM modulates via `zp_xphase` for a slow phaser feel. Last ~4.8 s buildup: V3-off bit clears so the K-S-K-S kit + arp slam back in, V1 returns, LP cutoff ramps from `$70` upward with V1+V2 routed through the filter (res $2), sprite-letter "SPARKED" drops with white-border flash. |
| sinus       | **Breakdown.** LP filter closes — and now actually closes audibly because V1 + V2 are routed through it ($D417 = $23, res $2). Cutoff ramps $70 → $08 over the duration; vol fades over the last 50 frames. Drums silent (sinus zeros `$F6 = zp_outro` — the gating byte). The eye of the storm before the drop. |
| greets      | **Climax / drop.** Drums return (greets' setup re-arms `$F6`), full mix + lead + arp. V2 (lead) routed through LP filter ($D417 = $42, res $4) with a slow cutoff "wah" — `zp_wobble_pos` OR'd with $40 ramps $40..$FF over 5 s breathing the melody. DYCP scroller tells the personal arc on top of the loudest moment. |
| coda        | **The trophy — triumphant.** Setup sets `$F6 = $01` so the K-S-K-S drum kit from intro's `my_music_play` keeps firing through the whole part (kick + snare alternating on V3, V1 bass-bleed sub-thump on every hit). Setup ALSO sets `$F8 = $80` to restore intro's `zp_intro` after interlude's `zp_plasma_tgl` clobber — high enough that V1 bass and V2 lead freq writes fire (T_BARS=120) but low enough that V3 ctrl is NOT re-gated to pulse every frame (T_SCROLLER=240), so V3 keeps the **mellow triangle arp timbre** that drum_tick left behind. `$D417 = $26` (V2+V3 routed through LP, res 2) — V1 bass-bleed kept clean because routing the sub-thump through LP + resonance caused audible filter-clap crunch per beat. `$D416` cutoff sweeps via `sin_tab[zp_frame] + $60` over ~10 s for a slow breathing motion under the held title. This is the LOUDEST moment of the demo — full mix held aloft for ~32 s while the twin Kloot stars dance behind the title. |
| end         | `end_music_init` re-inits SID for slow chord/lead reprise: V2+V3 routed through LP filter ($D417=$06, V1 bass clean so it doesn't phase along with the mood LFO sweep), V1 walks bass_pattern at END_STEP_FRAMES=24 (4× slower than intro's 6), V2 plays lead_pattern at the same slow tempo, V3 arps within the current chord changing every 4 frames. Cutoff baseline $60 (raised from $30 for a brighter, more ethereal feel) with a slow mood LFO breathing between "clean" and "dark" filter sweeps. No drums. The credit-roll outro. |

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

## Music continuity through load gaps (the `'M'` + `bit $0000` trick)

Pefchain inserts blank-filler effects between parts to mask the disk
load — they paint a solid black screen and run a minimal IRQ. Without
any setup, those blanks DON'T call `my_music_play`, so the SID just
sits playing whatever was last written until the next part's IRQ takes
over. With ~8 KB of koala bitmap to stream into greets, those blanks
total ~11-18 s before each big part, which used to manifest as ~0.5 s
audible drop-outs at every transition.

The fix uses Spindle's standard "installed music player" mechanism:

1. **Intro's EFO header declares the `'M', $9e, $11` tag** — tells
   pefchain that `my_music_play` lives at `$119e` and should be the
   global play routine for the whole demo.
2. **Every other part (interlude, sinus, greets, coda) has a
   `musichook:` label in its IRQ** pointing at a 3-byte placeholder
   `bit $0000` (= `.byte $2c, $00, $00`). The EFO header's `callmusic`
   field references this label.
3. **At link time, pefchain rewrites every `bit $0000` placeholder to
   `jsr $119e`** — so the part's IRQ ends up calling music normally,
   AND the auto-inserted blank-filler parts get a matching `jsr $119e`
   injected too.

Net effect: SID music ticks at 50 Hz continuously from intro's first
note through end-credits, regardless of how long pefchain spends
loading between parts. End is the exception — it does `end_music_init`
which clears SID and runs its own player. The very last transition
(coda→end) still sees one frame of intro's player from the blank
filler before end's setup takes over, so there's no audible seam.

If a part needs to install a different player (e.g. a SID rip), put
its own `'M', lo, hi` tag in that part's EFO and pefchain re-routes
the callmusic placeholders from that point onward.

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
every later part that calls it (interlude / greets / coda — sinus
also calls it, but its setup zeros `$F6` so the resident drum gate
stays closed there for the breakdown breather. Coda explicitly OPENS
the gate by setting `$F6 = $01` in setup, so the K-S-K-S kit fires
through the whole held title — see the "Coda" entry in the arc
table above).

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
- Coda: setup sets `$F6 = $01` → **resident drums FIRE** through the
  whole 32-s held title. The K-S-K-S kit + V1 bass-bleed carry the
  trophy weight; no dedicated coda V3 kick needed.
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
- **V1 mute + V3-off + typewriter "FOR YEARS NO TIME FOR BREADBIN
  CODE" on interlude's plasma** — sudden silence except for the V2
  lead with PWM phaser, the human's confession types out char by
  char during the music-box pad. The story's line 1 lands here.
- **V3-off bit clears + V1 returns + LP cutoff sweeps from $70 + the
  K-S-K-S kit + arp slam back in + sprite-letter "SPARKED" drop on
  the buildup beat** — story line 2 (the AI's answer, drops as 8
  hires sprites from above, white border flash on landing) lands
  exactly when the full mix slams back in. The two-line joke is
  complete *as* the music explodes back into life.
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
- **end's own `music_init` re-init** with PWM-shimmer pulse arp + filter sweep for the
  credit roll reprise — quiet, no drums, settles to the title card.
  Lunch is over.

If you're tweaking the score, work WITHIN this rhythm rather than
adding hard cuts. Volume drops anywhere on the resident path leak
into every later part.

## End-credits audio

`end_music_play` runs its own SID engine (not intro's `my_music_play`)
at 4× slower tempo (`END_STEP_FRAMES=24`). V1 walks `bass_pattern`
with octave jumps every 3rd step, V2 plays `lead_pattern`, V3 arps
through the current chord changing every 4 frames.

Filter routing: `$D417 = $06` (V2+V3 through LP, V1 bass clean).
Cutoff baseline $60 with a ~20 s mood LFO cycling the filter between
clean (~$60) and dark (~$8A). V3 arp is pulse with PWM walking the
high byte $04..$0B (25%..68% duty) per frame — a gentle phaser
shimmer that gives the credit roll its nostalgic character. No drums.

### V1 bass walks `bass_pattern`

`end_music_play`'s V1 freq write reads `bass_pattern[mu_step & 31]`
(32-entry table with octave jumps every 3rd step, e.g. Am:
`A2 A2 A3 A2 A2 E3 A3 A2`) for natural motion every step (~480 ms)
without becoming busy. Same pattern as intro's bass; at end's 4×
slower tempo.
