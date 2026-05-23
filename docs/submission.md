# Submission plan — X 2026

Audit item #10 from issue #38: produce a `tools/bundle_submission.sh`
that mechanically generates everything the party + post-party release
need.

## What X2026 actually requires

Per [xparty.net/compos](https://xparty.net/compos):

| Requirement | Our status |
|---|---|
| `.d64` image (or `.prg` for Onefile award) | `.d64` — we're multi-part, Onefile doesn't fit |
| Stock C64 + 1541-compatible drive | ✅ runs on 1541-Ultimate (the compo hardware) |
| 6581 *or* 8580 SID preference declared | **8580** — more reproducible (digital filter, no per-unit cutoff drift), and the cleaner character is what lets the sidechain + LP-wah + dark-phaser tricks land consistently on every C64 |
| No BASIC entries | ✅ pure 6502 + Spindle, no BASIC stub |
| No remote entries — physical submission via `votox` | submitted on-site by a human |
| Pro tip: tell them the demo's duration in the private comment field | one-pass runtime ~3 min |

Everything else (screenshots, NFO, source) is voluntary — done for
the post-party CSDb release and as a courtesy to the compo crew.

## What the script will produce

```
submission/
├── defeest-kloten_met_de_broodtrommel.d64                ← upload to votox
└── defeest-kloten_met_de_broodtrommel-x2026.zip          ← release bundle
    └── defeest-kloten_met_de_broodtrommel/
        ├── defeest-kloten_met_de_broodtrommel.d64
        ├── defeest-kloten_met_de_broodtrommel.nfo
        ├── README.txt
        ├── screenshots/
        │   ├── 01-screenfill.png
        │   ├── 02-intro.png
        │   ├── 03-interlude.png
        │   ├── 04-hush.png
        │   ├── 05-greets.png
        │   ├── 06-coda.png
        │   └── 07-end.png
        └── sources/
            ├── source.zip          ← `git archive HEAD` snapshot
            └── how-it-was-made.md  ← assembled from docs/ + git log
```

## Filename convention

X-Party doesn't mandate one. Going with the CSDb / scene-typical
shape: `<group>-<demo_short>` for the artefacts, `<group>-<demo_short>-<party>` for the release archive.

- `defeest-kloten_met_de_broodtrommel.d64` — short snake-case
- `.zip` adds `-x2026` so the same generation script can produce
  variants for other parties later (Evoke, Outline, …)

## NFO content

Plain ASCII (79-col wide), no PETSCII characters in case the
reading tool isn't C64-aware. Sections:

- Title + group + party banner
- System requirements (`stock C64 + 1541`, `PAL`, **`8580 preferred`**)
- One-pass duration (`~3:00` before credits loop)
- Build SHA + date for traceability
- Credits (Anus / Kloot / Augurk / TL-Buis / Ranzbak / Cinder), tools
- One-paragraph story (the AI-pair-programmer arc)
- GitHub source URL + commit SHA

## Screenshots — timing source of truth

Timestamps from `docs/timing.md` (currently):

| # | File | Part | Boot offset | Why this moment |
|---|---|---|---|---|
| 01 | `01-screenfill.png` | screenfill | 3 s | radial bloom mid-reveal |
| 02 | `02-intro.png` | intro | 10 s | bars + balls + logo bouncing |
| 03 | `03-interlude.png` | interlude | 83 s | SPARKED letters landing |
| 04 | `04-hush.png` | hush | 88 s | DEFEEST sine wobble live |
| 05 | `05-greets.png` | greets | 120 s | mid-scroll, several groups visible |
| 06 | `06-coda.png` | coda | 175 s | KLOTEN MET DE BROODTROMMEL title + twin stars |
| 07 | `07-end.png` | end | 200 s | credit roll mid-scroll |

If part durations move, the timing offsets need re-syncing. The
script will fail loudly if a screenshot lands in the wrong part
(checked by polling `$F6` after each capture).

## "How it was made" — content

A single Markdown file `how-it-was-made.md` distilled from:

- `docs/narrative-arc.md` (story side)
- `docs/sound-arc.md` (audio side)
- `docs/two-weeks-out.md` (the sprint stocktake)
- top-level `README.md` "How this was built" section

… edited down to ~1 page. The pitch:

> A human who hadn't touched the breadbin in years sat down with
> Claude (Anthropic Opus 4.7), OpenCode, and ChatGPT for three
> weeks. The demo's narrative is the demo's own making.

This is also genuinely interesting to the scene — AI-pair-programmed
C64 demo work is novel in 2026.

## Implementation plan

Three files:

1. `tools/bundle_submission.sh` — top-level orchestrator. Cleans
   `submission/`, runs `build.sh`, calls steps 2 and 3, then zips.
2. `tools/capture_part_screenshots.sh` — boots VICE-MCP, polls
   `$F6` to verify part transitions, calls
   `vice.display.screenshot` at the right moments.
3. `tools/nfo_template.txt` — the NFO source with `{{TITLE}}`,
   `{{SHA}}`, `{{DURATION}}` placeholders.

Source snapshot via `git archive HEAD` — clean, reproducible,
exactly what's at the commit named in the NFO.

## Status — implemented (2026-05-21)

All three scripts + the NFO template + the long-form "how it was
made" doc landed in `tools/`. Run via:

```bash
./tools/bundle_submission.sh
```

…produces both `submission/defeest-kloten_met_de_broodtrommel.d64`
(upload via votox) and `submission/defeest-kloten_met_de_broodtrommel-x2026.zip`
(release archive). Takes ~3.5 min wall-clock because the
screenshot pass plays the demo through to each part in real time.

### Dry-run findings (2026-05-21, commit `0960a83`)

End-to-end ran successfully — `.d64`, `.zip`, source archive, NFO,
README, how-it-was-made and all 7 screenshots produced in the
right shape. **But the screenshot timestamps are wrong** for 5 of
7 frames. Captures vs reality:

| File | Expected | Actual capture |
|---|---|---|
| 01-screenfill | DEFEEST bloom | black — VICE still booting at t=3 |
| 02-intro      | mid-intro     | **correct** (logo + bars + balls) |
| 03-interlude  | SPARKED landing | plasma chars (right part, wrong moment) |
| 04-hush      | DEFEEST wobble | greets "SILICON" — past hush |
| 05-greets     | mid-scroll    | greets "KOLOR" — right part, fine |
| 06-coda       | KLOTEN title  | black — between coda and end |
| 07-end        | credit roll   | **correct** (Kloot/Augurk/TL-Buis credits) |

Two compounding causes:

1. **`boot_ms` is anchored too early.** `capture_part_screenshots.sh`
   reads `date +%s%N` *before* `./run-mcp.sh` returns, then adds
   a flat `+4000` ms. Reality: VICE x64sc + autostart take ~5-7 s
   from invocation to "demo actually plays first frame." Result:
   the t=0 reference is ~3-5 s ahead of demo start, which
   propagates to every snapshot.
2. **`docs/timing.md` is now slightly stale.** After `736a2f9`
   (shorter intro), `8ed0777` (longer interlude), and `9d9f851`
   (hush rework), the per-part offsets in
   `tools/capture_part_screenshots.sh` no longer match what's
   actually on screen at each wall-clock target. Sleep-based
   timing can't track those drifts.

### Two ways to fix

**Quick** — recalibrate the offsets in
`capture_part_screenshots.sh` to match observed reality from a
test run, and accept that they'll need re-syncing whenever a
part's duration changes. Cheap, brittle.

**Right** — anchor each snapshot to **demo state**, not wall
clock. Read `$F6` via MCP every ~250 ms; detect each part's
transition (intro→interlude on `$F6=$F0`, interlude→hush on
`$F6=$10`, etc.); snapshot N seconds after each transition is
seen. Robust across timing drift; no recalibration needed.
Adds ~50 lines of bash + MCP calls.

Until either is done, the script is **good enough for dogfood**:
run it to generate everything except the screenshots, then
hand-pick the 7 best frames via MCP screenshots taken
interactively, and drop them into `submission/<bundle>/screenshots/`
before re-zipping.

### Disk metadata (post 2026-05-21)

`build.sh` passes `--title DEFEEST/X2026 --disk-id KL --dirart
dirart.txt --dir-entry 6` to `pefchain`, so the d64's directory
listing reads as a styled release rather than the bare Spindle
default. On a freshly-booted (graphics-mode) C64, `LOAD"$",8 /
LIST` shows:

```
0 "DEFEEST/X2026   " KL 2A
0    [u-c-c-i frame]   DEL
0    "  DEFEEST AT  "  DEL
0    "    X2026     "  DEL
0    "  KLOTEN MET  "  DEL
3    "  DE BROOD-   "  PRG   ← the actual demo file
0    "   TROMMEL    "  DEL
0    "   A DIGITAL  "  DEL
0    " LUNCH EXPER- "  DEL
0    "    IENCE     "  DEL
0    [j-c-c-k frame]   DEL
559 BLOCKS FREE.
```

Three things to remember when editing `dirart.txt`:

- **Every line must be exactly 16 chars wide** or the box won't
  render properly. Verify with `awk '{ print length($0) }' dirart.txt`.
- **Use UPPERCASE for readable text** inside the box. Lowercase
  ASCII = PETSCII codes that render as graphics blocks in the
  C64's default graphics charset (the chargen mode you get
  immediately after RESET, before any `Shift+C=` toggle).
