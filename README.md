# outline26-claude-c64

A C64 demo for the Outline 2026 demoparty, written together with Claude.
KickAssembler 6510, tested on VICE x64sc (PAL).

## What's in the demo

- **Open top/bottom borders** via the canonical HCL polling trick (`$d011` 24/25-row toggle in IRQs at line `$f9` and `$01`).
- **Multicolour bitmap "de FEEST" logo** in the centre (160×200 Koala, encoded from a PNG by `tools/png_to_koala.py`).
- **Rainbow rasterbars** wrapping the logo. The bar IRQ at line `$50` polls `$d012` and writes both `$d021` (background, behind the bitmap's transparent pixels) and `$d020` (border / side stripes) per scanline from a page-aligned 512-byte palette. 21-cy tight loop fits within the bad-line CPU budget.
- **Eight Y-expanded "koorballen" sprites** bouncing on sine paths — three in the open top border, three in the display, two in the open bottom border. Sprites 0-2 are disabled during VBL to hide their Y+256 wrap-around duplicates.
- **SID music** (`Nightshift.sid` by Agemixer) loaded via KickAssembler's `LoadSid()` and played from `irq_open` after the time-critical sprite re-enable and motion work.

50 Hz PAL, locked.

## Build / run

You need:

- **KickAssembler** (jar in `kickass/KickAss.jar`, [download from theweb.dk](http://theweb.dk/KickAssembler/))
- **VICE** with `x64sc` (`zypper in vice` on openSUSE)
- Java for the assembler

Assemble and run:

```
java -jar kickass/KickAss.jar rasterbars.asm
x64sc rasterbars.prg
```

## Memory layout (VIC bank 0)

| Range          | Contents                              |
| -------------- | ------------------------------------- |
| `$0801-$080c`  | BASIC SYS stub (`BasicUpstart2`)      |
| `$0810-$0999`  | Main code + IRQs                      |
| `$0a00-$0a3f`  | Sprite shape data (block `$28`)       |
| `$0c00-$0fe7`  | Bitmap-mode screen RAM (colour info)  |
| `$0ff8-$0fff`  | Sprite pointers                       |
| `$1000-$1d77`  | Nightshift.sid                        |
| `$2000-$3f3f`  | Logo bitmap (multicolour, 8000 bytes) |
| `$4000-$4acc`  | Page-aligned tables (palette, sines)  |

> **Trap to remember:** VIC sees the chargen ROM at `$1000-$1fff` in bank 0, *not* RAM. Sprite shape data placed there is invisible to VIC — VIC reads chargen glyphs as sprite data. Keep sprite blocks outside that window.

## Tools

- `tools/png_to_koala.py` — convert a PNG to a 4-colour C64 multicolour bitmap (`defeest.kla`). Uses a fixed slot palette (black/blue/yellow/white) so every cell has the same 4 colours — works for logos with a small palette.
- `vicemon.py` — stdlib VICE binary-monitor client (originated in the Umbra C64 project). Launch VICE with `-binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502` then `python3 vicemon.py read 0xADDR LEN`, `regs`, `resume`.

## Credits

- Music: *Nightshift* by Ari Yliaho (Agemixer), 2001
- Logo: defeest.nl
- Assembly: Anne Jan Brouwer with Claude (Anthropic) Opus 4.7
