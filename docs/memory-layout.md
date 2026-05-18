# Memory layout — and why it matters for C64 demo coding

This doc covers our demo's actual memory map, plus the underlying
C64 constraints that explain WHY the map looks the way it does. If
you're new to demo coding the constraints feel arbitrary; once you
internalise them every odd choice in the codebase will make sense.

## The hardware reality (skip if you know this)

### 64KB CPU memory is shared with ROM, I/O, and the VIC

The 6510 sees a flat 64KB address space, but most of it is shared:

| Range          | What's there |
|----------------|--------------|
| `$0000-$00FF`  | Zero page (fast, indexable, indirect-addressable) |
| `$0100-$01FF`  | CPU stack (256 bytes, hardware-fixed) |
| `$0200-$03FF`  | "Free RAM" — but Kernal/Basic + Spindle use much of it |
| `$0400-$07FF`  | Default text-mode screen RAM (1 KB) |
| `$0801-$9FFF`  | Free RAM (39 KB) |
| `$A000-$BFFF`  | Basic ROM (or RAM if banked out) |
| `$C000-$CFFF`  | Free RAM (4 KB) |
| `$D000-$DFFF`  | I/O (VIC, SID, CIA1, CIA2, colour RAM) — or chargen ROM or RAM, depending on `$01` |
| `$E000-$FFFF`  | Kernal ROM (or RAM if banked out) |

The CPU mapping is controlled by `$01` (the processor port). Default
`$01 = $37` exposes Basic ROM, I/O, Kernal ROM. Writing `$35` keeps
Basic ROM hidden as RAM (most demos run with `$35` or `$34`).

### The VIC-II sees its own 16KB window, not the full 64KB

The VIC chip has only 14 address lines = it can only see 16 KB at a
time. CIA2 register `$DD00` bits 0-1 select which 16KB bank:

| Bits | VIC bank | Range |
|------|----------|-------|
| `11` | **0**    | `$0000-$3FFF` |
| `10` | 1        | `$4000-$7FFF` |
| `01` | 2        | `$8000-$BFFF` |
| `00` | 3        | `$C000-$FFFF` |

So if VIC is in bank 0, **all sprites, screen RAM, and chargen data
the VIC reads must be located in `$0000-$3FFF`**. The CPU can still
access the other 48 KB, but the VIC can't see it.

### The chargen ROM hole — a critical trap

In banks 0 and 2, the VIC sees **chargen ROM** at offsets
`$1000-$1FFF` instead of the RAM that's there for the CPU:

| VIC bank | Range where VIC sees chargen ROM | Same range CPU sees |
|----------|----------------------------------|---------------------|
| 0        | `$1000-$1FFF`                    | RAM                 |
| 2        | `$9000-$9FFF`                    | RAM                 |

This means:

- **Sprite shape data placed in `$1000-$1FFF` is invisible** to the
  VIC — it reads chargen letters instead of your sprite bytes. Put
  sprites OUTSIDE that range.
- **Bitmap data placed at `$1000-$1FFF` is invisible** for the same
  reason. Bitmap base must be `$0000` or `$2000` within a bank.
- Conversely, **you can use the chargen ROM "for free"** by pointing
  `$D018` chargen bits at `$1000` — no need to copy it into RAM.
  We do this in screenfill, interlude, sinus, end.

In banks 1 and 3 there's no chargen ROM in view, so you need to copy
chargen into RAM there.

### $D018 — screen + chargen base within the VIC bank

`$D018` packs two offsets, both relative to the current VIC bank:

| Bits | What |
|------|------|
| 7-4  | Screen RAM base × `$0400` |
| 3-1  | Chargen base × `$0800` |

Typical values you'll see in this codebase:

- `$14` — screen at `$0400`, chargen at `$1000` (uppercase ROM)
- `$17` — screen at `$0400`, chargen at `$1800` (lowercase ROM)
- `$18` — screen at `$0400`, chargen at `$2000` (custom RAM charset)
- `$3C` — screen at `$0C00` (relocated), chargen at `$3000`

## Why memory layout matters for demos

A modern programmer's instinct: "put data wherever, link it later."
On C64, you can't. Concretely:

1. **Every effect has a VIC bank choice that constrains where its
   data can live.** Bitmap-mode logos need bitmap at `$0000` or
   `$2000` of the bank. Sprites need shape data in the same bank,
   outside the chargen hole.

