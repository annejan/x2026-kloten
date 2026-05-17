# outline26-claude-c64

A C64 demo for the Outline 2026 demoparty, written together with Claude.
KickAssembler 6510, tested on VICE x64sc (PAL).

## What's in the demo

- **Open top/bottom borders** via the canonical HCL polling trick (`$d011` 24/25-row toggle in IRQs at line `$f9` and `$01`).
- **Multicolour bitmap "deFEEST" logo** mid-screen (160×200 Koala, encoded from a PNG by `tools/png_to_koala.py`). Wipes in column-by-column from the left via `reveal_column`, then floats on a flexible-line-distance bounce.
- **FLD logo bounce** — anchor-style "late write" pattern at line `$3B`. Per-frame `K = bounce_total[frame]` writes increment `$D011`'s yscroll after VIC's cycle-14 check, so each line's badline check sees the previous write and fires a spurious badline. Smooth 0..28 px bounce, 3× sine frequency.
- **Fixed bitmap scroller** at the very top, bitmap row 0 (lines `$33..$3A`). Below the open border, above the FLD trigger at `$3B` — so the scroll stays put while the logo bounces below. Mixed-case chargen, **zig-zag scroll** (even pixel rows shift left, odd rows shift right), 1 px/frame via 40-cell ROL/ROR chains.
- **Rainbow rasterbars** wrapping the logo. The bar IRQ at line `$80` polls `$d012` and writes both `$d021` (background, behind the bitmap's transparent pixels) and `$d020` (border / side stripes) per scanline from a page-aligned 512-byte palette. 21-cy tight loop fits within the bad-line CPU budget.
- **Eight X+Y-expanded "koorballen" sprites** bouncing on sine paths — three in the open top border, three in the display (Y range 90..200, clear of the FLD zone), two in the open bottom border. Sprites 0-2 are disabled during VBL to hide their Y+256 wrap-around duplicates.
- **Custom 3-voice SID music** — bass pulse, lead pulse, sustained arp over a 32-step Am-Em-F-G chord progression with a 128-step lead melody.
- **Sequenced intro** driven by `zp_intro` saturating frame counter: phase 0 logo wipe-reveal → phase 1 (`T_BARS=40`) bars in → phase 2 (`T_BALLS=120`) balls in → phase 3 (`T_SCROLLER=200`) scroller in. Music master volume ramps from `$00` to `$0f`, and SID voices gate in on the same boundaries (V1 bass at `T_BARS`, V2 lead at `T_BALLS`, V3 arp at `T_SCROLLER`).

50 Hz PAL, locked.

## Build / run

You need:

- **KickAssembler** (jar in `kickass/KickAss.jar`, [download from theweb.dk](http://theweb.dk/KickAssembler/))
- **VICE** with `x64sc` (`zypper in vice` on openSUSE)
- **xa65** for Spindle (`zypper in xa` on openSUSE)
- **Spindle v2.3** — first run `./build.sh` will fail with hints; build the `spin` tool via:
  ```
  curl -L https://hd0.linusakesson.net/files/spindle-2.3.tgz | tar xz
  cd spindle-2.3/spindle && make
  ```
- Java for the assembler

Build the multi-part disk and run:

```
./build.sh        # produces outline-64.d64
./run-disk.sh     # autostarts the disk in x64sc
```

## Multi-part layout (Spindle)

| Part | Path | Contents |
| ---- | ---- | -------- |
| 1    | `parts/screenfill/screenfill.asm` | Loading screen at `$4000` — "DEFEEST" pattern, holds ~3 sec, then `jsr $c90` + `jmp $0810` |
| 2    | `parts/main/main.asm`             | The bouncebars demo — adapted as Spindle part 2 |

Spindle's resident loader sits at `$0c00-$0dff` (+ scratch `$0e00-$0eff` and zero-page `$f4-$f7` during loads). The main demo keeps clear of that range — bitmap screen RAM moved to `$0400`.

## Main-demo memory layout (VIC bank 0)

| Range          | Contents                                       |
| -------------- | ---------------------------------------------- |
| `$0400-$07e7`  | Bitmap-mode screen RAM (colour info)           |
| `$07f8-$07ff`  | Sprite pointers                                |
| `$0810-$09f9`  | Main code + IRQs (entry point: `$0810`)        |
| `$0b00-$0b3f`  | Sprite shape data (block `$2c`)                |
| `$0c00-$0dff`  | **reserved for Spindle's resident loader**     |
| `$1000-$125d`  | Hand-written 3-voice SID player + patterns     |
| `$2000-$3f3f`  | Logo bitmap (multicolour, 8000 bytes)          |
| `$4000-$46ff`  | Page-aligned tables (palette, sines, bounce)   |
| `$4c00-$53ff`  | Chargen-ROM copy (mixed-case font for scroll)  |
| `$5400-$5dc3`  | Bitmap scroll renderer + scroll text + sprite shape |

> **Trap to remember:** VIC sees the chargen ROM at `$1000-$1fff` in bank 0, *not* RAM. Sprite shape data placed there is invisible to VIC — VIC reads chargen glyphs as sprite data. Keep sprite blocks outside that window.

## Tools

- `tools/png_to_koala.py` — convert a PNG to a 4-colour C64 multicolour bitmap (`defeest.kla`). Uses a fixed slot palette (black/blue/yellow/white) so every cell has the same 4 colours — works for logos with a small palette.
- `vicemon.py` — stdlib VICE binary-monitor client (originated in the Umbra C64 project). Launch VICE with `-binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502` then `python3 vicemon.py read 0xADDR LEN`, `regs`, `resume`.

## Credits

- Music: hand-written 3-voice SID jam (bass + lead + arp)
- Logo: defeest.nl
- Assembly: Anne Jan Brouwer with Claude (Anthropic) Opus 4.7
