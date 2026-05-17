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