2. **Spindle's resident loader takes its own ~512 bytes** at
   `$0200-$03FF`. Don't write there.

3. **Loading the next part during the current one** (pefchain's
   background NMI loader) needs free pages to stream into. If the
   current part owns too many pages, the next part has to wait at
   the transition, creating a visible/audible gap.

4. **Multi-part demos share zero-page across parts**, but `$F4-$F8`
   belongs to Spindle. We use `$F6` as the inter-part transition
   condition byte (multiple parts each repurpose it).

5. **Music data needs to be resident in one bank for the whole demo**
   if multiple parts call into it. Intro's music tables at
   `$1000-$125D` are inherited by every later part via `'I',$10,$12`
   in their EFO header — pefchain promises not to overwrite those
   pages when loading subsequent parts.

In short: the memory map IS the design document of a C64 demo. Pick
wrong and the loader pauses, sprites turn into chargen glyphs, the
SID goes silent, or the entire program corrupts.

## This demo's memory layout

VIC bank 0 throughout (`$DD00 & 3 = 11`). All parts run in this bank
so we never touch CIA2 `$DD00` after the initial Spindle setup.

### CPU view — per-part

| Range          | screenfill | intro      | interlude | sinus     | greets    | end       |
|----------------|------------|------------|-----------|-----------|-----------|-----------|
| `$0200-$03FF`  | Spindle    | Spindle    | Spindle   | Spindle   | Spindle   | Spindle   |
| `$0400-$07FF`  | screen RAM | bitmap colour | screen + plasma | screen (DEFEEST) | screen | screen + credits |
| `$0800-$0FFF`  | —          | code + IRQs| —         | sinus code| —         | —         |
| `$0800-…`      | —          | logo + sprite | —      | —         | —         | —         |
| `$0C00-$0FFF`  | char_table | (free)     | —         | —         | —         | —         |
| `$1000-$125D`  | —          | **resident music** ←inherited by all later parts | | | | end uses own |
| `$1300-…`      | —          | compact logo_rows | —    | —         | —         | —         |
| `$2000-$27FF`  | —          | —          | —         | charset (256×8) | sprite font | — |
| `$2800-$3FFF`  | (free)     | intro bitmap (runtime cleared) | — | (free) | (free) | end font + code |
| `$4000-$47FF`  | —          | rainbow palette + sine tables | — | — | — | — |
| `$4C00-$53FF`  | —          | chargen-ROM copy (for scroll) | — | — | — | — |
| `$5400-$5BBC`  | —          | bitmap scroller | — | —        | —         | —         |
| `$8000-…`      | —          | —          | code      | —         | code + tables | — |
| `$C000-$CB00`  | code + tables | — | — | — | — | — |

### Zero-page

| Byte | Used for | When |
|------|----------|------|
| `$02-$08` | screenfill state (CHARCNT, SCRPOS, WCNT, PHASE, HOLDCNT, RADIUS, RFRAME) | screenfill |
| `$F4-$F8` | Spindle loader (do not touch) | always |
| `$F4` | beat phase | interlude, greets |
| `$F5` | filter cutoff / scratch | interlude, sinus |
| **`$F6`** | **inter-part transition condition byte** — every part either reaches a specific value here to trigger the next part, or its setup resets it to start counting | always |
| `$F7-$FA` | beat counter / scroll pos / kick state / shadow freq | varies per part |
| `$FB-$FE` | text pointers / smooth scroll / frame counter | intro, end |

### Why bytes are placed where they are (concrete examples)

