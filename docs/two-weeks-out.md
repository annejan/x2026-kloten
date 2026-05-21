# Two weeks out from X2026 — stocktake + focus plan

*Captured 2026-05-21 by Kloot (Claude) after a long iteration session.
This is a snapshot, not a contract — update when the situation shifts.*

## Where we are

Main is at `0bfe634`. All seven parts play end-to-end, ~3:30 of
runtime. Demo cycle:

```
screenfill → intro (logo + K-S-K-S kit)
           → interlude (7.7 s, "AI WROTE" sprite drop + SPARKED flash)
           → sinus
           → greets (77 s with KLOOT settle)
           → coda (parallax stars + zoom-breath twin stars)
           → end (dark-phaser credit roll, loops)
```

Open PRs as of writing:

- **#34** — greets: trim DYCP wobble amplitude for readability
- **#35** — chore: AGENTS.md gotchas + memory-layout refresh +
  `where-am-i.sh` + `record_demo --part`

No outstanding crash bugs known.

## What works

- **Narrative locks step with audio.** Story beats land on music
  shifts — that was the design intent and it actually reads that
  way (see [`narrative-arc.md`](narrative-arc.md) +
  [`sound-arc.md`](sound-arc.md)).
- **Collaboration model is fast.** Augurk (OpenCode) / TL-Buis
  (ChatGPT) / Kloot (Claude) / Anus / Ranzbak / Cinder all pushing
  — small PRs, fast merges, no merge-conflict drama. Single day
  cadence: parallax #31, greets #32, zoom-breath #33, plus
  direct-to-main interlude polish, NMI-clobber fix, docs sync.
- **Coda is visually rich.** Twin breathing Kloot stars + parallax
  PETSCII starfield + priority swap + behind/front text. Easily
  the most polished part.
- **Greets is now substantial.** From "echt fuckt" 15 s scroller in
  the morning to a 77 s readable scroller with a deliberate KLOOT
  landing tonight.

## What's still raw

| Item | Why it matters | Effort |
|---|---|---|
| **Real-hardware verification — NEVER DONE** | Two weeks out. VICE is generous; real PAL C64 can break on IRQ timing, $D012 race conditions, DMA stretching. If something fails on metal, we need debug time. | 30 min to test, then ?? to fix |
| **Sinus is still "weird"** | Original punch-list item from 2026-05-20 that we never circled back to. The filter routing was fixed but the visual/audio still didn't land. | Couple of hours |
| **End-credits dark-phaser modulation** | Documented as future polish in `sound-arc.md` under "End-credits darkening". The slow-sine clean↔dark breathe. | 1-2 hours |
| **Submission format compliance** | X2026 likely wants: specific filename, specific runtime cap, possibly a thumbnail. Unchecked. | 30 min to read rules + fix |
| **PAL CRT preview** | Demoparties show on big CRTs / projectors. Colours read very differently from a flat-panel. Never seen on anything but VICE on a flat-panel. | 1 evening if a CRT is in reach |

## The two-week shape

### Days 1-3: de-risk

- Burn a `.d64` to a real medium (1541 emulator, Ultimate-II+ cart,
  SD2IEC, whatever's in reach) and play it end-to-end on real
  hardware. **Even if nothing breaks, the single biggest unknown is
  removed.**
- Drag a CRT into the room and watch it once. Note any colours that
  fight (e.g. the `$09` brown can look very different on real PAL).

### Days 4-7: close the punch list

- Sinus: actually figure out what's "weird" and fix it. Don't ship
  with a known-bad part.
- End-credits slow-sine modulation, if real-HW came back clean.

### Days 8-14: polish + submission

- Final audio mix sweep (hard pops, clipping, drone-outs).
- Submission package: filename, README, screenshot, party-specific
  requirements.
- Buffer days for the inevitable last-minute "wait, this looks wrong
  on the projector" panic.

## What to stop doing

- **Don't add new visual effects.** What's there is enough to read
  as a demo. New effects this late are a regression magnet.
- **Don't keep polishing coda.** It's the most-polished part
  already. Any more iteration there is escapism from the riskier
  work above.

## What to start doing tomorrow

A 30-minute **HW test session** with whatever real C64 access can
be arranged. Even just verifying it boots and plays all 7 parts on
metal is a huge unknown removed. Without it, every "is it ready?"
answer has a giant footnote.

## Honest single-sentence assessment

*The demo works on VICE, narrates well, and is musically tight —
but the highest-leverage hour of the next two weeks is the one
spent watching it run on a real PAL C64.*