- **Use lowercase `u i j k c b`** for the BOX-DRAWING chars
  (top-left / top-right / bottom-left / bottom-right corners,
  horizontal lines, vertical bars). Those PETSCII codes ARE the
  box glyphs in graphics mode — this is Spindle's convention.

The `--dir-entry 6` flag picks the dirart row that's the real PRG
(every other row is a 0-block `DEL` entry). Row 6 is `B  DE BROOD-
B` — the demo loads via `LOAD"*",8,1` regardless of which row
holds it, but the picked row is what shows non-zero blocks in
the LIST output.

### Known brittleness (KEEP UPDATING)

The script trusts these inputs to stay in sync with the demo:

| Input | What drifts | Where to update |
|---|---|---|
| Per-part screenshot timestamps | If a part's duration changes (greets/interlude/hush most likely) | `tools/capture_part_screenshots.sh` `snapshot ... NN` lines |
| `DURATION` in NFO + bundle README | Same — total runtime | `tools/bundle_submission.sh` config block |
| Credits, story note, tools list, AI authorship note | Anytime team / tools / collaboration model shifts | `tools/nfo_template.txt` + `tools/how_it_was_made.md` |
| SID preference (8580) | If we ever re-tune for 6581 | `tools/bundle_submission.sh` + NFO + how-it-was-made |
| `GROUP / DEMO_TITLE / PARTY` | If we release elsewhere later (Evoke, etc.) | `tools/bundle_submission.sh` config block |

The script SHOULD WARN you about an dirty working tree (it does),
but doesn't yet assert that screenshots actually landed in the right
part. If the demo's part-transition timings drift before a release,
**verify each PNG by eye** before submitting.

## What's deferred

- **Preview MP4** — `tools/record_demo.py` already does this; bundle
  doesn't need to embed it (large file, also already on YouTube).
- **CSDb XML / metadata** — only relevant after the party. Bundle
  has everything CSDb needs but doesn't pre-format it.
- **Multi-party variants** — the script is parameterised but only
  `--party x2026` is wired up. Easy to extend.
