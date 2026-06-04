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
  We do this in screenfill, interlude, hush, end.

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

### CPU view — per-part (current as of 2026-05-21)

| Range          | screenfill | intro      | interlude | hush     | greets    | coda      | end       |
|----------------|------------|------------|-----------|-----------|-----------|-----------|-----------|
| `$0200-$03FF`  | Spindle    | Spindle    | Spindle   | Spindle   | Spindle   | Spindle   | Spindle   |
| `$0400-$07FF`  | screen RAM | bitmap colour info | screen + plasma | screen (DEFEEST) | bitmap colour attrs (koala c1+c2) | title screen | screen + credits |
| `$0800-$0BFF`  | —          | code + IRQs + sprite shapes | code + tables | code + tables | DYCP sprite font (A-Z + blank + hyphen, 2 KB total) | code + state + tier tables | — |
| `$0C00-$0CFF`  | —          | (free)     | code+     | code (tail) | sprite font (cont.) | code (cont.) + ping-pong state + starfield init data | — |
| `$0D00-$0DFF`  | —          | —          | code+     | —         | sprite font (cont.) | code (cont.) + title text | — |
| `$0E00-$0EFF`  | —          | —          | code (interlude) | — | sprite font (cont.) | char-layer state + cyc/bord/flash tabs | — |
| `$0F00-$0FFF`  | —          | —          | —         | —         | sprite font (cont.) | sin_tab   | —         |
| `$1000-$125D`  | —          | **resident music tables + `my_music_play` (drum_state $12BC / drum_offset $12BD) — inherited by interlude / greets / coda; end uses its own player** ||||||
| `$1300-$1FFF`  | —          | compact logo_rows | —    | —         | —         | —         | —         |
| `$2000-$27FF`  | —          | logo bitmap (multicolour) | — | —    | koala bitmap (320×200 MCM) | Kloot-star TR shapes (24 frames) | — |
| `$2800-$2BFF`  | —          | (logo bitmap continues) | — | —     | koala bitmap (cont.) | Kloot-star TL shapes (cont.) | — |
| `$2C00-$31FF`  | —          | (logo bitmap continues) | — | —     | koala bitmap (cont.) | Kloot-star BL shapes (24 frames) | — |
| `$3200-$37FF`  | —          | (logo bitmap continues) | — | —     | koala bitmap (cont.) | Kloot-star BR shapes (24 frames) | — |
| `$3800-$3F3F`  | —          | (logo bitmap continues) | — | —     | koala bitmap (cont.) | —         | end font + code |
| `$4000-$47FF`  | —          | rainbow palette + sine + bounce tables | — | — | — | — | — |
| `$4C00-$53FF`  | —          | chargen-ROM copy (for scroll) | — | — | — | — | — |
| `$5400-$5BBC`  | —          | bitmap scroller + scroll text + extra sprite shape | — | — | — | — | — |
| `$8000-$85FF`  | —          | —          | —         | —         | code + IRQ + DYCP tables | —     | —         |
| `$8700-$8901`  | —          | —          | —         | —         | scroll message + settle_text | — | — |
| `$8902-$90FF`  | —          | —          | —         | —         | sprite-font glyph data (built at assembly time) | — | — |
| `$9800-$9BE7`  | —          | —          | —         | —         | koala screen-RAM buffer (CPU-copied to $0400 at setup) | — | — |
| `$9C00-$9FE8`  | —          | —          | —         | —         | koala colour-RAM buffer + bg byte (CPU-copied to $D800 at setup) | — | — |
| `$C000-$CAFF`  | code + dist_table + ripple palette + char_table | — | — | — | — | — | — |

EFO `'P'` claims as of today:

| Part       | Page claims                       |
|------------|-----------------------------------|
| screenfill | `$C0-$CA`                         |
| intro      | `$04-$5B`, `$10-$12`              |
| interlude  | `$08-$0E`                         |
| hush      | `$08-$0D`                         |
| greets     | `$08-$0F`, `$20-$3F`, `$80-$9F`   |
| coda       | `$08-$0F`, `$20-$37`              |
| end        | `$30-$44`                         |

Greets has the biggest claim now — sprite font at `$08-$0F` (2 KB),
koala bitmap at `$20-$3F` (8 KB), code + message + font_data + koala
screen/colour buffers at `$80-$9F` (8 KB). Total ~18 KB of greets data
needs to load before the part starts, which is why the longest blank-
filler gap in the demo sits between hush and greets (~11 s of
pefchain-managed loading masked by black-screen blank effects that
still call music via the `'M' + bit !0` mechanism).

Coda reuses the same `$0800` pages hush and greets claimed earlier
in the chain — those parts are long gone by the time coda loads, so
the bytes are free to repurpose. Coda also claims `$30-$37` which
overlaps with end's `$30-$44`; end runs strictly after coda, so
pefchain defers ~2 KB of end's payload to a post-coda load chunk
(visible as ~0.5 s gap at the coda → end transition).

