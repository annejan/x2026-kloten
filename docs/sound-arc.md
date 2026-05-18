# Sound arc — how music flows across the six parts

## TL;DR

Intro owns the music. Its **tables and play routine stay resident in
RAM** for the rest of the demo (intro EFO claims `'P', $10, $12`; every
subsequent part declares `'I', $10, $12` so pefchain doesn't overwrite
them). Interlude, greets, sinus, and end all call into intro's
`my_music_play` at `$119E` from their per-frame IRQ, so the chord
progression + lead + arp drift through the entire production with no
discontinuity.

The interesting parts are the **per-part SID register management
overlays** on top of that continuous music.

## The arc

| Part        | What you hear                                                       |
|-------------|---------------------------------------------------------------------|
| screenfill  | (silence — SID untouched, music engine isn't running yet)           |
| intro       | Full mix: bass (V1) + lead (V2) + arp (V3). Master vol fades in.    |
| interlude   | Pad only (lead + arp). V1 muted. Last 8 beats: V1 returns + LP sweep |
| greets       | Full mix returns. V1 = bass, no filter. The "payoff" loudness.       |
| sinus        | Full mix, but LP filter closes ($D418 re-asserted) and vol fades out over last 50 frames. |
| end          | end_music_init re-inits SID for slow chord/lead reprise. PWM + filter sweep. |

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

- **Visual cascade in intro's outro** (sprites despawn one by one,
  bars off, logo un-wipes)
- **V1 mute drop into interlude's pad** — the sudden absence of bass
  signals "we're in the breather now"
- **V1 return + LP cutoff sweep in interlude's last 8 beats** —
  rising tension into greets
- **Full-vol bass + no filter in greets** — the payoff
- **LP filter closing + vol fade in sinus** — the afterglow comedown
- **end's own music_init re-init** with PWM + filter sweep for the
  credit roll reprise

If you're tweaking the score, work WITHIN this rhythm rather than
adding hard cuts. Volume drops anywhere on the resident path leak
into every later part.
