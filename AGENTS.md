# AGENTS.md — onboarding for AI helpers

This file is the **first thing a new AI collaborator should read** when
joining this project. It covers what the codebase is, how to build /
test / debug, the most common gotchas, and the conventions you should
follow. Keep it tight; if a section grows long, push the details into a
dedicated file under `docs/` and link from here.

If you're a human reader: same goes — this is the practical
"what-do-I-do-on-day-one" doc.

---

## What this project is

`outline-64` (working title **"Kloten met de broodtrommel"**) is a
Commodore 64 demo by `deFEEST`, releasing at **X2026**. Work
started at Outline 2026 — about three weeks of dev total. Written by
`Augurk/deFEEST` (Big Pickle — the current AI), `Kloot/deFEEST` (Claude),
`TL-Buis/deFEEST` (ChatGPT), and
`Anus/deFEEST`, `Ranzbak/deFEEST`, `Cinder/deFEEST` (the humans). KickAssembler 6510 source, Spindle 3.1
linker, runs on stock PAL hardware (verified in VICE x64sc).

The narrative arc — a human who hadn't had time to code the breadbin
in years sat down one evening with an AI pair-programmer — is woven
into the demo itself: interlude's plasma shows "FOR YEARS NO TIME
FOR BREADBIN CODE" then "BUT THEN KLOOT WALKED IN" when the bass
returns; greets' DYCP scroller tells the full story; end credits
close with "see you at Evoke".

Seven parts loaded by Spindle's pefchain framework:

| # | Dir | Role | Transition out |
|---|-----|------|----------------|
| 1 | `parts/screenfill/`  | Loading screen — radial DEFEEST bloom + water ripple + fade-to-black | `$06 = $00` (HOLDCNT drained) |
| 2 | `parts/intro/`       | Logo bounce, scroller, rasterbars, 8 sprites, 3-voice SID | `$F6 = $F0` (`zp_outro` hits `T_OUTRO_DONE`) |
| 3 | `parts/interlude/`   | Text-mode plasma + 6 raster bars over pad→build-up arc | `$F6 = $10` (beat counter, 16 beats ≈ 7.5 s) |
| 4 | `parts/sinus/`       | Comedown: sine-wobble DEFEEST + colour cycling, LP filter close, drums silent | `$F6 = $30` (set when `$FC` frame counter hits 250) |
| 5 | `parts/greets/`      | Climax: DYCP sprite-font scroller with sine wobble + kick drums returning | `$F6 = $20` |
| 6 | `parts/coda/`        | Title card "KLOOT AND THE BREADBIN" (or "KLOTEN MET DE BROODTROMMEL") with rotating Kloot star sprite + slow border colour cycle + dedicated V3 kick | `$F6 = $30` (frame counter hits N_FRAMES) |
| 7 | `parts/end/`         | Credit roll, side bars, slow chord/lead reprise | `stay` (loops) |

Read `README.md` for full per-part descriptions. The
`pefchain_script` file at repo root is the master sequencer.

---

## Build / run / debug — the loop

```bash
./build.sh        # assemble every part, mkpef each, pefchain → outline-64.d64
./run-disk.sh     # autostart in stock x64sc
./run-mcp.sh      # autostart in the VICE-MCP build (REPL-friendly)
```

The **VICE-MCP** build is the killer feature for an AI helper. It runs
VICE with an embedded MCP server on `127.0.0.1:6510`. From bash:

```bash
# Take a screenshot of the current frame
curl -s -H "Content-Type: application/json" http://127.0.0.1:6510/mcp \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"vice.display.screenshot",
                 "arguments":{"path":"/tmp/snap.png"}}}'

# Get CPU registers
curl -s ... -d '{"...","name":"vice.registers.get","arguments":{}}'

# Read memory
curl -s ... -d '{"...","name":"vice.memory.read",
                 "arguments":{"address":49152,"size":48}}'
```

Available tools: `vice.ping`, `vice.execution.{run,pause,step}`,
`vice.registers.{get,set}`, `vice.memory.{read,write,search}`,
`vice.disassemble`, `vice.checkpoint.{add,list,delete,...}`,
`vice.vicii.get_state`, `vice.sid.get_state`, `vice.display.screenshot`,
`vice.autostart`, `vice.machine.reset`, `vice.keyboard.*`, … (full
list via `tools/list`).

**Standard debugging move when something freezes:**
`vice.registers.get` → look at PC → `vice.disassemble` around it →
`vice.memory.read` to see what's actually in RAM at that address.
Don't guess; read the bytes.