The Kloot-star shapes don't live in coda's `.prg` (which would force
a contiguous KA PRG spanning the `$0E00-$1FFF` zero-padding gap and
collide with intro's inherited music tables at `$1000-$125D`).
Instead `parts/coda/kloot_star_{tr,tl,bl,br}.bin` are each passed to
`mkpef` as separate data files (`,2000`, `,2600`, `,2c00`, `,3200`)
in `build.sh`. Each 1.5 KB chunk becomes its own pefchain payload
entry alongside coda's main `.efo`.

**Coda byte-budget note** (updated 2026-06-04): coda's tables are no
longer `.align 256`d — `col_tab` was dropped entirely (the demoscene
char layer's `cyc_tab`/`bord_tab`/`flash_ramp` + state took its place),
and `sin_tab` (256 B, the only big table left) now packs straight after
the code. `sin_tab` MUST still end before `$1000` or it stomps the
inherited music tables; coda currently ends at `$0FFE` — 1 byte of
slack. If you grow coda's code, watch `parts/coda/coda.sym` for
`sin_tab` creeping toward `$0F00+` — that's the symptom (the `.errorif`
on `sin_tab + 256 > $1000` is the hard backstop).

### Zero-page

| Byte | Used for | When |
|------|----------|------|
| `$02-$08` | screenfill state (CHARCNT, SCRPOS, WCNT, PHASE, HOLDCNT, RADIUS, RFRAME) | screenfill |
| `$F4-$F8` | Spindle loader (do not touch) | always |
| `$F4` | beat phase | interlude, greets |
| `$F5` | filter cutoff / scratch | interlude, hush |
| **`$F6`** | **inter-part transition condition byte** — every part either reaches a specific value here to trigger the next part, or its setup resets it to start counting | always |
| **`$F9`, `$FA`** | **clobbered by intro's `my_music_play` on every JSR** — zp_tmp / zp_msb in intro's namespace. Any part that calls `$119E` (interlude, hush, greets) MUST NOT park persistent state here. | every JSR `$119E` |
| `$F7` | zp_tmp (hush), echo / scroll counter (intro) | hush, intro |
| `$F8` | beat counter / scroll tick / kick state | varies per part (NOT used by hush) |
| `$FB`, `$FC` | hush zp_line ($FB), zp_frame ($FC) | hush |
| `$FB-$FE` | intro text pointers / smooth scroll / frame counter | intro, end |

### Why bytes are placed where they are (concrete examples)

- **`drum_state` lives at `$12BC`** (`drum_offset` at `$12BD`, inside intro's music segment)
  rather than zero-page, because every part that calls
  `INTRO_MUSIC_PLAY` at `$119E` sees the same address. Putting it in
  intro's `'I',$10,$12`-protected pages means interlude / hush /
  greets / coda can all read and write it without needing their own
  zp declaration.

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

- **greets' sprite font moved to `$0800-$0FFF`** (was `$2000-$27FF`
  in earlier text-mode-only versions). Reason: greets is now in
  multi-colour bitmap mode with the koala backdrop at `$2000-$3F3F`,
  so the sprite font needed to relocate out of that region. Sprite
  pointer values shifted from `$80-$9F` to `$20-$3F` to match.
  `ptr_lookup` was updated to map A-Z → `$20+(c-$41)`.

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

When pefchain loads interlude / hush / greets, it preserves the
contents of `$10-$12` from the previous load. So intro's music
tables — set up at `$1000-$125D` during intro's `my_music_init` —
remain in RAM forever. Each later part can call `jsr $119E`
(`my_music_play`) and the chord progression + lead + arp + drums
keep going without interruption.

This is why removing the `vol_out` subtraction in `my_music_play`
(see [`sound-arc.md`](./sound-arc.md)) was so important: a single
change to the shared routine affected every part that inherited it.

## ⚠️ The "claim every page" rule

The single nastiest bug in the project's history: hush once shipped
with `'P', $08, $08` declaring ownership of only one page, but its
code + sine_tab + col_tab + bg_tab actually spanned `$0800-$0CE7`
(five pages). Pefchain saw `$09-$0C` as unclaimed and **put its
driver wait-loop there**, overwriting hush's data tables. Two
catastrophic consequences:

1. `irq_sine` reading `col_tab,y` got CPU opcodes (`$A5`/`$F6`/`$C9`
   /`$30`/`$D0`/`$FA` — the wait-loop's `LDA $F6 / CMP #$30 / BNE`)
   interpreted as VIC colours. Screen showed wild garbage stripes
   that LOOKED like a feature.
2. `irq_top`'s write of `$30` to `$F6` to trigger the transition
   actually wrote to the same MEMORY holding the wait-loop code,
   NOT to `$F6` itself. Pefchain's polling never saw the trigger.
   Hush ran forever.

**Always declare every page your code + tables occupy.** Build with
`java -jar kickass/KickAss.jar parts/<x>/<x>.asm` and check the
Memory Map output:

```
Default-segment:
  $0800-$0949 Hush
  $0A00-$0AFF SineTab
  $0B00-$0BC7 ColTab
  $0C00-$0CC7 BgTab
```

Every range must be inside a `'P'` tag in the EFO header. For
hush that means `'P', $08, $0C` (or two tags if disjoint).

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
