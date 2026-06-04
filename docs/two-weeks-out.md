# Two weeks out from X2026 — stocktake + focus plan

*Captured 2026-05-21 by Kloot (Claude) and refreshed 2026-05-22 after
the koala backdrop / scroll-driven greets / callmusic-during-load-gap
sweep. Snapshot, not a contract — update when the situation shifts.*

> **Superseded (2026-06-04).** This is a dated planning snapshot. The
> part/duration figures below are stale — `hush` was merged into
> interlude, the coda is now ~16 s (was ~30 s), and the coda gained a
> demoscene char layer. For the current timeline see
> [`docs/timing.md`](./timing.md) and [`AGENTS.md`](../AGENTS.md).

## Where we are

All seven parts play end-to-end, ~2:55 of runtime. Demo cycle:

```
screenfill → intro (logo + K-S-K-S kit, ~57 s)
           → interlude (V3-muted music-box pad + typewriter,
                         then SPARKED drop with V1 + drums + filter
                         sweep slamming in, ~4 s pad + ~4 s buildup)
           → hush (~4 s comedown)
           → greets (~50 s scroll-driven, smooth-pixel DYCP scroller
                      over a multi-colour koala backdrop, KLOTEN
                      landing as the punchline)
           → coda (~30 s parallax stars + zoom-breath twin stars +
                    triumphant full K-S-K-S kit)
           → end (dark-phaser credit roll, loops)
```

Music stays continuous through every part-to-part blank-filler load
gap via Spindle's `'M'` install + `bit $0000` callmusic placeholders
(see `docs/sound-arc.md` "Music continuity through load gaps").

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
- **Greets is now substantial.** Smooth-pixel scroll over a
  user-painted multi-colour koala backdrop (peephole portal +
  gradient title text). Scroll-driven settle on " KLOTEN " so the
  part length tracks message length — add/remove names without
  touching timing constants. ~50 s.

## What's still raw

| Item | Why it matters | Effort |
|---|---|---|
| **Real-hardware verification — NEVER DONE** | Two weeks out. VICE is generous; real PAL C64 can break on IRQ timing, $D012 race conditions, DMA stretching. If something fails on metal, we need debug time. | 30 min to test, then ?? to fix |
| **Hush** | Reworked as the breath (`9d9f851`) — repeating DEFEEST field, woven grid + colour banding, LP fade. | ✅ done |
| **End-credits dark-phaser modulation** | Slow LFO modulates filter cutoff clean↔dark (`4d37d23`, `ba22f08`). ~20.5 s cycle, never starts dark. | ✅ done |
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

Both done. Focus on HW test and submission prep.

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
