# Sound arc — how music flows across the seven parts

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
| intro       | Bass + lead + arp build in. Drums kick in late (when `zp_outro != 0` — intro's outro animation starts, ~20 s in). |
| interlude   | Pad-only first 11 s (V1 muted). Last 4 s: V1 returns + LP cutoff sweeps open. Drums continue from intro. The "BUT THEN KLOOT WALKED IN" tease. |
| sinus       | **Breakdown.** LP filter closes ($D418 re-asserted) and vol fades over the last 50 frames. Drums silent (sinus zeros `$F6 = zp_outro` — the gating byte). The eye of the storm before the drop. |
| greets      | **Climax / drop.** Drums return (greets' setup re-arms `$F6`), full mix + lead + arp. DYCP scroller tells the personal arc on top of the loudest moment. |
| coda        | **Aftermath.** Intro's drums silenced again (coda's setup zeros `$F6`), but coda *owns* V3 for the whole part — overrides the arp every IRQ with its own hard-restart kick on a ~60 BPM cadence. Chord pad + lead drift on V1/V2 under a sparser, slower thump than greets. Title card sits quietly while the music breathes out. |
| end         | `end_music_init` re-inits SID for slow chord/lead reprise. PWM + filter sweep. No drums. The credit-roll outro. |

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

Architecture:

```kickass
; --- V3 drum trigger (at step boundary) ---
lda zp_outro
beq !drum_done+       ; gated: drums only fire if zp_outro != 0
lda mu_step
and #$03
bne !drum_done+       ; only every 4th chord step = every 24 frames = ~125 BPM
lda #DRUM_LEN
sta drum_state        ; arm a new kick window
lda #DRUM_FREQ_HI
sta drum_freq         ; shadow of V3 freq hi (SID regs write-only)
!drum_done:

; --- V3 drum tick (every frame, end of my_music_play) ---
lda drum_state
beq !drum_skip+
dec drum_state
lda drum_freq
sec / sbc #DRUM_SWEEP
... sweep down to DRUM_FLOOR, store back ...
sta $D40F
lda #$00 / sta $D40E
lda #$81 / sta $D412   ; noise + gate
!drum_skip:
```

The two-byte `drum_state` + `drum_freq` live in intro's music
segment (around `$128A`), so every part inheriting `'I', $10, $12`
sees the same state.

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
- **V1 mute drop + the "FOR YEARS NO TIME FOR BREADBIN CODE" text
  appearing on interlude's plasma** — the sudden bass drop +
  sad admission together
- **V1 return + LP cutoff sweep + "BUT THEN KLOOT WALKED IN" tease
  appearing in interlude's last 4 s** — rising tension, the build
- **Drums STOP + LP filter close + vol fade in sinus** — the
  breakdown / breather, the calm before the drop. Visual is a
  hypnotic sine wobble of repeating DEFEEST text.
- **DYCP scroller telling the full story in greets** — the climax
  with drums returning + bass + lead + arp + the personal arc on
  the loudest moment of the demo
- **Coda's sparse hard-restart kick under the title card** — drums
  from intro's gated player drop out again, but coda owns V3 and
  fires its own slow ~60 BPM thump under the held chord. The room
  settles. Title sits centered on a quiet screen for ~10 s.
- **end's own `music_init` re-init** with PWM + filter sweep for the
  credit roll reprise — quiet, no drums, settles to the title card

If you're tweaking the score, work WITHIN this rhythm rather than
adding hard cuts. Volume drops anywhere on the resident path leak
into every later part.
