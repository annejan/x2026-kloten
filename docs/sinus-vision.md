# Sinus — vision archive

> **Shipped: Option D — the manifesto.** Implemented in commit
> `cff79d1` (rewrite) + `f1779de` (chargen fix) + `48b3330`
> (byte-order fix). See [`narrative-arc.md §4`](./narrative-arc.md)
> for the live description of what plays.
>
> 2026-05-22 — Originally written as an options doc before any code
> landed. Kept as an archive of the design space we considered and
> the rationale for picking what we picked. No further sinus
> implementation here — this is "what we thought about" / "what we
> went with".

## What shipped

Dual-phase text beat, ~5 seconds total at 50 Hz:

| Frames | Time | Text on rows 10-11 | Palette | Wobble |
|--------|------|--------------------|---------|--------|
| 0-119 | 0 → 2.4 s | `THEY SAID AI DESTROYS CREATIVITY` / `KILLING JOY AND NUMBING OUR MINDS` | red tones | full sine amplitude |
| 120 | swap | (1-frame white border flash) | — | — |
| 120-249 | 2.4 → 5.0 s | `WE FOUND THE OPPOSITE` / `NOT A THREAT BUT A TOOL` | cyan tones | half amplitude |

The rest of the screen (rows 0-9 and 12-24) wallpapers with
"deFEEST" repeating, dim-blue gradient. Audio continues its breath
job underneath (LP close on V1+V2, drums silent, vol fade over
last second). White border flash highlights the swap.

This is **Option D below** (manifesto / accusation → answer) which
the original doc didn't enumerate — added after the fact.

## Original options considered

> The doc below is what was on the table before implementation
> started. Kept verbatim for archaeological value.

---


## Where sinus sits in the arc

```
interlude  →  sinus  →  greets
SPARKED       ?????      KLOTEN-snap
(joke lands)  (breath)   (party + community + title)
```

It's a **bridge beat** — ~5 seconds of dead air between the
interlude's punchline and the greets climax. Every other part of
the demo is doing one specific narrative job (load / hello /
confession / party / trophy / bow). Sinus, right now, is the only
part with **no story job** — it's just the breath the audio needs
between exhale (SPARKED filter-open) and inhale (greets drums slam
back).

That's why it reads flat: the music is doing the right thing (LP
filter closing on bass+lead, drums silent, vol fade — the breather),
but the visual + text say nothing **specific to this moment**. A
field of repeating "DEFEEST" wobbling on a sine could be in any
demo from 1989 onward. It's the generic-est filler we ship.

## What's broken, exactly

1. **The text says nothing.** "DEFEEST" is the group name — the
   audience already saw it in screenfill bloom + intro cracktro.
   Repeating it a third time in a 5-second wobble is not story —
   it's logo wallpaper.
2. **The effect has no personality.** Sine-wobbled text on a
   background colour cycle is the cheapest "I have raster cycles
   left over" effect. It looks like a screensaver, not like a
   demo beat.
3. **It doesn't set up greets.** The audience exits sinus knowing
   exactly what they knew entering it. Sinus is a 5-second gap in
   the story, not a transition.
4. **The "breath" is musical but not visual.** Sound-arc nails the
   breather (drums stop, filter closes, vol fades) — but the screen
   doesn't *show* a breath. It shows wobbling words. The two arcs
   come unlocked here.

## What the bridge beat could DO

The job of sinus, narratively, is **the moment between getting
sparked and actually doing the thing**. SPARKED was the spark.
Greets is the party. Sinus is the **pivot** — the half-second
where Anus + Kloot look at each other and decide *yeah, let's
actually do this*. The lunchbox costume on that beat:

| Mood        | What it might say                 |
|-------------|-----------------------------------|
| Casual      | "ANYWAY…"                          |
| Determined  | "LET'S MAKE LUNCH"                 |
| Cooking     | "WARMING UP…" / "PREHEATING…"      |
| Direct      | "OPEN THE BREADBIN"                |
| Reflective  | "OK. NOW WHAT."                    |
| Anus-coded  | "HOLD MY SANDWICH"                 |
| Title tease | first letters of KLOTEN forming   |

The strongest candidates land both the narrative role (bridge from
spark to party) AND the costume (lunch / breadbin). Top three:

- **"LET'S MAKE LUNCH"** — completes the metaphor; SPARKED is the
  hob lighting, this is the decision to actually cook. Pairs
  naturally with greets-as-party (eating together).
