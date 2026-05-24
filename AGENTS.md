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
FOR BREADBIN CODE" then "AI WROTE" drops in as 8 sprite letters
when the bass returns; greets' DYCP scroller tells the lunchbox-party
story; coda lands the title "KLOTEN MET DE BROODTROMMEL / A DIGITAL
LUNCH EXPERIENCE"; end credits close out the bow.

**Read `docs/narrative-arc.md` and `docs/sound-arc.md` first** —
they're the two-sided map of the same arc (story side and audio side
locked in step). Every text reveal sits on an audio shift, every
visual climax has a music moment under it.

Seven parts loaded by Spindle's pefchain framework:

| # | Dir | Role | Transition out |
|---|-----|------|----------------|
| 1 | `parts/screenfill/`  | Loading screen — radial DEFEEST bloom + water ripple + fade-to-black | `$06 = $00` (HOLDCNT drained) |
| 2 | `parts/intro/`       | Logo bounce, scroller, rasterbars, 8 sprites, 3-voice SID + K-S-K-S kit | `$F6 = $F0` (`zp_outro` hits `T_OUTRO_DONE`) |
| 3 | `parts/interlude/`   | Plasma + bars-on-buildup, typewriter "FOR YEARS…" + sprite-letter "SPARKED" drop with white-border flash, LP V1+V2 filter sweep | `$F6 = $10` (~16 beats ≈ 7.7 s) |
| 4 | `parts/hush/`        | Manifesto: full-screen colour-RAM fire engine ($A0 blocks + 7-step sbctab palette chain + drifting wave seed at row 24) with a 3-row blue banner carrying inverted cryptic-poetry text (phase 1 dark blue → phase 2 light blue swap at frame 120, white-border flash). K-S-K-S drums hammer through ($F6=$01); LP filter still closes on V1+V2. | `$F6 = $30` (frame counter hits 250) |
| 5 | `parts/greets/`      | Climax: smooth-pixel DYCP sprite-font scroller (~50 s, scroll-driven) over a multi-colour koala backdrop. Sprite-7 carousel for clean right-edge entry. Snap landing on " KLOTEN " (the demo title's first word). Drums returning, V2 LP "wah". | `$F6 = $82` (scroll-driven settle + 4 beats) |
| 6 | `parts/coda/`        | "KLOTEN MET DE COMMODORE / LEARN EXPLORE DISCOVER / RELEASED AT X2026", twin brown+cyan Kloot stars (Stage F ping-pong zoom breath) on wide sine orbits, alternating priority + in/out of title plane, 32-star 4-tier parallax PETSCII starfield, **triumphant full K-S-K-S kit + V1 bass-bleed sub-thump** (setup sets `$F6 = $01` so intro's drums fire through the held title) | `$F6 = $30` |
| 7 | `parts/end/`         | Credit roll, side bars, slow chord/lead reprise (V1/V2 triangle pad, V3 pulse w/ PWM-hi shimmer pulled under via sustain $9, all-voice LP $20..$58 cutoff sweep) | `stay` (loops) |

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
│   ├── hush/     {hush.asm,     hush_efo_header.asm}
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

To pixel-edit the logo:

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

For the full per-part / per-page table see
[`docs/memory-layout.md`](./docs/memory-layout.md). Quick reference:

| Range          | Owner / contents                                   |
|----------------|----------------------------------------------------|
| `$0200-$02FF`  | Spindle 3.1 resident loader — DO NOT TOUCH         |
| `$0300-$03FF`  | Spindle loader buffer                              |
| `$0400-$07FF`  | Screen RAM (intro: bitmap colour-info; others: text) |
| `$0800-$5BBC`  | intro code + bitmap colour info + sprite shapes + scroller |
| `$0800-$0CE7`  | hush code + sine_tab + col_tab + bg_tab (during hush) |
| `$0800-$0FFF`  | coda code + state + col_tab + sin_tab (8 pages) (during coda) |
| `$1000-$125D`  | **intro's resident music** — tables + my_music_play (inherited by interlude / hush / greets / coda) |
| `$2000-$27FF`  | greets sprite font (during greets) / coda Kloot TR+TL sprite shapes (during coda) |
| `$2C00-$37FF`  | coda Kloot BL+BR sprite shapes (4 quadrants × 24 frames × 64 B; sprite-pointer bases `$80/$98/$B0/$C8`) |
| `$3000-$444F`  | end font + code                                    |
| `$8000-$8FFF`  | interlude / greets code + state + scroll message + sprite-font glyphs |
| `$C000-$CAFF`  | screenfill code + dist_table + ripple palette + char_table |
| `$F4-$FA`      | Spindle loader + shared zero-page (multiple part-specific overlays — see memory-layout.md) |

**Zero-page conventions:**
- `$F4-$F8` belongs to Spindle's loader — declare your usage of any
  bytes in this range in the EFO header's `'Z'` tag.
- `$F6` doubles as the inter-part **transition condition** for several
  parts (intro's `zp_outro`, interlude's beat counter, greets' beat
  counter, hush' `zp_timer`). When a new part starts, its setup must
  reset `$F6` to a value that won't immediately trigger the next condition.
- `$F7` (zp_tmp), `$F8` (zp_line), `$F9` (zp_frame) used by hush.
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
`parts/hush/hush.asm`.

---

## KickAssembler gotchas

### `>label + N` precedence ⚠️

```kickass
cmp #(>char_table + 4)   ; evaluates as cmp #>(char_table+4) — almost always wrong!
cmp #((>char_table) + 4) ; what you actually want
```

The `>` (hi-byte) operator binds **tighter** than `+`. We've shipped a
bug where a wrap-page stop comparison silently never matched and
spread DEFEEST screencodes across all 64 KB of memory, corrupting the
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

Hush once shipped with `'P', $08, $08` but spans `$0800-$0CE7` (5
pages). Pefchain put its driver wait-loop in `$09-$0C`, overwriting
hush's `sine_tab`/`col_tab`/`bg_tab` — VIC then read CPU opcodes
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

### `.align 256` + 'P'-claim collision (Stage F coda incident, 2026-05-21)

`.align 256` is great for performance — `lda table,y` never crosses a
page boundary, saving 1 cycle per indexed read. But the alignment
directive **doesn't know about your EFO `'P'` claim**. It just bumps
PC to the next 256-byte boundary regardless.

Concrete symptom from coda: `'P', $08, $0F` claimed 8 pages. Code +
state grew by ~20 bytes past `$0DFF`. The `.align 256` before
`col_tab` jumped to `$0F00`; `.align 256` before `sin_tab` then
jumped to `$1000`, dropping `sin_tab` into chargen-ROM page `$10` —
which coda *inherits* from intro's music tables (`'I', $10, $12`).
Build output: `pefchain: Increase MAXEFFECTS!` plus repeated
`'(blank)' and 'coda' share pages 10` warnings as pefchain
desperately inserted filler trying to resolve the conflict.

**When you `.align 256` data inside a 'P' claim, check that the
table can't overflow past your claim end.** Either size your code to
leave headroom, or place the table explicitly via `* = $XX00` so it
errors at assembly time when there's not enough room rather than
silently spilling into the next page.

### Disk title / dirart / disk ID — case-mode quirk

The C64 boots into **graphics character set** by default (the
"ALL CAPS + box graphics" mode). In that mode:

- PETSCII bytes `$41-$5A` (= ASCII `A`-`Z`) render as readable
  uppercase letters
- PETSCII bytes `$61-$7A` (= ASCII `a`-`z`) render as **graphics
  blocks**, not lowercase letters

So if you set `--title "defeest/x2026"` in `pefchain`, the disk
listing shows the title as a string of PETSCII graphics rather
than the word `defeest`. Same for `--disk-id "kl"` — renders
as `KL` only if uppercase.

**Lesson for `--title`, `--disk-id`, and `dirart.txt`:**
use **UPPERCASE** for any text that should READ as letters on a
freshly-booted (graphics-mode) C64. Lowercase letters in your
source map to PETSCII codes that the default character set
renders as graphics blocks. Spindle's example `dirart.txt`
uses lowercase `u c c i j k b` etc. for the BOX-DRAWING chars
on purpose (those PETSCII codes ARE the box-corner glyphs in
graphics mode), and uppercase `EXAMPLE DEMO` for the readable
text.

Concrete pattern that works (`dirart.txt`):

```
ucccccccccccccci      ← box top: lowercase = corners + lines
b              b      ← box sides: lowercase = vertical bars
b  HELLO WORLD b      ← interior text: UPPERCASE for readability
jcccccccccccccck      ← box bottom
```

See `build.sh` for the `--title DEFEEST/X2026 --disk-id KL`
invocation and `dirart.txt` for the actual release art.

---

## DYCP / sprite-font gotchas

### Always fill EVERY pointer slot referenced by the lookup table

If you use a `ptr_lookup` table to map char codes → sprite-shape
pointer values (greets pattern), make sure **every distinct pointer
value in that table corresponds to actual emitted glyph data**.
Spaces, punctuation, digits — anything you map to a "blank" slot —
needs an explicit `.fill 64, 0` (or whatever blank-tile content you
want) at that pointer's address.

Concrete symptom from greets: `ptr_lookup` mapped every char outside
A-Z to slot `$9A` (= `font_data + 26*64`). `font_data` only emitted
26 A-Z glyphs and no padding, so slot `$9A` read whatever RAM
happened to sit there at boot — random bytes from the loader, the
previous part, whatever. The "blank" sprite rendered as scrambled
pixels, and any message containing spaces / `.` / digits read as
"letters popping in" (= readable letters interleaved with garbage).
Fix was one line: `.fill 64, 0` after the A-Z loop.

### Absolute-Y addressing reach is 256 bytes

`lda message,y` loads from `message + Y` where `Y` is 8-bit, so the
reachable window is exactly 256 bytes. If your message / lookup
table is larger, `scroll_pos` capped at ~248 silently — the scroller
appeared to "advance" but `update_sprite_ptrs` was reading the same
8-char window forever past offset 255.

Solutions, in order of pain:
- **Self-modify the LDA's address operand**: compute
  `message + scroll_pos` (16-bit add via carry), patch the operand
  bytes once per `update_sprite_ptrs` call, run the inner loop with
  `Y = 0..N` against the patched instruction. Pattern in
  `parts/greets/greets.asm:update_sprite_ptrs`.
- ZP indirect: `lda (ptr),y` — requires 2 ZP bytes per pointer.
- Multiple 256-byte chunks with selector code — usually worse.

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

### Self-modifying code: opcode at `+0`, operand-lo at `+1`, operand-hi at `+2`

For an absolute STA / LDA / etc., the assembled bytes are:

```
8D 00 D8     ; sta $D800 — opcode is byte +0
                                   operand-lo is +1
                                   operand-hi is +2
```

To patch the target address, write to **`label+1` (lo) and
`label+2` (hi)** — NOT `label` (which is the opcode byte). Burning
the opcode turns the instruction into garbage; subsequent writes
go to wherever the corrupted opcode happens to interpret as.

We shipped this bug in PR #26 (starfield self-mod patched `+0/+1`
instead of `+1/+2`); the demo hung on coda for hours until #29
fixed it. Always double-check offsets on self-mod or run a quick
disassembly of the label after patching.

### `$D417` voice routing is NOT optional for the filter

`$D418` bit 4 turns LP filter mode ON, but the filter only
affects voices whose corresponding bit is set in `$D417` (bits 0-2
= V1/V2/V3, bit 3 = external in). If you set LP mode but no voices
are routed, the cutoff sweep does nothing audibly. Hush shipped
silent filter sweeps for weeks because `$D417 = $10` (resonance $1
but no voice routing). Always set BOTH together. See
`docs/music-theory.md` "Critical pitfall" section.

### ZP slot collisions across the demo

The intro's resident `my_music_play` (called from every part except
end) uses `$F9` / `$FA` as private scratch — they're safe to use as
ephemeral scratch IN A PART, but DON'T hold cross-frame state in
them. Each part also has its own ZP claim in the EFO header
(`'Z', from, to`); collisions there cause silent state corruption.

In coda specifically: `$FB` = `zp_subtick` and `$FC` = `zp_frame`.
Using them as ZP-indirect pointer destroys both, hanging the
transition. Use `$F9` / `$FA` for short-lived scratch, OR
self-modifying absolute STAs (see above).

When adding ZP-using code: cross-check the EFO header's `'Z'`
range vs. what other parts assume from `my_music_play`.

### `$08` (orange) vs `$09` (brown) — the Kloot star is BROWN

The Claude logo is brown ($09), not orange ($08). Setting the star
to $08 reads as Claude orange but the *demo* convention is the
**brown Kloot star**. Same shade as bread crust — fits the
lunchbox theme. See `parts/coda/coda.asm` star colour setup.

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
3. **Audio silent in interlude/greets/hush?** Someone reintroduced the
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

## Pending work (current as of 2026-05-22)

See [`docs/two-weeks-out.md`](./docs/two-weeks-out.md) for the full
stocktake + recommended focus plan for the X2026 runup.

- **Real-hardware verification — never done.** Two weeks out from
  X2026. VICE is generous; real PAL C64 can break on IRQ timing,
  `$D012` race conditions, DMA stretching. Highest-priority item.
- ~~**Hush** — dual-phase accusation→answer rewrite done (commit `cff79d1`).~~
- **End-credits clean↔dark slow-sine modulation** — documented as
  future polish in [`docs/sound-arc.md`](./docs/sound-arc.md) under
  "End-credits darkening". Sketch implementation ready; not built.
- **Submission compliance** — X2026 rules unread; filename / runtime
  cap / screenshot package not verified.
- **PAL CRT preview** — never seen the demo on anything but a
  flat-panel monitor.

**What's DONE since the docs were last refreshed (2026-05-20 → 22):**

- **Hush colour-RAM fire rewrite** (commit `e09591d`, 2026-05-24) —
  replaced the sine-wobble + DEFEEST wallpaper with a full-screen
  colour-RAM fire engine. Standard hires text mode, every cell is `$A0`
  (inverse-space solid block); COLOUR RAM is the heat field; propagation
  cools through a 7-step `sbctab` palette chain (white → yellow → orange →
  light red → red → brown → dark grey → black). Row-24 wave-palette
  seed drifts ~1 col / 4 frames; row alternation halves prop cost so
  `my_music_play` ticks at clean 50 Hz. A 3-row blue banner on rows 10-12
  carries the cryptic-poetry text ("THE MACHINE WAS NOT EMPTY" → "THE
  SPARK CAME BACK") as inverted glyphs cut out of solid colour blocks.
  Propagation skips banner rows; row 9 sources from row 13 so fire keeps
  climbing past the banner. Drums hammer through (`$F6 = $01` gate ON)
  — no silent breakdown. EFO claim shrinks to `'P', $08, $0B` (4 pages).
- **Coda parallax PETSCII starfield** (PR #31) — 32 stars across 4
  speed tiers, replacing the original static-asterisk twinkle.
- **Coda Stage F ping-pong zoom breath** (PR #33) — both Kloot stars
  ping-pong `0 → 23 → 0` forever; star 1 opens with zoom-in, star 2
  with zoom-out, naturally out of phase. Plus the size-diet sprite-
  pointer loop refactor that fits Stage F back inside coda's 8-page
  claim.
- **Coda NMI-clobber jitter fix** (direct commit `ae80273`) — sprite
  pointers re-written every frame at 50 Hz so the Spindle NMI loader
  can't drag them off-screen between IRQs.
- **Greets epic-extended** (PR #32) — 15 s scroller stretched out with
  16-bit `scroll_pos`. (Post-PR-#32 the scroll is now smooth-pixel
  at 9 px/frame, scroll-driven settle on " KLOTEN ", and runs over
  a multi-colour koala backdrop.)
- **Greets DYCP wobble** — sine amplitudes ±3 (Y) and ±2 (X).
- **Interlude breathing room + SPARKED border flash** (direct commit
  `8ed0777`) — `BEAT_PERIOD 20→24`, `BUILDUP_BEAT 4→6`,
  `TRANSITION_BEAT 10→16`, white-border flash on SPARKED landing.
- **AGENTS.md gotcha additions + memory-layout refresh + tools
  helpers** (PR #35).
- **`docs/two-weeks-out.md`** (PR #36) — stocktake + focus plan.
- **Hush vision doc** (commit `0926851`) — `docs/hush-vision.md` naming
  the gap with three effect directions (Option A/C recommended). Written by
  Kloot/deFEEST; superseded by my accusation→answer rewrite.

See [`docs/timing.md`](./docs/timing.md) for the current frame-by-frame
event timeline.

---

## Tone

This demo's brand humor is **crude Dutch + improper grammar** (group
handle is "deFEEST", scene names "kloot/deFEEST", "Anus/deFEEST",
"Ranzbak/deFEEST", "Cinder/deFEEST"). The Dutch lines in credits
(`kloot voor de fouten / en meer slechte ideeen`) are intentional;
don't "fix" their grammar.

The demo brand is **`deFEEST`** (one S). The screenfill bloom uses
mixed-case `deFEEST` / `DEFEEST` for its visual joke; everything else
stays one S.
