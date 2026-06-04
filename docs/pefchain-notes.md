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

## The auto-inserted leading "blank" — and the screenfill prepare

Pefchain auto-inserts a blank effect ahead of the very first part
(it lives at `$0800-$08AB` in our build — see the sector map
`./build.sh` prints). The blank's auto-generated setup writes:

```
lda #$00
sta $D011        ; DEN=0, display disabled
sta $D020        ; border black
sta $D015        ; sprites off
lda #$F0
sta $D012        ; raster line for the blank's IRQ
rts
```

That `$D011 = $00` is what produces the ~270 ms black flash between
BASIC's `RUN` and screenfill's setup — DEN off means the entire
visible area shows border colour, which is also black. It runs
while screenfill loads from disk in the background.

There is no Spindle flag to suppress this. The blank's setup is
emitted directly by `pefchain.c` (`create_blank_effect`).

What we DO is add a `prepare` routine to screenfill that restores
BASIC's defaults (`$D011=$1B`, `$D018=$15` ROM uppercase chargen,
`$D020=$0E` light-blue border, `$D021=$06` blue bg, sprites off).
Prepare runs in main context after the load completes and BEFORE
the switchover to screenfill's setup — so the BASIC text + light-
blue/blue colour scheme reappears at the latest possible moment
before the radial fill kicks in.

The handbook warns "do not write VIC registers in prepare" because
prepare races with the previous part's IRQ. That warning doesn't
apply here: the leading blank's IRQ only calls the music player
and never touches VIC. Safe.

If you ever add a part that's loaded onto a memory range overlapping
its predecessor's, pefchain will insert another blank between them
and the same load gap will appear in the middle of the demo. The
fix is the same pattern: give the affected next-part a `prepare`
that paints whatever it wants visible during the load — provided
the inserted blank's IRQ truly does nothing visible.

## Transition conditions

The `pefchain_script` is a sequence of `<pef-file> <condition>` lines:

```
parts/screenfill/screenfill.pef     06 = 00
parts/intro/intro.pef               f6 = f0
parts/interlude/interlude.pef       f6 = 30
parts/greets/greets.pef             f6 = 82
parts/coda/coda.pef                 f6 = 30
parts/end/end.pef                   stay
```

Conditions are evaluated continuously while the part runs. When the
condition fires, pefchain calls the part's `fadeout` routine; once
fadeout returns with carry set, pefchain loads the next part.

### Reusing the same byte across parts

We reuse `$F6` for the transitions (intro → interlude → greets → coda
→ end). This is fine because **each part's setup resets the byte to a
value that doesn't satisfy the next condition**:

- intro's `zp_outro` ticks from `0` to `$F0` (transition: `f6 = f0`)
- interlude runs plasma + the SPARKED drop, then the merged fire phase
  (formerly the separate `hush` part — merged in `0d8dca5`); its IRQ
  drives `$F6` to `$30` when the fire phase completes (transition:
  `f6 = 30`)
- greets is scroll-driven: when the scroller reaches the `DEFEEST`
  settle text, `$F6` is forced to `SETTLE_BEAT` and natural beat-ticking
  runs it up to `$82` (transition: `f6 = 82`)
- coda's setup resets `$F6 = 0`, then its IRQ sets `$F6 = $30` once the
  half-rate frame counter (`$FC` + a code-RAM high byte) ≥
  `N_FRAMES = 400` (~16 s). Same trigger value as interlude, fine
  because they're not adjacent. Transition: `f6 = 30`.

#### Watch out: `$F9` and `$FA` are clobbered every `my_music_play`

Intro's `my_music_play` (still resident, called from every later part
via `$119E`) uses `$F9` and `$FA` as its internal scratch bytes
(`zp_tmp`, `zp_msb`). Every JSR overwrites them. Hush originally
parked its frame counter at `$F9` and the part never transitioned —
each increment was silently wiped on the next music call. The fix:
move it to `$FC`, which intro's namespace doesn't touch. **For any
later part that calls `my_music_play`, treat `$F9`/`$FA` as live
clobber zones across the JSR; pick a different zp for state that
must survive frames.**

**If you forget to reset `$F6` in setup**, the prior part's value
satisfies the new condition and pefchain transitions immediately —
the new part flashes for one frame and then we skip to its successor.

## ⚠️ Claim ALL pages your part actually spans

