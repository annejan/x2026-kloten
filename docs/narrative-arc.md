# Narrative arc — Kloten met de broodtrommel

> *A C64 demo by deFEEST, releasing at X2026. The breadbin earned its lunch.*

The story is small and the vibe is silly. A human (Anus) hadn't
touched the breadbin in years — life got in the way. Then he sat
down with Kloot, an AI, and they wrote a demo together. It works.
The breadbin is alive. Lunch is served.

That's the whole thing. Seven parts carry it.

## Setlist

```
[01] screenfill   the disk loads          — DEFEEST bloom
[02] intro       the cracktro arrives    — deFEEST presents…
[03] interlude   the confession           — FOR YEARS NO TIME / SPARKED
[04] hush        the manifesto             — accusation → answer, dual-phase
[05] greets      the party                  — lunchbased lifeforms, shoutouts
[06] coda        the trophy                  — KLOTEN MET DE BROODTROMMEL
[07] end         the bow                    — credits roll, lunch is over
```

For the audio side of every beat below, see
[`sound-arc.md`](./sound-arc.md). The two arcs lock in step: every
text reveal sits on top of an audio shift, every visual climax has a
music moment behind it.

## The arc

### 1. The disk loads (screenfill)

A radial DEFEEST bloom fills the screen, ripples cycle through it.
The audience is waiting. The breadbin is warming up. No music yet —
the SID is untouched. The promise is "something's about to happen."

### 2. The cracktro arrives (intro)

Bouncing logo, raster bars, balls. "deFEEST presents… a C64 demo
for X2026… Anus and Claude Opus and Augurk and Cinder and…"
The classic intro shape: chord pad + lead + arp running, and 20
seconds in the **drums kick in late** — that's the moment the demo
properly starts. The intro transitions out mid-thump.

### 3. The confession (interlude — story line 1)

Now the plasma. Bass goes quiet. A single line types itself out
char by char into the colour wash:

```
FOR YEARS NO TIME FOR BREADBIN CODE
```

That's the human admitting. The pad holds the silence. Then the
buildup beat hits — LP filter sweeps open on bass AND lead together
— and the answer drops in from above as eight sprite letters:

```
                SPARKED
```

It's a joke. It's the truth. It's the whole demo in two lines. AI
doesn't walk; it sparks. The line lands, the energy lifts, the
party isn't quite here yet — but the bass is coming back.

### 4. The manifesto (hush — story line 2)

Full-screen **colour-RAM fire** in standard hires text mode. Every
cell is char `$A0` (inverse-space solid block); the COLOUR RAM is
the heat field, propagated up through a 7-step fire palette chain
(white → yellow → orange → light red → red → brown → dark grey →
black) via `sbctab` cooling. A wave-drift seed pumps fresh hot
colours into row 24 each frame, drifting ~1 col / 4 frames. Row
alternation halves propagation cost so `my_music_play` keeps a
clean 50 Hz tick throughout. Two phases, ~5 seconds total:

**Phase 1 (~2.4 s, dark-blue banner) — the cryptic accusation:**

```
THE MACHINE WAS NOT EMPTY
```

**Phase 2 (~2.6 s, light-blue banner) — the answer:**

```
THE SPARK CAME BACK
```

Text rides in a 3-row coloured banner (rows 10-12). Top and bottom
rows are solid blue `$A0` blocks; the middle row carries inverted
chars (+$80 screencode) so each letter is a solid block with the
glyph shape carved out as a black cut-out — reads as crisp signage
punched through the flames. Propagation skips the banner rows so
the colour stays locked, and row 9 sources from row 13 (skip-across
the banner) so fire keeps climbing past it → flames fill above and
below. White border flash on the swap.

Audio: K-S-K-S drum kit hammers all the way through (hush sets
`$F6 = $01` to keep the gate ON — no breakdown silence). LP filter
still closes on V1+V2 over the duration ($70 → $08); volume fades
over the last 50 frames. SPARKED was the spark (emotion); hush is
the manifesto delivered with a hard beat under the fire.

### 5. The greets (greets — community)