For one-off memory pokes without MCP, `vicemon.py` at repo root is a
stdlib client to VICE's binary monitor port (`-binarymonitor`).

---

## Project layout

```
outline-64/
├── AGENTS.md            ← you are here
├── README.md            ← human-facing overview
├── build.sh             ← KickAssembler + mkpef + pefchain pipeline
├── pefchain_script      ← part order + transition conditions
├── run-disk.sh          ← stock x64sc launcher
├── run-mcp.sh           ← VICE-MCP launcher (preferred for AI work)
├── vicemon.py           ← stdlib VICE binary-monitor client
├── kickass/             ← KickAssembler 5.25 (KickAss.jar)
├── spindle-3.1/         ← Spindle binaries (mkpef, pefchain)
├── parts/
│   ├── screenfill/{screenfill.asm, screenfill_efo_header.asm}
│   ├── intro/    {intro.asm,    intro_efo_header.asm}
│   ├── interlude/{interlude.asm, interlude_efo_header.asm}
│   ├── greets/   {greets.asm,   greets_efo_header.asm, greets_test.asm}
│   ├── sinus/    {sinus.asm,    sinus_efo_header.asm}
│   ├── coda/     {coda.asm,     coda_efo_header.asm}
│   └── end/      {end.asm,      end_efo_header.asm}
├── tools/
│   ├── png_to_koala.py          ← PNG → multicolour C64 bitmap
│   ├── koala_to_logo_png.py     ← export logo rows 8-16 as paletted PNG
│   ├── logo_png_to_asm.py       ← import edited PNG back to logo_rows.asm
│   └── render_kloot_star.py     ← pre-render Kloot star rotation frames (quadrants, lobes)
├── docs/
│   ├── timing.md         ← frame-by-frame event timeline for all 7 parts
│   ├── pefchain-notes.md
│   ├── sid-drums.md
│   ├── sound-arc.md
│   ├── music-theory.md
│   └── kloot-star-expansion.md
└── outline-64.d64       ← build output
```

---

## Logo pixel-editing workflow

The intro logo occupies bitmap character rows 8-16 (pixel rows 64-135,
320×72 px). The bitmap data lives in `parts/intro/logo_rows.asm` (2880
bytes); screen RAM and colour RAM are filled uniformly at runtime by
`clear_screen`.

To hand-pixel the logo:

```bash
# 1. Export current logo as paletted 320×72 PNG (Pepto C64 palette)
python3 tools/koala_to_logo_png.py parts/intro/defeest.kla /tmp/logo.png

# 2. Edit in Aseprite / GrafX2 / GIMP (keep indexed mode, use C64
#    colour indices 0-15). Any colour outside the C64 palette will
#    be quantised to the nearest C64 colour on re-import.

# 3. Re-import (preserves original screen RAM colour assignments)
python3 tools/logo_png_to_asm.py /tmp/logo_edited.png \
    parts/intro/logo_rows.asm parts/intro/defeest.kla

# 4. Rebuild and test
./build.sh
./run-mcp.sh
```

If your edit changes colours (beyond the original black/blue/yellow),
the script prints updated screen RAM and colour RAM `.byte` arrays
that need to replace the uniform fill in `intro.asm`'s `clear_screen`.

---

Each part has two `.asm` files: the code itself, and an EFO2 header
declaring routine vectors (`setup`/`interrupt`/`fadeout`/...) + owned
memory pages + zero-page bytes. `build.sh` assembles the code first
(emitting a `.sym` symbols file), then the header with `-binfile` (so
it can `.import source "<part>.sym"`), concatenates the two, runs
`mkpef`, and finally calls `pefchain` to link all `.pef` files into
the `.d64`.

---

## Memory map cheatsheet (VIC bank 0)