- **"HOLD MY SANDWICH"** — Anus's voice, casual confidence. Reads
  funnier, looser. Slightly off-tone with greets' big-feels climax.
- **"WARMING UP…"** — literal hook into the disk-load happening
  in the background. Meta-honest about what sinus actually IS
  (load filler) without breaking the costume.

## What the EFFECT could be

Constraints:
- **~5 seconds of screen time**, half of which the loader is
  hammering disk → IRQ cycle budget is tight, no raster-heavy FX
- **Visual rhyme with "sinus"** — the word literally means "sine",
  so something that visibly *waves* / *breathes* / *pulses* fits
  the name. Don't fight the part name.
- **Show the breath.** A 5-second beat of silence should LOOK
  like a 5-second beat of silence. Calm, not busy.
- **Set up greets.** Greets opens loud, drums slamming, scroller
  flying right-to-left. Sinus should end on a *coiled-spring*
  feeling — calm, but pointed.

Three effect directions:

### Option A — One word, one breath, one sine
A single line of large text (sprite-font or hires) in the middle
of the screen, slowly expanding and contracting **with the
music's filter close**. The audio LP cutoff drops $70→$08 over
the part; the text width / brightness / Y-stretch could ride the
same curve. Audio breath = visual breath, exactly synced.

**Pros:** narratively focused, visually calm, locks the two arcs
back together, cheap on cycles (one row of FLD-stretched text).
**Cons:** "sine" only used as breath modulation — not exploring
the sine-effect heritage that the part name promises.

### Option B — Title-tease coalesce
The screen starts with the SPARKED-style chaos (sprite letters
scattered? noise field?) and over 5 seconds **slowly resolves into
the first word of the title** — `KLOTEN` — which then snaps to
position as greets begins with its own KLOTEN-snap landing. So
sinus is the *anticipation* of the trophy, made literal.

**Pros:** load-bearing in the narrative arc (telegraphs trophy),
visually striking (chaos → form), pairs perfectly with greets'
existing KLOTEN snap.
**Cons:** doubles down on KLOTEN as the focal word, which greets
ALSO settles on. Could read as repetition. Also: harder to do
cheaply — chaos-to-text dissolve isn't a free effect.

### Option C — Heartbeat sine + one-line caption
Visual is a **single horizontal sine wave** rendered as a hires or
char-bitmap line across the screen, breathing with the audio LP
close. Below or above it, **one short line of text** (e.g. "LET'S
MAKE LUNCH") fades in halfway through and holds. The sine is the
breath; the text is the resolve.

**Pros:** the sine becomes the literal effect of the part (name
honoured), the caption carries the narrative, breath visual locks
to audio. Two arcs back in lock.
**Cons:** asks for a hires sine-plotter (modest but non-trivial
code) AND a text reveal, doubles the build cost.

## Recommended direction

**Option C** has the highest payoff/effort ratio: the sine is
literally the visual breath synced to the audio filter close,
and a single short line of text carries the narrative pivot. The
sinus-as-breath promise lands musically AND visually AND
narratively in one beat. The two-arc lock that the rest of the
demo enforces gets restored here.

If we cut for time/complexity, fall back to **Option A** — drop the
sine plot, keep the breathing word. Still better than what's there.

## What this changes upstream / downstream

- **Sound-arc.md** doesn't need to change — current audio behaviour
  (LP close, drums silent, vol fade) is exactly what these visuals
  want under them.
- **Narrative-arc.md §4 "The breath"** would get rewritten — drop
  the "DEFEEST wobble" description, add the new beat.
- **Memory-layout.md** — sinus' VIC bank claims wouldn't shift for
  Option A; Option B/C might need a hires bitmap chunk (8KB) or
  one row's worth of char-bitmap RAM.
- **Greets handoff** — current `$F6 == $30` trigger doesn't care
  what sinus shows, so the trigger contract stays.

## Decisions needed from the user

1. **Which line lands** — "LET'S MAKE LUNCH" vs "HOLD MY SANDWICH"
   vs "WARMING UP…" vs something else?
2. **Which option** — A (one breathing word), B (chaos → KLOTEN),
   or C (sine plot + caption)?
3. **Tone** — calm/deliberate (lock to music breath), or playful
   (lunchbox costume foregrounded)?
4. **Budget** — am I building this from scratch (full sinus
   rewrite), or layering onto the existing DEFEEST-wobble shell?