The single nastiest bug we've shipped — and one of the few that
silently produces "demo runs forever in a part without transitioning."

**Hush's EFO header originally declared `'P', $08, $08` — only ONE
page.** But the actual code + sine_tab + col_tab + bg_tab span
`$0800-$0CE7` (five pages). Pefchain saw `$09-$0C` as unclaimed and
put its driver wait-loop there. The wait-loop opcodes happened to
overlap hush's per-scanline colour tables, so:

- `irq_sine` reading `col_tab,y` got `$A5` (LDA), `$F6` (operand),
  `$C9` (CMP), `$30` (immediate), `$D0` (BNE), `$FA` (offset). These
  bytes interpreted as VIC colours produced WILD multicolour stripes
  on the DEFEEST text — looked like a feature, was actually opcodes.
- More importantly, `irq_top` writing `$30` to `$F6` to trigger the
  transition actually wrote to the SAME memory holding the wait-loop
  code, NOT to `$F6` itself. So pefchain's `LDA $F6 / CMP #$30 / BNE`
  loop never saw the transition value. Hush ran forever.

**Always declare every page your code + tables actually occupy.**
Run `./build.sh` and read the `Default-segment:` lines — every
range needs to be covered by some `'P'` tag (or inherited via `'I'`).

```kickass
// hush claims all 5 pages it actually uses
.byte 'P', $08, $0C
```

If you're unsure, run `java -jar kickass/KickAss.jar parts/<x>/<x>.asm`
and look at the Memory Map output. Any segment NOT covered by a `'P'`
or `'I'` tag is fair game for pefchain's driver and will be silently
overwritten.

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
- **For data far from your main segment, use mkpef's multi-file mode.**
  `mkpef` accepts trailing `<file>,<addr>` arguments after the `.efo`
  and treats each as its own payload entry — no zero-padding gap. Coda
  uses this for its Kloot-star sprite shapes at `$2800-$2BFF` while
  its code lives at `$0800-$0AFF`; without it, KA's contiguous PRG
  would have dragged a 7 KB zero-padded chunk that collided with
  greets' `$20-$27` pages during background loading. Build.sh's
  `build_part` accepts trailing `<file>,<addr>` args and forwards
  them; see the coda invocation:
  ```
  build_part parts/coda coda  kloot_star.bin,2800
  ```
  Symptom that signals you need this: pefchain spams `Warning:
  Inserting blank filler because '...' and 'YOUR_PART' share pages
  X-Y` and eventually errors out with `pefchain: Increase MAXEFFECTS!`.

### MAXEFFECTS bump (2026-05-21)

Stock pefchain ships with `MAXEFFECTS = 96` in `spindle-3.1/src/
pefchain.c`. The outline-64 build exceeds that because greets
claims a lot of pages (`$08-$0F` sprite font + `$20-$3F` koala
bitmap + `$80-$9F` code/buffers) and pefchain inserts a `blank`
filler effect per page-gap during the background load — well past
96 in our case.

**To rebuild pefchain with a higher limit:**

```bash
cd spindle-3.1/src
# Edit pefchain.c: change `#define MAXEFFECTS 96` to 512
make pefchain                  # may need `./mkheader commonsetup.bin > commonsetup.h` first
cp pefchain ../prebuilt-binaries/linux-x86_64/pefchain
```

This is a LOCAL build-tool patch; `spindle-3.1/` is gitignored so the
rebuilt binary doesn't ride along in the repo. If a fresh checkout
fails with `Increase MAXEFFECTS!`, apply this bump.

## VIC quirk to clear in every part's setup

`$D011` bit 7 is the high bit of the raster-compare register (NOT
the current-raster-hi which is what the READ returns). If a previous
part left bit 7 set (typically true if it ran any IRQ chain past
line 255), and your setup writes `$D012 = 49` for a raster IRQ at
line 49, the actual compare value is `$131 = 305` — well past visible
screen. The IRQ never fires at the line you wanted.

Standard fix in every part's setup:

```kickass
lda VIC_CTRL1
and #%01111111            // clear bit 7 = compare-raster-hi
sta VIC_CTRL1
lda #FIRST_LINE - 1
sta VIC_RASTER
lda #$01
sta VIC_IRQEN
```

The read-modify-write looks expensive but matters: just writing
`$1B` blindly would also work, BUT only if no per-frame state in
`$D011` (like `BMM` for bitmap mode) is supposed to persist.

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
