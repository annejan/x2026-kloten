# Music theory — outline-64 chord progression, voicing, and lead

## Key and mode

**A natural minor** (Aeolian mode), no accidentals. The progression
uses only the diatonic triads of A minor: Am, Em, F, G — i, v, VI, VII
in Roman-numeral terms. No harmonic/melodic alterations anywhere; the
entire demo sits in pure Aeolian.

The choice matters for the demo's narrative arc. Aeolian (relative to
C major) is the "sad" mode in Western harmony — the only common minor
mode with a flat seventh (♭VII = G, not G♯). The v chord (Em) instead
of V (E major) denies the leading-tone pull to tonic that would imply
a "resolution". The music never truly resolves; it cycles, like the
seven parts cycling through to the end credits.

## Chord progression

Four chords, 8 bars each at ~125 BPM (6 frames per chord step, 4 steps
per bar):

```
Am       | Em       | F        | G        |
(i)        (v)        (VI)       (♭VII)
```

One full cycle = 32 bars × 6 frames = 192 frames ≈ 3.84 s. The
progression loops throughout the demo (intro → interlude → sinus →
greets → coda, ~80 s total = ~21 full cycles).

### Chord voicings (arpeggio tones)

| Chord | Root | 3rd | 5th | Octave |
|-------|------|-----|-----|--------|
| Am    | A2   | C3  | E3  | A3     |
| F     | F2   | A2  | C3  | F3     |
| G     | G2   | B2  | D3  | G3     |
| Em    | E2   | G2  | B2  | E3     |

V3 cycles through these four tones frame-by-frame: root → 3rd → 5th →
octave, repeating at 50 Hz (= 80 ms per full arp cycle). The ear hears
a sustained chord with a subtle upward-pickup shimmer — classic C64
SID arp technique (Martin Galway, Jeroen Tel).

The arp notes span two octaves (E2–A3, roughly 82–220 Hz), sitting in
the low-mid register. This leaves sonic space for the lead (V2, mostly
octave 3-4) and keeps the bass (V1, octave 2-3) distinct.

## Tempo and step structure

| Unit | Frames | Time | Note value |
|------|--------|------|------------|
| PAL frame | 1 | 20 ms | — |
| Chord step | 6 | 120 ms | 16th note triplet feel |
| Bar (4 steps) | 24 | 480 ms | quarter note ≈ 125 BPM |
| Chord (8 bars) | 48 | 960 ms | two 4/4 bars |
| Cycle (4 chords) | 192 | 3.84 s | — |

`STEP_FRAMES = 6` means V1/V2/V3 note writes happen at chord-step
boundaries (= 8.33 Hz, roughly every 16th note in 4/4). Between steps
all voices hold whatever frequency + gate state they were last written
to. The arp (V3) is the exception: its control register keeps gate ON
continuously, so the envelope sustains at peak while the pitch register
(`$D40E`/`$D40F`) is overwritten every single frame to cycle through
the four arp tones.

## Voice architecture

### V1 — Bass (pulse wave, 12.5% duty)

ADSR: A=0, D=4, S=6, R=1 (fast attack, moderate decay, medium sustain,
short release). The 12.5% duty gives a thin, reedy timbre — cuts
through the mix without masking the lead or arp.

Bass pattern (8 steps per chord):

```
Am: A2 A2 A3 A2  A2 E3 A3 A2
Em: E2 E2 E3 E2  E2 B2 E3 E2
F:  F2 F2 F3 F2  F2 C3 F3 F2
G:  G2 G2 G3 G2  G2 D3 G3 G2
```

The pattern is identical across all four chords transposed to the root.
The 7th step in each 8-step bar jumps up an octave (root → root+12),
creating a syncopated lift on the "and" of beat 3. The 6th step also
jumps to the 5th degree of the chord (e.g. A2 → E3 in Am) — a
dominant-pedal bounce that adds rhythmic interest without leaving the
tonic harmony.

**Octave register:** A2–E3 (110–165 Hz). This is the classic "bass
guitar" range on C64 — low enough to feel like a root, high enough to
be audible on small speakers.