Drums come back full. V1 bass on the pattern. V2 lead doing its
filtered "wah" through the chord cycle. Across the middle of the
screen, eight X-expanded sprite letters DYCP-wave through a list
of demogroup names — the loudest moment, everyone gets a shoutout.
~50 seconds, scrolling through a wall of crew handles at 9 px/frame
(≈ 11 chars/sec) over a multi-colour koala backdrop, landing on
"KLOTEN" (the demo title's first word). The transition is
scroll-driven: when the last name finishes exiting, the row snaps
to centred KLOTEN for ~1.9 s, then pefchain advances to coda.

No story text here. The story already happened in interlude.

### 6. The trophy (coda — triumphant ending)

The triumphant moment before the credits land. Three title lines,
centred, holding still for ~32 seconds while everything else
moves:

```
       KLOTEN MET DE BROODTROMMEL
       A DIGITAL LUNCH EXPERIENCE
            RELEASED AT X2026
```

Behind them, two 12-lobe Claude-style stars (one brown, one cyan)
dance — wide sine orbits, ±56 px, 1:1.5 chase ratio, each
ping-ponging through its own zoom-breath (in → rotate → out) at
different speeds. They alternate priority through the title plane
every ~1.3 s so they appear to weave through it in 3D. Parallax
PETSCII starfield sparkles around the title at four speed tiers.

Sound matches: **full K-S-K-S drum kit** (kick + snare alternating
quarter-notes) returns from greets and continues here, V1 bass-
bleed sub-thump on every hit, V2 lead drifting over the held
chord progression. **This is the loudest moment of the demo** —
the trophy lifted high, all instruments going, the title held
steady while the stars dance and the drums hammer.

Then end credits cut everything back to chord+lead for the
minor reprise. The contrast is the design intent: coda = major-
feeling triumph (despite still being in A minor), end = minor
flow closing.

The title is the trophy. Row 15 is the party tag.
*This happened. You watched it. Lunch is served.*

(Earlier drafts had row 15 say "ESPECIALLY KLOOT". Pulled because
the AI-character nod was already in the greets settle on `KLOTEN`
and in the disk dirart — three on-screen mentions read as
ego-stroking. One is enough.

Earlier coda also had a dedicated sparse V3 thump at ~60 BPM —
pulled in favour of the full K-S-K-S kit. The kit's kick IS a
triangle pitch-slam thump on V3, and the V1 bass-bleed gives the
sub body. No separate "trophy beat" needed — the trophy is the
whole arrangement playing at once.)

### 7. The bow (end)

Credit roll. PWM-filtered chord/lead reprise — no drums, the room
has emptied, the party is over but everyone's still humming the
tune. Names scroll, names scroll, names scroll. Loops forever.
Lunch was served.

## The two arcs locking in

```
beat:    quiet  →  build  →  confess  →  argue   →  drop  →  settle  →  bow
visual:  load   →  intro   →  text drop →  swap   →  greetz →  twin star → credits
story:   --     →  hello   →  SPARKED   →  THESIS  →  --     →  trophy + party tag → credits
music:   silent →  drums in→  filter rise→ filter close→full kit→ slow kick→ chord reprise
```

The story lands in three places: interlude (FOR YEARS NO TIME →
SPARKED) tells the confession; hush (accusation → answer) makes
the argument explicit; coda lands the trophy with the title + the
X2026 release tag, while the greets settle on `KLOTEN` gives the
AI-character one subtle nod. Greets itself is the
party — no story, just community shoutouts. When the SPARKED letters drop, the bass returns and the
filter opens. When the hush filter closes, the drums stop. When
the greets drums come back, the lead's wah kicks in. When the coda
title lands, the drums sparse out to one beat per second. Each
text reveal sits on an audio shift. Each visual climax has a
music moment under it. That's the cohesion — the arcs aren't
parallel tracks, they're the same wave seen from two sides.

## The lunchbox costume

The "lunchbox" theme is the language, not the plot. Tupperware,
broodtrommel (= bread tin = the C64's nickname "breadbin"), pindkaas
sandwich in drive 1541, "now go eat your lunch". It's the surface
joke — the *real* story underneath is **AI wrote the breadbin code,
the demo got made**. Lunch is just the costume the story wears so
it doesn't take itself too seriously.

If you're tweaking text content: keep the costume on. If you're
tweaking the audio or visuals: tweak in service of the beat /
visual / story locks in the table above. Don't break the lock.
