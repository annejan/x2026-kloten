# SID drums — classic techniques + how we apply them

A field guide to writing percussion on the C64 SID, focused on the
3-voice-music-AND-drums problem we face in this demo. References to
specific composers are who made each trick famous, not necessarily
who invented it.

## The fundamental constraint

SID has 3 voices. Real songs need bass + lead + accompaniment + drums
= at least 4 elements. So either:

1. **Dedicate a voice to drums** — quietest melody. Common in
   "tracker"-style productions (Rob Hubbard's later work).
2. **Time-share a voice** — usually V3 cycles between arp/lead and
   drum hits per frame. This is the **Maniacs of Noise** pattern,
   pioneered by Jeroen Tel: the arp plays continuously except for the
   few frames immediately after a beat, when the same voice is
   overridden with a drum sound. The arp's envelope is short so the
   "missing" arp notes during drum frames aren't noticeable.
3. **Borrow ADSR slots** — Tim Follin / Galway sometimes used the
   master volume `$D418` itself as a drum envelope, modulating all
   voices at once. Adds an obvious "ducking" feel.

This demo uses (2): V3 normally plays the arp; kick fires on beat,
overriding V3 for the kick window; after the window, arp resumes.

## Drum recipes

### ⚠️ Hard restart — required to retrigger envelopes

Before any drum recipe will WORK, you have to understand that the
6581 SID **silently drops new attacks** if the gate is already high.
Writing `$D412 = $81` (noise + gate) when the gate was already 1
just changes the waveform — the envelope stays at whatever level it
was already at. This is why our first kick attempt was inaudible:
the music engine writes V3 control = `$41` (pulse + gate) every
frame, so V3's gate has been HIGH continuously since intro.

The fix is the **"hard restart"** technique:
- Set gate to 0 + zero AD/SR registers, hold for ≥ 1 frame
- Then write new ADSR + waveform + gate ON — rising edge triggers
  the attack cleanly

In our voice-sharing setup the music engine writes V3 control = `$41`
EVERY frame. To force a retrigger we need to override that with a
gate-off + zero-ADSR write for at least one full frame BEFORE
gating the new sound:

```kickass
; Frame 1 (HARD RESTART)
lda #$00
sta $D413          ; AD = 0
sta $D414          ; SR = 0
sta $D412          ; control = 0 (gate off, no wave)
; envelope drops to 0 during this frame

; Frame 2 (ATTACK)
lda #$09 / sta $D413           ; AD = new (attack 0, decay 9)
lda #$00 / sta $D414           ; SR = new (no sustain)
... set freq ...
lda #$81 / sta $D412           ; noise + gate ON — clean attack
```

This is what `greets.asm` implements via `zp_kick_state` — state 1
is hard-restart, state 2 is the audible attack, states 3..N are
sweep frames. Without this, all of the recipes below produce
nothing audible when sharing a voice with a gated melody engine.

### ⚠️ The same law bites sustained LEADS (friet easter-egg lesson)

Hard restart isn't only a drum problem. The `friet-met-desire`
easter-egg tune (built from the sibling repo) hit the identical wall
on its **lead voice**, and the fix generalises a principle worth
keeping:

- A "sung" lead wants legato — notes butted onset-to-onset with no
  gap. But if you change pitch *without* dropping the gate, the SID
  silently skips the attack (same rule as above), so the line glides
  with no transient. We tried retriggering (gate off→on) on every
  note to get the accent back — but doing the off→on **within a
  single frame** doesn't give the envelope a frame to fall, so the
  hard restart fails and notes come out glitched or "barely there."
- **Fix:** when filling notes legato, leave a **~2-frame (~40 ms)
  gate-off gap** before the next onset. Inaudible, but it's a real
  hard-restart window, so every note re-attacks cleanly. Continuous
  *and* accented. (In the friet composer this is `dur = gap - 2`.)

Two more lead-clarity traps from the same session:

- **Combined waveforms eat notes.** Selecting tri+pulse (`$50`) for a
  "brighter" lead AND-combines the two waveform outputs → a thin,
  partly-cancelled tone that drops notes on some pitches. Pick a
  single waveform ($10/$20/$40) for anything that must read clearly.
- **Resonance masks the fundamental.** A resonant filter sweep
  ("flange/hoover") is gorgeous, but past ~res $9 the peak overpowers
  the note's own pitch and the melody muddies. res $8 with a ±10
  cutoff-LFO kept the effect without burying the tune.

And one timing law that applies to drums *and* lead: **every voice
must share ONE beat→frame grid.** The friet engine snapped the melody
to an integer-accumulated (Bresenham) 16th grid but left the drums on
`round(beat × frames_per_beat)` — ~30% of hits landed off-grid and
flammed against the lead. Put every voice through the same grid
function and the groove locks.

### Kick — pitch-swept pulse (Jeroen Tel / 808-style)

The defining sound of "epic" SID drums. Pulse wave with a fast
downward pitch sweep over 4-10 frames.

```kickass
on_beat:
    lda #$00 / sta $D413          ; V3 AD = 0 (instant)
    lda #$30 / sta $D414          ; V3 SR = $30 (mid sustain for body)
    lda #$00 / sta $D40E          ; V3 freq lo
    lda #$20 / sta $D40F          ; V3 freq hi START (mid-bass)
    lda #$41 / sta $D412          ; pulse + gate on
    ; window = 8 frames

each_kick_frame:
    lda $D40F / sec / sbc #$03    ; sweep freq hi DOWN
    bcs ok / lda #$01 / ok:
    sta $D40F
```

Variations:
- Start freq `$30` for higher-pitched "kick-snare hybrid"
- Sweep step `$05` for very fast "boom"
- Sweep step `$01` for "tom-like" longer decay

### Kick — noise attack + pulse body (Rob Hubbard)

Two-stage waveform. Noise for the percussive *click*, then pulse for
the *thump*.

```kickass
on_beat:                          ; same envelope as pitched kick
    lda #$00 / sta $D413
    lda #$30 / sta $D414
    lda #$81 / sta $D412          ; noise + gate (first frame only)
    lda #$00 / sta $D40E
    lda #$20 / sta $D40F          ; mid freq for noise body

frame_1:
    lda #$41 / sta $D412          ; switch to pulse + gate
    ; pitch sweep from frame 1 onward (same as above)
```

This is what we use in greets — first frame noise transient, then
pulse with pitch sweep.

### Snare — noise + filter open

```kickass
on_snare:
    lda #$00 / sta $D413          ; AD = 0
    lda #$50 / sta $D414          ; SR = $50 (~80ms sustain)
    lda #$00 / sta $D40E
    lda #$30 / sta $D40F          ; mid-high freq
    lda #$81 / sta $D412          ; noise + gate

each_snare_frame:                 ; optional: open filter for "snap"
    lda #$10 / ora #$70           ; LP + bits 4-6 = HP/BP add
    sta $D418                     ; brighten the mix briefly
```

### Hi-hat — short noise

```kickass
on_hat:
    lda #$00 / sta $D413
    lda #$00 / sta $D414          ; no sustain at all
    lda #$00 / sta $D40E
    lda #$80 / sta $D40F          ; high noise freq
    lda #$81 / sta $D412          ; noise + gate
    ; window = 1-2 frames only
```

### Cymbal crash — ring-modulated noise

Ring-mod a noise voice with another voice's freq. The result is
metallic and inharmonic. Rare in 50Hz-budgeted demos, but
spectacular when it lands.

```kickass
lda #$84 / sta $D412              ; bit 2 = ring mod V3 with V1
                                  ; bit 7 = noise wave
```

## Timing patterns (24-frame beat = ~125 BPM)

### Four-on-floor (dance)

```
Frame 0 : KICK
Frame 24 : KICK
Frame 48 : KICK
...
```

Simplest. Heavy.

### Boom-tah-boom-tah (rock)

```
Frame 0 :  KICK     (beat 1)
Frame 12 : SNARE    (offbeat)
Frame 24 : KICK     (beat 2)
Frame 36 : SNARE    (offbeat)
...
```

What we'd add next if we want a busier feel.

### Kick + 8th-note hats (dance)

```
Frame 0 :  KICK
Frame 6 :  HAT
Frame 12 : HAT
Frame 18 : HAT
Frame 24 : KICK
Frame 30 : HAT
...
```

Very 808. V3 gets hat'd to death — arp barely audible.

## How this demo wires it up

The drum implementation lives in **intro's `my_music_play`**, NOT
in the parts that "look" like they have drums (greets, interlude).
Because every later part calls `INTRO_MUSIC_PLAY = $119E` via the
resident-music inheritance, the drum code propagates automatically.

### K-S-K-S kit (2026-05-20)

Since the May 20 rework, drums are a **table-driven K-S-K-S kit**
(kick and snare alternating on the quarter-note grid). State lives
in intro's music segment around `$128A`:

- `drum_state` — countdown of remaining frames in the current hit window
- `drum_offset` — 0 for kick rows, 8 for snare rows of the drum table

```
drum_table:                     ; 16 bytes, 2 bytes per row × 8 rows
    ; KICK rows (offset 0) — triangle pitch slam, no noise.
    .byte $11, $10              ; triangle gate-on, ~250 Hz
    .byte $11, $04              ; ~62 Hz
    .byte $11, $02              ; sub-bass body (~30 Hz)
    .byte $11, $02              ; hold sub
    ; SNARE rows (offset 8) — low-noise transient + triangle body.
    .byte $81, $20              ; noise gate-on, ~500 Hz rattle
    .byte $11, $10              ; triangle body, ~250 Hz
    .byte $11, $05              ; ~80 Hz
    .byte $11, $03              ; ~50 Hz
```

Trigger:

```kickass
lda zp_outro
beq !drum_done+       ; gated: drums only fire if zp_outro != 0
lda mu_step
and #$03
bne !drum_done+       ; only every 4th step = ~125 BPM beat

; Pick kick (offset 0) or snare (offset 8): bit 2 of mu_step splits
; even/odd quarters, ASL'd to byte-offset into the 16-byte table.
lda mu_step
and #$04
asl
sta drum_offset

lda #DRUM_LEN          ; = 4 (snug, ~80 ms per hit)
sta drum_state

; V1 BASS-BLEED LAYER — Macro Player / SFX-routine pattern. V1 just
; wrote its bass note above; we overwrite with N_C1 (~33 Hz) and
; gate-pulse to retrigger V1's punchy $04/$61 ADSR. The bass-pattern
; note at this kick step is sacrificed; bass resumes the next step.
ldx #N_C1
lda sid_freq_lo,x  / sta $D400
lda sid_freq_hi,x  / sta $D401
lda #$40 / sta $D404   ; gate off → release prior bass note
lda #$41 / sta $D404   ; gate on → fresh attack of the sub thump
!drum_done:
```

Per-frame tick:

```kickass
lda drum_state
beq !drum_skip+
dec drum_state
lda #DRUM_LEN-1
sec / sbc drum_state           ; forward phase index
asl                             ; × 2 bytes/row
clc / adc drum_offset          ; + kick (0) / snare (8) base
tay
lda drum_table,y   / sta $D412 ; ctrl (gate held on throughout)
lda drum_table+1,y / sta $D40F ; V3 freq hi
lda #$00 / sta $D40E
!drum_skip:
```

Current constants:

| Constant | Value | Effect |
|----------|-------|--------|
| `DRUM_LEN` | 4 frames (~80 ms) | Hit window — short, snappy, leaves arp to play between |
| Kick pitch sweep | $10 → $02 hi byte | 250 Hz → 30 Hz over 4 frames (triangle) |
| Snare pitch sweep | $20 (noise) → $03 hi | 500 Hz rattle into 50 Hz triangle body |
| V1 sub-bass | `N_C1` (~33 Hz) | Bass-bleed layer fires on BOTH kick + snare |

### Key design choices

**No hard restart.** V3's envelope is `AD=$00, SR=$F0` (sustain pinned
at peak) from `my_music_init`. The kick is purely waveform + pitch on
top of a constant peak envelope. The kick body relies on that pinned
peak envelope to be LOUD. Waveform switches between pulse (arp) /
noise (snare attack) / triangle (kick + body) without ever re-gating;
envelope stays at peak the whole time so each waveform plays at full
volume. Post-kick arp `$41` (pulse + gate) write swaps waveform with
the gate still on → no envelope retrigger, no audible seam, arp
picks up cleanly.