### V2 — Lead (pulse wave, ~37% duty)

ADSR: A=0, D=2, S=8, R=1 (faster decay than bass, higher sustain).
The wider pulse (37% duty vs bass's 12.5%) gives a fuller, richer
harmonic spectrum — the lead sits "on top" of the mix.

Melody spans 128 steps (4 chord cycles = ~15.36 s before repeating).
Each phrase is tied to a specific emotional arc:

#### Phrase 1 — Sparse opening (*"intro's first 15 s"*)
Character: tentative, lots of space. Rests every other step.

```
Am:  A3  –  E3  –  A3  C4  E3  –
Em:  G3  –  B3  –  E4  G3  E3  –
F:   F3  –  A3  –  F4  A3  C4  –
G:   G3  –  B3  –  D4  G4  F4  E4
```

The G chord's final four notes (D4 → G4 → F4 → E4) are the first
truly melodic gesture — a descending stepwise line that resolves to E4
(the 3rd of C major / 5th of Am) as the loop rolls back to Am. This
is the hook.

#### Phrase 2 — Active 8ths (*"intro's second 15 s, energy rising"*)
Character: eighth-note motion, no rests, rising tessitura.

```
Am:  A4  C4  E4  A4  C4  E4  C4  A3
Em:  B3  D4  G3  B3  E4  G3  E3  B3
F:   C4  A3  F3  A3  F4  C4  A3  F3
G:   D4  B3  G3  B3  G4  D4  B3  G3
```

Each chord's line arpeggiates up and down. The F chord has a notable
drop into the lower octave (F4 → C4 → A3 → F3) — the emotional low
point of the phrase. The G chord climbs back up and ends on G3, the
root.

Notable intervals: major 6th (A4→C4), minor 7th (A4→E4, E4→C4),
octave leaps (A4→A3). The wide intervallic leaps give the phrase an
"electric" quality.

#### Phrase 3 — High climb (*"intro's third 15 s, climax build"*)
Character: sustained high notes, arpeggiated figurations, rests
return on the last two chords.

```
Am:  E4  A4  E4  C4  A4  E4  A4  E4
Em:  B3  E4  G4  B4  E4  B3  E4  G4
F:   C4  F4  A4  –   F4  C4  A3  F3
G:   G4  B4  D4  –   B4  G4  D4  B3
```

The Am bar is almost entirely within the A4–C4 range (A above middle
C). The Em bar climbs to B4 (the highest note in the entire melody),
then steps down. The F bar introduces rests again, like the melody is
running out of breath. The G bar mirrors the upward leap to B4 seen in
Em.

This phrase reaches the emotional apex of the melody: B4 over Em is
the ♭6 scale degree, and hearing it ring out against E minor's G (♮3)
is the "sweetest" harmonic moment in the tune.

#### Phrase 4 — Descending resolution (*"intro's fourth 15 s, winding down"*)
Character: sparse, descending, mostly rests. The melody gives up.

```
Am:  E4  –  C4  –  A3  –  –  –
Em:  E4  –  B3  –  G3  –  –  –
F:   F3  –  C4  –  F3  –  –  –
G:   G3  –  D4  –  G3  –  –  –
```

Each chord plays two notes (the 3rd and root, or root and 5th) then
falls silent. The rests dominate — three full beats of silence before
the next chord. By the end of the G bar, the lead has retreated to G3
(lowest note in the lead range), ready for phrase 1 to restart.

### V3 — Arpeggio (pulse OR triangle, gated by intro's `T_SCROLLER`)

ADSR: A=0, D=0, S=F, R=0 (instant full volume, sustain pinned at peak,
no release). Because the gate stays ON continuously, V3's envelope
never drops — the voice is effectively a gate-less oscillator whose
pitch changes on every frame.

The arp cycles root → 3rd → 5th → octave at 50 Hz. Perceptual result:
a shimmering chord pad with an upward-pitch "shimmer" that blurs the
harmonic boundaries.

#### V3 timbre is controlled by `zp_intro` (subtle but important)

`my_music_play` re-writes V3's control register to **pulse + gate**
(`$41`) every frame ONLY if `zp_intro >= T_SCROLLER` (240). When that
re-write is skipped, V3's control register holds whatever the last
write left it at — which is **always `$11` (triangle + gate)** because
the drum_tick block writes the final drum body row to V3 every kick
and snare hit. The result:

| `zp_intro` value | V3 timbre during arp | Where you hear it |
|-------------------|---------------------|---------------------|
| `>= 240` (T_SCROLLER) | **Pulse 25%** — clean, harmonically rich, "organ" | Intro (`zp_intro` saturates at `$FF`) |
| `< 240` but `>= 120` (T_BARS) | **Triangle** — mellow, hollow flute-like | Greets, coda |
| `< 120` (T_BARS) | Same as above PLUS V1 bass freq writes skip | Side effect of low `$F8` |
| `< 40` (T_BALLS) | Above PLUS V2 lead freq writes skip → stuck note | What coda accidentally had before 2026-05-21 |

The triangle/pulse swap is the single biggest timbre control in the
demo. Greets sounds "flowing and musical" largely because V3 plays as
mellow triangle (`zp_intro` ≈ `$89` from interlude's `zp_plasma_tgl`
residue). Coda sets `zp_intro = $80` to inherit that triangle arp
while still letting V1 bass + V2 lead walk through their patterns.

See [`docs/sound-arc.md`](./sound-arc.md) for the full filter +
routing trace; see [`docs/sid-drums.md`](./sid-drums.md) for the
drum_tick code that leaves V3 as triangle.

### Drum voice — V3 timesharing + V1 bass-bleed layer

The resident drum code in `my_music_play` steals V3 from the arp on
beat frames (every 4th chord step = every 24 frames = ~125 BPM) AND
takes a 1-frame override on V1 to layer a sub-bass thump.

**The kit is K-S-K-S** alternating on the quarter-note grid since
the 2026-05-20 rework — kick on even quarters, snare on odd. See
[`docs/sid-drums.md`](./sid-drums.md) for the full table + state.

**Gate-latency fact:** The SID 6581 does NOT respond to a gate-on if
gate was already high. The waveform simply switches without resetting
the envelope. V3 keeps its arp-set $00/$F0 envelope (sustain pinned
at peak) through every drum frame — the kick is LOUD without any
ADSR change because the envelope was already maxed out.

**V1 bass-bleed.** At each drum trigger, V1 gets a fresh gate-pulse
($40→$41) to N_C1 (~33 Hz sub-bass). V1's existing punchy
$04/$61 ADSR (instant attack, fast decay, sustain $6, fast release)
shapes the thump naturally. The bass-pattern note at that step is
sacrificed (3 of every 4 bass notes survive, kicks land on the
quarter). This is where the kick's actual low-end weight comes from
— V3 alone can only paint the high-frequency click + harmonic body.
Pattern from the codebase64 Macro Player (Geir Tjelta / Jeroen Tel).

After each drum window (4 frames ≈ 80 ms), `my_music_play`'s next
chord-step write puts V3 back to pulse waveform at the next arp pitch
with gate held on → no envelope retrigger, no audible seam.

**Coda — full K-S-K-S kit + bass-bleed.** Coda enables drums via
`$F6 = $01` in setup so intro's resident kit fires throughout the
held title. The earlier dedicated V3 kick state machine (a hard-restart
pitch-slam at ~60 BPM) was pulled in favour of the K-S-K-S kit because
the kit's kick IS a V3 triangle pitch-slam and the V1 bass-bleed IS
the sub body — separate machines were redundant.

Coda also sets `$F8 = $80` (not `$FF`) so the V3 arp stays as triangle
between drum hits (see the "V3 timbre" table above). The combined mix
under the held title:
- **V1**: walking bass_pattern + N_C1 sub-thump on every drum
- **V2**: lead_pattern through LP filter (inherited V2-routed `$D417=$42` from greets)
- **V3**: triangle arp between drums, triangle pitch-slam kick / low-noise + triangle snare during hits
- **Filter**: cutoff frozen at greets' last value (no wobble modulation)

## Filter / volume arc across parts

```
intro:     vol=$0F (max), no filter routing
interlude: vol=$1F (LP mode), V1+V2 filtered ($D417=$23, res $2),
           cutoff $40→$FF during the buildup (last ~2.4 s)
sinus:     vol=$1F (LP mode), V1+V2 filtered ($D417=$23, res $2),
           cutoff $70→$08 over duration, vol fades $0F→$00 over last 50 frames
greets:    vol=$1F (LP mode), V2 filtered ($D417=$42, res $4),
           cutoff modulated by `zp_wobble_pos | $40` for slow "wah"
coda:      vol=$1F, LP mode on, $D417=$42 inherited (V2 still filtered),
           cutoff FROZEN at greets' last value (no wobble in coda)
end:       vol ramps $00→$0F over 2 s, V1+V2+V3 all filtered ($D417=$07),
           cutoff baseline $60 with mood-LFO breathing clean↔dark
```

The filter arc is the long-form emotional contour: dry (intro) →
opens up with bass + lead (interlude build) → closes both (sinus
breakdown) → wah on the lead (greets climax) → **frozen lead-wah +
full drums + walking bass under the title (coda — the triumphant
trophy)** → all-voice LP reprise with slow PWM and mood breath
(end — back into the minor flow). Coda is the loudest moment by
design; end is the closing breath.

**Target SID chip: 8580** — picked over 6581 because the 8580's
digital filter has no per-unit cutoff drift, so the cutoff values
listed above land identically on every C64. The 6581's analog
filter character is unit-dependent; cutoff $40 on one 6581 sounds
like $30 on another. Sidechain + LP-wah + dark-phaser tricks
need that reproducibility to read the same to every audience.
Declared in the submission NFO via `tools/bundle_submission.sh`.

**Critical pitfall: $D417 voice routing.** `$D418` bit 4 sets LP
mode, BUT the filter only affects voices whose bit is set in
`$D417` (bits 0-2 = V1/V2/V3 routed through filter). Sinus shipped
for weeks with the cutoff sweep doing nothing because `$D417 = $10`
routed no voices. Always set BOTH the mode bit in `$D418` AND the
voice-routing bits in `$D417` when adding filter work to a part.

## Why this progression works for a 2-minute demo

1. **Aeolian never resolves.** The v→VI→♭VII→i loop has no perfect
   authentic cadence. This suits a demo whose narrative arc is "open"
   — it ends with credits and a "see you at Evoke," not a button.

2. **Static harmony, dynamic arrangement.** The chord progression never
   changes for ~130 seconds. All musical interest comes from:
   - Lead melody cycling through 4 different phrases (15-s phrases × 4)
   - Drum entrance/exit gating (intro's `zp_outro`)
   - Per-voice muting (interlude kills V1 for the first 24 beats)
   - V3 timbre flips pulse↔triangle via the `T_SCROLLER` gate on `zp_intro`
   - Filter routing changes (intro=off, interlude/sinus=V1+V2, greets=V2)
   - Filter cutoff sweeping (interlude up, sinus close, greets wah)
   - Volume fade (sinus's final 50 frames)
   - Coda inherits greets' V2-routed filter with a frozen cutoff

3. **125 BPM is the demoscene sweet spot.** Fast enough for a driving
   8th-note feel, slow enough that 24-frame beats don't feel rushed.
   The step rate (6 frames) puts V1/V2 writes at ~8 Hz = comfortably
   within the ear's rhythmic grouping (< 10 Hz).

4. **Three-voice tradeoffs are deliberate.** The arp (V3) is sacrificed
   for drums during beat frames. The bass (V1) uses a thin pulse to
   not mask the lead (V2). The lead stays in the upper octave range
   (C4–B4) to avoid clashing with the arp's chord tones (E2–A3).
   There's no "extra voice for pads" — the arp IS the pad.
