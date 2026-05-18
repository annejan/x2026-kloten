# Spindle 3.1 / pefchain — operational notes

Reference manual:
https://www.linusakesson.net/software/spindle/v3manual.pdf

This doc collects the gotchas we've actually hit, not the full spec.

## The EFO2 header

Every part's `*_efo_header.asm` is built with `-binfile` (raw, no PRG
load-addr prefix) and concatenated in front of the part's `.prg`:

```kickass
.pc = $0000 "EfoHeader"
        .text "EFO2"
        .word $0000           // prepare    (rarely used)
        .word setup           // setup      (per-part init, called once)
        .word interrupt       // interrupt  (per-frame raster IRQ)
        .word $0000           // main       (rarely used)
        .word fadeout         // fadeout    (called when transition fires)
        .word $0000           // cleanup
        .word $0000           // callmusic
        .byte 'P', $XX, $YY   // Owned page range (inclusive both ends)
        ... more 'P' tags as needed ...
        .byte 'I', $XX, $YY   // Inherited page range (data from previous part)
        .byte 'Z', $f4, $f6   // Zero-page bytes used
        .byte 'S'             // I/O safe (interrupts leave $01 at $35)
        .byte $00             // end-of-tags
```

### Tag semantics

- **`'P'` (Page)**: "I own these pages during my part. Pefchain must
  not load any other part's data here while I'm running." Pages are
  contiguous; use multiple `'P'` tags if you own disjoint ranges.
- **`'I'` (Inherit)**: "These pages already contain data from an
  earlier part that I need preserved." Don't claim them as `'P'`
  unless you're the part that originally wrote them.
- **`'Z'` (Zero-page)**: Range of zero-page bytes you touch. The
  inter-part transition condition byte (usually `$F6`) MUST be in
  some part's `'Z'` range for pefchain to poll it.
- **`'S'` (Safe)**: You leave `$01 = $35` during interrupts. Required
  for Spindle's resident loader to work.

## Transition conditions

The `pefchain_script` is a sequence of `<pef-file> <condition>` lines:

```
parts/screenfill/screenfill.pef     06 = 00
parts/intro/intro.pef               f6 = f0
parts/interlude/interlude.pef       f6 = 20
parts/greets/greets.pef             f6 = 20
parts/sinus/sinus.pef               f6 = 30
parts/end/end.pef                   stay
```

Conditions are evaluated continuously while the part runs. When the
condition fires, pefchain calls the part's `fadeout` routine; once
fadeout returns with carry set, pefchain loads the next part.

### Reusing the same byte across parts

We reuse `$F6` for four different transitions (intro → interlude →
greets → sinus → end). This is fine because **each part's setup resets
the byte to a value that doesn't satisfy the next condition**:

- intro's `zp_outro` ticks from `0` to `$F0` (transition: `f6 = f0`)
- interlude's setup resets `$F6 = 0`, then beat counter ticks to `$20`
  (transition: `f6 = 20`)
- greets' setup resets `$F6 = 0`, then beat counter ticks to `$20`
  (transition: `f6 = 20`)
- sinus' setup resets `$F6 = 0`, then frame counter ticks past `$30`
  and stalls; condition `f6 = 30` catches it at the right moment
  (transition: `f6 = 30`)

**If you forget to reset `$F6` in setup**, the prior part's value
satisfies the new condition and pefchain transitions immediately —
the new part flashes for one frame and then we skip to its successor.

## Background loading

While part N runs, Spindle's NMI-driven loader streams part N+1 into
RAM. Pages claimed by part N (`'P'` tags) are off-limits to the
loader. Pages NOT claimed are fair game.

### The load-gap symptom

If the user perceives a noticeable pause at the inter-part transition
(black screen, music dropout), the loader couldn't finish
pre-streaming part N+1 during part N. Causes:

1. **Part N is too short** vs part N+1's compressed size.
2. **Part N claims pages that part N+1 needs**, forcing pefchain to
   split that data into a "post-N" load chunk visible in `./build.sh`
   output as a separate sector entry.

To diagnose: check `./build.sh` output. For each part you'll see chunks
like `0800-5BDC "intro:intro.efo+intro:(drv)": 21469 bytes crunched to
5322`. Multiple chunks for the same part = split (post-load) chunks.

### Mitigations

- Don't claim pages you don't actually need.
- If a small region must be claimed (e.g. screenfill's screen RAM at
  `$0400-$07FF`), accept the small post-load chunk — it loads in
  fractions of a second.
- For LARGE chunks (we hit this with screenfill claiming `$0C-$0F`,
  which split out 3 KB of intro padding), audit whether the next part
  even needs the bytes there. KickAssembler PRGs are contiguous, so
  big gaps in your segment layout end up as zero-padded bytes that
  pefchain dutifully streams from disk.

## The silent-truncate trap

Spindle's older bootloader script (NOT the pefchain script) and some
mkpef internals hardcode segment byte-counts. **If a segment grows
past its declared size, Spindle silently truncates and boot dies to
BASIC `READY.`** — no error message, no warning.

If a recent change makes the demo boot to READY instead of running:
the first suspect is a size mismatch in a script or descriptor.
Re-run `./build.sh` and diff the sector-map output against a
known-good build.

(This used to bite us in the Spindle 2.3 era. Pefchain handles sizes
automatically, so it's less common now, but worth knowing if you ever
poke at the boot stage.)

## Driver overhead

Each `.pef` chunk includes a Spindle "driver" stub appended to your
code. The `./build.sh` sector map shows it as `Driver for '<part>' at
$XXXX`. The driver lives at the end of your owned page range (or just
past it). Sometimes overflows your declared range by a page — check
the build output if memory layout gets tight.

## VIC bank + CIA2 caveat

Spindle's loader uses **CIA2 NMI** for its background streaming. Do
NOT write to `$DC0D` / `$DD0D` (CIA ICR registers) or you'll disable
the loader and break the next transition. Set VIC bank via `$DD02`
(data direction) + `$DD00` (port A), and leave `$DD0D` alone.

Likewise, `$01 = $35` (default I/O+kernal mapping) must be preserved
across IRQs. Declare `'S'` in the EFO header to advertise this.

## Things you can't do (or should think twice about)

- **Take over the entire IRQ chain forever** — pefchain needs to run
  its main loop between part transitions to check the condition. If
  you wedge into an infinite IRQ loop with no exit, the transition
  never fires.
- **Disable interrupts for more than a few cycles** — same reason,
  plus the NMI loader needs to fire.
- **Load big chunks of data into RAM at runtime from your own code**
  — Spindle's loader IS already doing this on your behalf in the
  background. Use the pefchain part-split mechanism instead.