**Multi-voice layering.** V3 alone reads as thin — it shares its
loudness slot with the arp and competes with V1 bass + V2 lead. The
V1 bass-bleed at `N_C1` reinforces the kick's body with a real
sub-thump using V1's `$04/$61` punchy ADSR. Pattern from the
codebase64 Macro Player (Geir Tjelta / Jeroen Tel) and the
Prince-of-Persia SFX routine — "the kick lives across voices".

**Triangle, not sawtooth.** Sawtooth's all-harmonics buzz reads as
"head punch" (high frequency content); triangle's odd-harmonics-only
+ 1/n² rolloff keeps the kick in the belly band.

### Coda — triumphant K-S-K-S kit + V1 sub-bleed (no dedicated kick)

Coda used to run its own textbook hard-restart V3 kick at ~60 BPM
(the "Coda's V3 kick" section in earlier revisions of this doc;
recover from git history if you want the state machine writeup
back). That was pulled because the K-S-K-S kit's V3 kick row already
IS a triangle pitch-slam thump, and V1's `N_C1` bass-bleed already
IS the sub body — a dedicated layer was redundant.

The triumphant coda config (since 2026-05-21):

- Setup sets `$F6 = $01` → enables intro's `my_music_play` drum
  gate, so the K-S-K-S kit fires through the whole 32-s held title.
