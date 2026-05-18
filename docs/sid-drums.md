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

Two zp-style bytes live in intro's music segment (around `$128A`):

- `drum_state` — countdown of remaining frames in current kick window
- `drum_freq` — shadow of V3 freq hi (SID `$D40F` is write-only)

Trigger condition (inside `my_music_play`):

```kickass
lda zp_outro
beq !drum_done+       ; ⚠️ gating — drums only fire if zp_outro != 0
lda mu_step
and #$03
bne !drum_done+       ; only every 4th step = ~125 BPM beat
lda #DRUM_LEN
sta drum_state
lda #DRUM_FREQ_HI
sta drum_freq
!drum_done:
```

Per-frame tick (also inside `my_music_play`):

```kickass
lda drum_state
beq !drum_skip+
dec drum_state
lda drum_freq
sec / sbc #DRUM_SWEEP        ; pitch sweep down
cmp #DRUM_FLOOR
bcs !sweep_ok+
lda #DRUM_FLOOR              ; floor at sub-bass
!sweep_ok:
sta drum_freq
lda #$00 / sta $D40E         ; V3 freq lo
lda drum_freq / sta $D40F    ; V3 freq hi (sweeping)
lda #$81 / sta $D412         ; V3: noise + gate on
!drum_skip:
```

Current constants:

| Constant | Value | Effect |
|----------|-------|--------|
| `DRUM_LEN` | 10 frames (~200 ms) | Kick window length — long enough to "land" |
| `DRUM_FREQ_HI` | `$20` (~488 Hz) | Start pitch — mid-bass attack |
| `DRUM_SWEEP` | `$03` per frame | Sweep speed — fast 808-style dive |
| `DRUM_FLOOR` | `$03` (~46 Hz) | Sub-bass body floor |

No hard restart in this implementation — V3's envelope was set to
`AD=$00, SR=$F0` by intro's `my_music_init` (sustained-at-peak arp)
and the kick relies on that to be LOUD. The waveform switches from
pulse (arp) to noise (kick) without re-gating; envelope stays at
peak the whole time so noise plays at full volume.

After the kick window ends, music_play's next V3 ctrl write puts
the waveform back to pulse and the arp resumes audibly — envelope
never released, so no click.

### Coda's V3 kick — the clean version (no arp to fight)

Coda is the one part where we can do a **textbook hard-restart kick
with its own ADSR**, because coda overrides V3 every IRQ for its
entire duration. The arp is never allowed to sound, so we can pre-
load V3's ADSR with a true kick shape (`A=0, D=8, S=0, R=0`) once
in setup and let the envelope decay naturally between hits.

The state machine in `parts/coda/coda.asm`:

```
zp_kick_state == 0       : idle. Decrement zp_kick_count; when
                           it reaches 0, arm a new beat by writing
                           CTRL = $10 (triangle, gate OFF) — release
                           with R=0 → envelope to zero instantly.
zp_kick_state == KICK_LEN: body frame 0 — first audible tick. Set
                           fresh freq, write CTRL = $11 (triangle +
                           gate ON). Rising-edge gate triggers a
                           fresh attack from zero.
zp_kick_state in 1..N-1  : body frames. Sweep freq hi down (KICK_SWEEP
                           per frame, floor at KICK_FLOOR), keep
                           CTRL = $11. Envelope decays per AD.
```

Triangle wave + low frequency (`$D40F` swept from `$18` to `$03` over
12 frames) produces the 808-style sub-bass thump. No noise transient
because the title card is meant to feel *quiet*, not punchy.

This is a simplified take on lft's "stabiliseRC3" / "new hard-restart"
pattern — the full multi-frame dance is overkill for one slow kick at
60 BPM, and coda owns V3 so there's no envelope state to recover.

Coda's coexistence with intro's resident music engine:

1. `jsr INTRO_MUSIC_PLAY` runs first — engine writes V1 / V2 / V3
   for the chord step. V3 gets the arp pulse waveform + gate, but
   since coda overrides V3 on the very next instruction, the arp
   never reaches the speaker.
2. `jsr coda_kick` overwrites `$D40E` / `$D40F` / `$D412` with the
   kick state. Body frames write CTRL = `$11` (triangle + gate ON);
   idle frames leave whatever the engine last wrote, which is the
   arp's CTRL = `$41` — but the envelope from the previous kick has
   already released to zero (R=0), so nothing is audible until the
   next gate-on.
3. Intro's drum gate inside `my_music_play` stays closed because
   coda's setup zeros `$F6` (= `zp_outro` in intro's namespace).
   No noise transient from the resident drum code interferes.

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

We use this in interlude: pad-only first 24 beats (no drums, V1 muted),
build-up beats 24-31 (V1 returns + filter sweep, still no drums),
greets (drums + bass + full mix = climax), end (drum-free reprise).