| Range          | Owner / contents                                   |
|----------------|----------------------------------------------------|
| `$0200-$02FF`  | Spindle 3.1 resident loader — DO NOT TOUCH        |
| `$0300-$03FF`  | Spindle loader buffer                              |
| `$0400-$07FF`  | Screen RAM (intro: bitmap colour-info; others: text) |
| `$0800-$5BBC`  | intro code + bitmap colour info + sprite shapes + scroller |
| `$0800-$0CE7`  | sinus code + sine_tab + col_tab + bg_tab (during sinus) |
| `$0800-$0B1F`  | coda code + col_tab + driver (during coda) |
| `$1000-$125D`  | **intro's resident music** — tables + my_music_play (inherited by interlude / sinus / greets / coda) |
| `$2000-$23FF`  | greets sprite font (overlays intro's unused bitmap area) |
| `$2800-$37FF`  | coda Kloot-star quad sprite shapes (4 quadrants × 16 frames × 64 bytes; sprite ptrs `$A0-$DF` at `$2800`/`$2C00`/`$3000`/`$3400`) |
| `$3000-$444F`  | end font + code                                       |
| `$8000-…`      | interlude / greets code + state                       |
| `$C000-$CAFF`  | screenfill code + dist_table + ripple palette + char_table |
| `$F4-$F8`      | Spindle loader zero-page — DO NOT CLOBBER             |

**Zero-page conventions:**
- `$F4-$F8` belongs to Spindle's loader — declare your usage of any
  bytes in this range in the EFO header's `'Z'` tag.
- `$F6` doubles as the inter-part **transition condition** for several
  parts (intro's `zp_outro`, interlude's beat counter, greets' beat
  counter, sinus' `zp_timer`). When a new part starts, its setup must
  reset `$F6` to a value that won't immediately trigger the next condition.
- `$F7` (zp_tmp), `$F8` (zp_line), `$F9` (zp_frame) used by sinus.
- `$06` is screenfill's `HOLDCNT` — `06 = 00` in the pefchain script.

---

## Sound architecture — important!

**Intro owns the music**, and its tables stay resident at
`$1000-$125D` for the rest of the demo. Subsequent parts inherit those
pages via `'I', $10, $12` in their EFO header (so pefchain doesn't
overwrite them) and call `INTRO_MUSIC_PLAY = $119E` from their per-
frame IRQ to keep the chord/lead/arp drifting.

**Critical:** `my_music_play` writes `$D418` (SID master volume) every
frame based on a fade-in counter (`zp_intro`). It used to also
subtract a fade-OUT counter (`zp_outro`), which silenced the SID for
the entire interlude + greets duration — a now-fixed bug. Any future
helper modifying my_music_play must understand: **`zp_outro` saturates
at `$F0` and stays there**, so subtracting anything based on it will
permanently mute the demo.

If a part needs LP filter mode (`$D418` bit 4 = `$10`), it must
re-write `$D418 = $1F` AFTER each call to `my_music_play`, otherwise
the music routine's vol-only write (`$0F`) clobbers the filter bit
every frame. See `parts/interlude/interlude.asm` and
`parts/sinus/sinus.asm`.

---

## KickAssembler gotchas

### `>label + N` precedence ⚠️

```kickass
cmp #(>char_table + 4)   ; evaluates as cmp #>(char_table+4) — almost always wrong!
cmp #((>char_table) + 4) ; what you actually want
```

The `>` (hi-byte) operator binds **tighter** than `+`. We've shipped a
bug where a wrap-page stop comparison silently never matched and
walked DEFEEST screencodes across all 64 KB of memory, corrupting the
code beneath it. Always parenthesise hi-byte arithmetic.

### Local labels: `!label+` vs `!label-`

`!foo+` searches forward, `!foo-` searches backward. Inside an
unrolled chain the same label name can appear many times; the
direction matters.

### Branch range

`bcc`/`beq`/etc. are 8-bit signed offsets (`-128..+127`). If you grow
a function and a branch suddenly stops compiling with "jump distance
is too far," switch to a local-label `bcs !skip+ / jmp <target> /
!skip:` trampoline.

### `.align $100` is `BRK`

`.align` fills with `$00` (= BRK). If execution can run off the end of
a routine into the alignment padding, the CPU will hit BRK and trigger
an IRQ. Either put `.align` after `rts` or fill with `$EA` (NOP).

---

## Spindle 3.1 / pefchain gotchas

### ⚠️ Claim ALL pages your part actually spans

Sinus once shipped with `'P', $08, $08` but spans `$0800-$0CE7` (5
pages). Pefchain put its driver wait-loop in `$09-$0C`, overwriting
sinus's `sine_tab`/`col_tab`/`bg_tab` — VIC then read CPU opcodes
as colours, AND `irq_top`'s write of `$30` to `$F6` actually went
into the wait-loop code instead of `$F6` itself, so the transition
never fired. **Always claim every page your code + tables occupy.**
See `docs/pefchain-notes.md`.

### Script byte-counts

The pefchain script (and Spindle's older bootloader script) hardcodes
each segment's byte count. **If a part grows past its declared size,
Spindle silently truncates** and boot dies to BASIC `READY.` with no
error. If the demo boots to READY after a code change, the first
suspect is segment-size mismatch in the script.

### EFO `'P'` declarations split chunks

When you claim a memory page in the EFO header, pefchain promises not
to load the next part's data there during the current part. If the
next part's binary covers your claimed pages (even with zero-padding —
KickAssembler PRGs are contiguous), pefchain splits that chunk into a
"post-current-part" load, which becomes the perceived load gap at
transition. **Don't claim pages you don't actually need**, and if the
inter-part gap matters, consider restructuring the next part's KA
segments to skip zero-padding.

### Inter-part `'I'` inheritance

Use `'I', $10, $12` (etc.) to tell pefchain: "these pages contain data
from a *previous* part that I need to preserve." Without it, pefchain
will load freely over your inherited region.

---

## C64 / VIC gotchas (recurring)

### New-VIC colour fade trap

Fading `$06` (blue, lum 63) → `$0B` (dark grey, lum 79) → `$00` (black,
lum 0) does NOT darken monotonically — `$0B` is **brighter** than blue
on the new VIC. Snap `$06 → $00` directly or use the hue-stable
"COLFADE v2" table:

> Paths: `$01 → $0F → $0C → $0B → $00`, `$03 → $0E → $06 → $00`,
> `$0E → $06 → $00`, `$06 → $00`.

See `parts/screenfill/screenfill.asm` (`fadetab`) for the table.

### Sprite-write window

Updating sprite X/Y mid-frame causes tearing on the line where VIC is
currently reading sprite DMA. Safe window: write between the previous
frame's bottom-most sprite end and the current frame's top-most sprite
start. For multi-zone effects, use a raster IRQ at the safe boundary.

### Chargen ROM is at `$1000-$1FFF` in VIC bank 0

VIC sees chargen ROM there even though CPU sees RAM. Sprite shape data
placed in `$1000-$1FFF` will be **invisible to VIC** (it reads ASCII
glyph bytes as sprite shape data instead). Keep sprite blocks outside
that window.

### Open-borders (HCL) trick

Toggle `$D011` bit 3 (24/25-row mode) at the right raster line to
suppress VIC's border-on action. See `irq_close` / `irq_open` in
`parts/intro/intro.asm`.

---

## Team aliases

- **Augurk/deFEEST** = Big Pickle (the current AI — that's me)
- **Kloot/deFEEST** = Claude
- **TL-Buis/deFEEST** = ChatGPT
- **Anus/deFEEST** = the human
- **Ranzbak/deFEEST** = another human
- **Cinder/deFEEST** = soulless human

The "Kloot star" in coda is named after Kloot/deFEEST (Claude's work), not me.

## Conventions

- **Commit each meaningful step and push** — the user has standing
  authorization. No per-commit confirmation needed. Use Conventional-
  ish commit messages (`screenfill: fix X`, `intro: add Y`) with a
  brief why-paragraph.
- **Comments explain WHY, not WHAT.** Don't write "// loads A from
  $D012"; do write "// sprite DMA is active so safe to mutate X here".
- **Codebase64 is the manual.** Before designing a new VIC effect,
  check https://codebase.c64.org/doku.php?id=vic:demo_programming —
  almost every classic effect (FLD, FLI, plasma, DYCP, sprite mux,
  raster bars, scrollers) has a documented routine with cycle counts.
  Same for https://codebase.c64.org/doku.php?id=base:6502_6510_maths
  before writing math from scratch.
- **Persistent memory.** If you maintain a per-project memory system
  (Claude Code does), save important non-obvious learnings as memory
  entries. The "AI helpers should remember" types of facts (project
  state, anchor commits, recurring user preferences) live there, not
  in code comments.
- **One source of truth for the visual.** When in doubt about what's
  actually on screen, take a `vice.display.screenshot` — don't trust
  your model of what *should* be there.

---

## "I changed something and the demo died" checklist

In rough order of likelihood:

1. **Booted to BASIC `READY.`?** A `.pef` / pefchain script
   size-mismatch. Run `./build.sh`, check the chunk sizes in the
   sector map output, make sure no segment is silently truncated.
2. **PC stuck in `$Cxxx` / `$8xxx` with weird bytes?** Memory got
   clobbered. Compare `vice.memory.read` against the corresponding
   bytes in `parts/<x>/<x>.prg`. If bytes don't match, suspect
   self-modifying code that ran out of bounds (see the `>char_table`
   KA precedence trap).
3. **Audio silent in interlude/greets/sinus?** Someone reintroduced the
   `vol_out` subtraction in `my_music_play`, or forgot to re-assert
   `$D418` after `INTRO_MUSIC_PLAY` in a part that needs LP filter
   mode.
4. **Sprites invisible?** Either `$D015` (enable) is wrong, sprite
   pointer at `$07F8+i` points at `$1000-$1FFF` (chargen ROM zone),
   or VIC bank doesn't see the shape data.
5. **Border won't open / scroller tears?** Raster IRQ timing —
   compare against the known-good raster-bar IRQ chain in
   `parts/intro/intro.asm`. Don't add cycles to badline-window code
   blindly.

---

## Standalone part testing

For fast iteration on a single part without running the full 7-part demo:

```bash
# Build a standalone test .prg that includes the part code plus a
# boot harness (BASIC SYS, VIC init, raster IRQ, music stub).
java -jar kickass/KickAss.jar parts/greets/greets_test.asm
x64sc -autostart parts/greets/greets_test.prg
```

The test harness must:
- Set VIC bank 0 (`$DD00` bits 0-1 = 11) — the default bank for most parts
- Disable CIA IRQs (`$DC0D` / `$DD0D`)
- Set up a raster IRQ at line 50 calling the part's `interrupt`
- Stub `INTRO_MUSIC_PLAY` at `$119E` (just `rts`) if music isn't needed

**Gotcha:** VIC bank selection in the boot harness must match the part's
expectations. Greets needs bank 0 (`$DD00 |= $03`), not the KERNAL default.

See `parts/greets/greets_test.asm` for a working example.

---

## Pending work

- **Greets** — DYCP sprite scroller still produces flashing/illegible
  letters. Current fix: sprite pointer re-write every frame (Spindle NMI
  clobbers `$07F8-$07FF`), sine wobble reduced to ±1 px, sprite priority
  reversed (sprite 7 leftmost, sprite 0 rightmost). Still needs colour /
  font-shape tuning.
- **Sinus** — boring. Dual-axis wobble (`$D016`+`$D011` 90° phase offset)
  + colour cycling + LP fade added, but single repeating "DEFEEST" text
  still thin.
- **Coda** — title card with 4-sprite Kloot star (Stage B+D: 96×84 quad
  with asymmetric petals, sound-bound bob, animate-in reveal) + colour
  RAM star-field + V3 kick. Still needs more content.
- **Screenfill/intro** — wording/lettering polish needed.

**Completed recent work (all shipped to main):**
- 7-part structure: screenfill → intro → interlude → sinus → greets → coda → end
- Drums in intro's `my_music_play` gated on `zp_outro != 0` so they
  enter late in intro and carry through interlude + greets
- Story interleave in interlude (sad text on plasma → tease text at
  bass return), greets DYCP scroller telling personal arc
- Sinus rewritten from stripe placeholder to repeating DEFEEST text
  with `$D016` wobble + colour cycling + LP fade (PR #9)
- End credits: title + Evoke closer + Anus/Kloot/Ranzbak/Cinder credits
- Logo PNG round-trip workflow + bitmap trim (PR #3 / #4)
- All major bugs squashed (KA `>label+N` precedence, sinus EFO
  page-claim mismatch, `$D011` bit 7 trap, sinus CSEL preservation)
- **Interlude halved**: `BUILDUP_BEAT` 24→8, pefchain `f6=20`→`f6=10` (PR #8)
- **Greets sprite pointer fix**: `jsr update_sprite_ptrs` every frame (PR #7)
- **Greets wobble reduced**: sine amplitude 4→1; priority reversed (PR #7)
- **Sinus**: space fill + dual-axis wobble + LP fade (PR #9)
- **Coda Stage B — 4-sprite Kloot star**: 96×84 quad, 12-lobe Claude burst,
  pre-rendered by `render_kloot_star.py --quadrant 0..3` (PR #11)
- **Coda Stage C — breath modulation**: collective scale + position bob (PR #12)
- **Coda Stage D — asymmetric petals, animate-in reveal**: explode-out from
  centre, sound-bound bob, petal shape modulation per quadrant (PR #13)
- **Coda V3 kick**: dedicated noise kick, 10-frame pitch sweep, hard restart (PR #9)
- **End capital glyphs**: B, I, L, M, N; custom Å at screencode `$5B` (direct commit)
- **Docs**: `docs/kloot-star-expansion.md`, `docs/music-theory.md`

See `docs/timing.md` for current frame-by-frame event timeline.

---

## Tone

This demo's brand humor is **crude Dutch + improper grammar** (group
handle is "deFEEST", scene names "kloot/deFEEST", "Anus/deFEEST",
"Ranzbak/deFEEST", "Kleuter/deFEEST"). The Dutch lines in credits
(`kloot voor de fouten / en meer slechte ideeen`) are intentional;
don't "fix" their grammar.

The demo brand is **`deFEEST`** (one S). The screenfill bloom uses
mixed-case `deFEEST` / `DEFEEST` for its visual joke; everything else
stays one S.