- Setup sets `$F8 = $80` (= between `T_BARS` 120 and `T_SCROLLER`
  240) → V1 bass + V2 lead freq writes fire every step boundary,
  but V3's ctrl is NOT re-gated to pulse every frame, so V3 stays
  as triangle (= whatever the drum_tick last wrote = mellow arp
  between drum hits). Triangle arp pairs with the LP-filtered V2
  lead for the cohesive "trophy" mix.
- `$D417 = $26` (V2+V3 routed through LP, res 2) → the
  triangle arp + filtered lead sit in the same space while V1's
  bass-bleed sub-thump stays clean (LP + resonance on the heavy
  low-end kick caused audible filter-clap crunch per beat).
- `$D416` cutoff sweeps via `sin_tab[zp_frame] + $60` over ~10 s
  for a slow breathing motion under the held title.

## Engine considerations

The shared resident `my_music_play` writes V3 freq + control + gate
every frame at chord-step boundaries (every 6 frames in intro). To
add drums to V3 in a downstream part:

1. Call `jsr INTRO_MUSIC_PLAY` first.
2. Then conditionally override V3 freq + control + ADSR.
3. When the drum window ends, **restore V3 AD/SR to intro's arp
   settings** (`AD = $00`, `SR = $F0`) so the next freq write from
   the engine plays the arp note audibly. If you forget this, V3
   stays at the drum envelope (no sustain) and the arp is silent.