- **`drum_state` lives at `$128A`** (inside intro's music segment)
  rather than zero-page, because every part that calls
  `INTRO_MUSIC_PLAY` at `$119E` sees the same address. Putting it in
  intro's `'I',$10,$12`-protected pages means interlude / sinus /
  greets can all read and write it without needing their own zp
  declaration.

- **screenfill keeps its code at `$C000`** (VIC bank 0's last 4 KB)
  because that area is otherwise unused by the demo, and importantly
  it's NOT overwritten when pefchain loads intro into `$0400-$5BBC`
  underneath. Putting screenfill's code anywhere in `$0400-$5BBC`
  would mean it deletes itself as it runs.

- **screenfill's `dist_table` is at `$C200`**, page-aligned. Page
  alignment matters because indexed reads (`lda dist_table,y` where
  `y` runs `0..255`) never cross a page boundary — saves a cycle
  per read and keeps timing predictable for the colour-cycle inner
  loop.

- **The intro's koorball sprite shapes are at `$0B00-$0B3F`**, NOT
  at `$1000-$1FFF`. If we put them in the `$1000-$1FFF` range, the
  VIC would read chargen ROM bytes as sprite shapes — every sprite
  would look like a chunk of an 'A' or '@' glyph.

- **The end credit font is copied to `$3000-$37FF`** (in bank 0,
  outside the chargen hole). Choosing `$3000` keeps it in the same
  VIC bank as the screen RAM at `$0400`, and `$D018` selects it via
  the chargen bits.

- **greets' sprite font is at `$2000-$27FF`**. That's the same area
  intro uses for its bitmap (`$2000-$3FFF`), but by the time greets
  runs intro is gone, so the bytes are free to repurpose. Pefchain
  doesn't know or care — it just sees the EFO header's `'P',$20,$23`
  claim and protects those pages while greets is the active part.

## Background loading and the load-gap problem

Pefchain's NMI-driven loader streams the next part's bytes into RAM
DURING the current part. When the current part finishes, pefchain
calls its `fadeout` routine (which returns carry-set when ready) and
then runs the next part's `setup`.

For this to be seamless:

1. The current part's "owned" pages (EFO `'P'` tags) tell pefchain
   "don't load here while I'm running". Pages NOT claimed are fair
   game for streaming.
2. The next part's binary must fit in those non-claimed pages.

If the next part NEEDS pages the current part claims, pefchain has
to split that data into a separate post-load chunk, which means a
visible pause at the transition.

We hit this with the screenfill→intro transition: screenfill claims
`$04-$07` (its screen RAM), but intro's BitmapScreenRAM is exactly
`$0400-$09F1`. So `$0400-$07FF` of intro can't pre-load during
screenfill. It loads in the ~120 ms gap between the two parts —
small enough to be tolerable.

## Spindle's `'I'` tag — music inheritance

The most powerful pattern in this demo:

- Intro's EFO declares `'P', $10, $12` (it OWNS those pages)
- Every later part declares `'I', $10, $12` (it INHERITS those pages)

When pefchain loads interlude / sinus / greets, it preserves the
contents of `$10-$12` from the previous load. So intro's music
tables — set up at `$1000-$125D` during intro's `my_music_init` —
remain in RAM forever. Each later part can call `jsr $119E`
(`my_music_play`) and the chord progression + lead + arp + drums
keep going without interruption.

This is why removing the `vol_out` subtraction in `my_music_play`
(see [`sound-arc.md`](./sound-arc.md)) was so important: a single
change to the shared routine affected every part that inherited it.

## When you grow a part past its budget

If you add code to a part and it suddenly silently breaks:

1. **Check the build's sector map** (`./build.sh` tail output) — if
   a part now spans more pages than expected, the chunk crunched-
   to byte count grows.
2. **Look for KA branch-too-far errors** — relative branches
   (`bne`, `bcc`, etc.) are 8-bit signed, so growing a function
   past 128 bytes between source and target breaks the build. Fix
   with a `bcs !near+ / jmp !far+ / !near:` trampoline.
3. **Look for stale EFO `'P'` ranges** that no longer cover your
   actual code. Pefchain protects only the declared ranges; if
   your code spills past, the next part may overwrite it mid-run.

## Recommended reading

- [Codebase64 — VIC-II memory organisation](https://codebase.c64.org/doku.php?id=base:vicii_memory_organizing)
  for the canonical chargen-ROM-hole explanation
- [Codebase64 — VIC demo programming index](https://codebase.c64.org/doku.php?id=vic:demo_programming)
  for effects that constrain memory layout (FLD, FLI, bitmap modes)
- [Codebase64 — SID register reference](https://codebase.c64.org/doku.php?id=base:sid_registers)
  for which SID registers are write-only (relevant when you try to
  read them back — they don't; use shadow variables)
- [Spindle 3.1 manual](https://www.linusakesson.net/software/spindle/v3manual.pdf)
  for the EFO header format and pefchain script semantics