In our greets implementation:

```kickass
jsr INTRO_MUSIC_PLAY

lda zp_kick_remain
beq no_kick
... override V3 with kick params ...
dec zp_kick_remain
jmp kick_done
no_kick:
lda #$00 / sta $D413              ; restore arp AD
lda #$F0 / sta $D414              ; restore arp SR
kick_done:
```

## The "4th channel" question — `$D418` digi

The SID has 3 hardware voices. Drum-heavy tunes often want a
dedicated channel that doesn't conflict with bass/lead/arp. The
classic answer is the **`$D418` digi** trick:

- SID's `$D418` register has the master volume in its low 4 bits.
- Writing different values at audio rate creates a tiny DC offset
  on the audio output (the master volume directly attenuates the
  voice mix, but also has a small leakage path that produces signal
  even when no voice is sounding).
- Stream 4-bit samples through `$D418` at ~8 kHz from a timer IRQ
  and you get audible PCM that doesn't use any of the three voices.

**The catch — chip revision matters:**

- **6581 (original SID)**: digi loud and clear. This is what
  Hubbard/Galway/Tel exploited for sample-based drums.
- **8580 (later SID, most modern C64s)**: the leakage path was
  "fixed" — digi is barely audible without **digiboost** (a hardware
  mod adding a small voltage offset on the audio output).
- **VICE**: digi works in 6581 emulation, partial in 8580 mode
  unless `SidResidDigiBoost = 1` is set. Demos targeting real
  hardware are usually conservative.

For this demo we use the **voice-share + hard-restart pattern** (see
above) instead of `$D418` digi, for portability across SID revisions
and to keep the IRQ budget free. We get one "drum channel" by
time-slicing V3 between arp and percussion frames — what most
4-channel-feel SID tunes actually do (Cybernoid II, Wizball, Commando
all share V3 like this).

If we needed BIG drum sounds (sampled snare, full hi-hat patterns)
we'd add a `$D418` digi player as a timer IRQ that streams a 4-bit
PCM buffer, accepting we'd need a digiboost'd 8580 or a 6581 to
hear it properly. For now, the voice-share kick is the right call.

## Recommended listening (real C64 SIDs to study)

- Jeroen Tel — **Cybernoid II** loader (the kick that defined demoscene drums)
- Rob Hubbard — **Commando** (noise+pulse layered kick)
- Martin Galway — **Wizball** (complex drum pattern in 3 voices)
- Chris Hülsbeck — **Turrican** (filter-modulated drums)
- Tim Follin — **LED Storm** (multiple drum sounds time-shared on V3)

HVSC (High Voltage SID Collection) is the canonical archive. Many
tunes there have hidden percussion in V3 that's only obvious when
you mute the other voices in a SID player.

## When NOT to add drums

- **Pad sections** — a slow, sustained chord pad gets ruined by
  percussive interruption. In this demo, end (credit roll) is
  deliberately drum-free.
- **Fade-in moments** — drums create attacks; attacks fight a fade-in.
- **Build-up bars** — if the part is building tension, no-drums-yet
  is itself a build-up element.

We use this in interlude: pad-only first ~6 beats (V1 muted via
$D404=0 AND V3 muted via $D418 bit 7 = "V3 off", so the K-S-K-S kit
and the arp are both silent — only V2 lead audible under the
typewriter), build-up from BUILDUP_BEAT onward (V3 bit clears →
drums + arp slam back in, V1 returns, LP filter sweep), greets
(drums + bass + full mix = climax), end (drum-free reprise).
