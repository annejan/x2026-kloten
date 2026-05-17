//==================================================================
// outline-64 — Part 3: credit roll
//
// Loaded after main's outro via `jsr $c90 / jmp $3800`. Overwrites
// main's now-dead bitmap area ($2000-$3F3F): custom 8x8 font goes to
// $3000 (charset RAM in VIC bank 0), code follows at $3800.
//
// Layout:
//   $3000-$37FF  custom font (256 glyphs × 8 bytes, mostly zero;
//                only the chars used by credit_text are populated)
//   $3800-….     end code, IRQs, scroll state, credit text + tables
//
// Visual: 38-column text mode. Credit text scrolls up 1 px / frame
// (yscroll bits 0-2) with a 24-row block-move every 8 frames pulling
// the next line in at row 24. The 8-px side strips (CSEL=0 extended
// border) and top/bottom borders show a rainbow rasterbar via per-
// line $d020 polling in the chained IRQ. Loops on the credit text.
//==================================================================

.const SCREEN     = $0400
.const FONT       = $3000
.const COLRAM     = $d800
.const VIC_CTRL1  = $d011        // DEN, RSEL, BMM, ECM, yscroll bits 0-2
.const VIC_RASTER = $d012
.const SPR_EN     = $d015
.const VIC_CTRL2  = $d016        // RES, MCM, CSEL, xscroll bits 0-2
.const VIC_MEM    = $d018
.const VIC_IRQ    = $d019
.const VIC_IRQEN  = $d01a
.const VIC_BORDER = $d020
.const VIC_BG     = $d021

.const zp_yscroll  = $f7         // current $d011 yscroll value, decrements each frame from 7→0 then wraps
.const zp_text_row = $f8         // index into credit_text (advances on hardware-scroll wrap)
.const zp_frame    = $f9         // free-running frame counter (for bar palette drift)
.const zp_tmp      = $fa
.const zp_fade     = $fb         // fade-in counter, 0..BAR_FADE_DONE, ticks each frame
.const zp_wave     = $fc         // wave-phase LSB for $D016 wobble

.const N_CREDIT_ROWS = 36        // KEEP IN SYNC with the .text blocks below
.const BAR_TOP       = $32       // first display line; bars run BAR_TOP..BAR_BOT
.const BAR_BOT       = $f8       // last bar line
.const BAR_LINES     = BAR_BOT - BAR_TOP   // = 198
.const BAR_REVEAL_RATE = 2       // lines per frame the bars roll in
.const BAR_FADE_DONE  = BAR_LINES / BAR_REVEAL_RATE   // = 99 frames ~2s
.const TEXT_REVEAL    = BAR_FADE_DONE                  // text pops in once bars are fully visible


//==================================================================
// font_data — custom 8×8 charset at $3000. Each char takes 8 bytes
// at offset (char_code × 8). screencode_mixed: lowercase a-z at
// $01-$1A, uppercase A-Z at $41-$5A, digits 0-9 at $30-$39, space
// $20, '.' $2E, ',' $2C, ':' $3A, '!' $21, '-' $2D. We only fill
// the codes credit_text actually uses; everything else stays $00.
//==================================================================
.pc = FONT "Font"

// $00 — unused
        .fill 8, 0

// $01 'a'
        .byte %00000000
        .byte %00000000
        .byte %01111100
        .byte %00000110
        .byte %01111110
        .byte %11000110
        .byte %01111110
        .byte %00000000
// $02 'b'
        .byte %11000000
        .byte %11000000
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %11111100
        .byte %00000000
// $03 'c'
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %11000000
        .byte %11000000
        .byte %11000000
        .byte %01111110
        .byte %00000000
// $04 'd'
        .byte %00000110
        .byte %00000110
        .byte %01111110
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %01111110
        .byte %00000000
// $05 'e'
        .byte %00000000
        .byte %00000000
        .byte %01111100
        .byte %11000110
        .byte %11111110
        .byte %11000000
        .byte %01111110
        .byte %00000000
// $06 'f'
        .byte %00011110
        .byte %00110000
        .byte %01111100
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00000000
// $07 'g'
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %11000110
        .byte %01111110
        .byte %00000110
        .byte %01111100
        .byte %00000000
// $08 'h'
        .byte %11000000
        .byte %11000000
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %00000000
// $09 'i'
        .byte %00011000
        .byte %00000000
        .byte %00111000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00111100
        .byte %00000000
// $0a 'j'
        .byte %00001100
        .byte %00000000
        .byte %00011100
        .byte %00001100
        .byte %00001100
        .byte %01101100
        .byte %00111000
        .byte %00000000
// $0b 'k'
        .byte %11000000
        .byte %11000000
        .byte %11001110
        .byte %11011100
        .byte %11110000
        .byte %11011100
        .byte %11001110
        .byte %00000000
// $0c 'l'
        .byte %00111000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00111100
        .byte %00000000
// $0d 'm'
        .byte %00000000
        .byte %00000000
        .byte %11101100
        .byte %11111110
        .byte %11010110
        .byte %11000110
        .byte %11000110
        .byte %00000000
// $0e 'n'
        .byte %00000000
        .byte %00000000
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %00000000
// $0f 'o'
        .byte %00000000
        .byte %00000000
        .byte %01111100
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $10 'p'
        .byte %00000000
        .byte %00000000
        .byte %11111100
        .byte %11000110
        .byte %11111100
        .byte %11000000
        .byte %11000000
        .byte %00000000
// $11 'q'
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %11000110
        .byte %01111110
        .byte %00000110
        .byte %00000110
        .byte %00000000
// $12 'r'
        .byte %00000000
        .byte %00000000
        .byte %11011100
        .byte %11100110
        .byte %11000000
        .byte %11000000
        .byte %11000000
        .byte %00000000
// $13 's'
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %11000000
        .byte %01111100
        .byte %00000110
        .byte %11111100
        .byte %00000000
// $14 't'
        .byte %00110000
        .byte %00110000
        .byte %11111100
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00011100
        .byte %00000000
// $15 'u'
        .byte %00000000
        .byte %00000000
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %01111110
        .byte %00000000
// $16 'v'
        .byte %00000000
        .byte %00000000
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %01101100
        .byte %00111000
        .byte %00000000
// $17 'w'
        .byte %00000000
        .byte %00000000
        .byte %11000110
        .byte %11000110
        .byte %11010110
        .byte %11111110
        .byte %01101100
        .byte %00000000
// $18 'x'
        .byte %00000000
        .byte %00000000
        .byte %11000110
        .byte %01101100
        .byte %00111000
        .byte %01101100
        .byte %11000110
        .byte %00000000
// $19 'y'
        .byte %00000000
        .byte %00000000
        .byte %11000110
        .byte %11000110
        .byte %01111110
        .byte %00000110
        .byte %01111100
        .byte %00000000
// $1a 'z'
        .byte %00000000
        .byte %00000000
        .byte %11111110
        .byte %00001100
        .byte %00011000
        .byte %00110000
        .byte %11111110
        .byte %00000000

// $1b..$1f — gap to space ($20)
        .fill 8 * (5), 0

// $20 ' '
        .fill 8, 0
// $21 '!'
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00000000
        .byte %00110000
        .byte %00000000

// $22..$2b — unused gap
        .fill 8 * 10, 0

// $2c ','
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00110000
        .byte %00110000
        .byte %01100000
// $2d '-'
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
// $2e '.'
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %01100000
        .byte %01100000
        .byte %00000000

// $2f — unused
        .fill 8, 0

// $30 '0'
        .byte %01111100
        .byte %11000110
        .byte %11001110
        .byte %11010110
        .byte %11100110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $31 '1'
        .byte %00111000
        .byte %01111000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %01111110
        .byte %00000000
// $32 '2'
        .byte %01111100
        .byte %11000110
        .byte %00000110
        .byte %00011100
        .byte %00110000
        .byte %01100000
        .byte %11111110
        .byte %00000000
// $33 '3'
        .byte %01111100
        .byte %11000110
        .byte %00000110
        .byte %00111100
        .byte %00000110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $34 '4'
        .byte %00001100
        .byte %00011100
        .byte %00111100
        .byte %01101100
        .byte %11111110
        .byte %00001100
        .byte %00001100
        .byte %00000000
// $35 '5'
        .byte %11111110
        .byte %11000000
        .byte %11111100
        .byte %00000110
        .byte %00000110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $36 '6'
        .byte %01111100
        .byte %11000110
        .byte %11000000
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $37 '7'
        .byte %11111110
        .byte %00000110
        .byte %00001100
        .byte %00011000
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00000000
// $38 '8'
        .byte %01111100
        .byte %11000110
        .byte %11000110
        .byte %01111100
        .byte %11000110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $39 '9'
        .byte %01111100
        .byte %11000110
        .byte %11000110
        .byte %01111110
        .byte %00000110
        .byte %11000110
        .byte %01111100
        .byte %00000000

// $3a ':'
        .byte %00000000
        .byte %01100000
        .byte %01100000
        .byte %00000000
        .byte %00000000
        .byte %01100000
        .byte %01100000
        .byte %00000000

// $3b..$ff — rest unused, zero fill up to $3800
        .fill (FONT + $800) - *, 0


//==================================================================
// End code at $3800. Entry: start.
//==================================================================
.pc = $3800 "End"

start:
        sei
        lda #$35
        sta $01

        // VIC bank 0 ($3c → $0000-$3FFF).
        lda #$3c
        sta $dd02

        // Screen $0400, charset $3000 → $d018 = (1<<4) | (6<<1) = $1c.
        lda #%00011100
        sta VIC_MEM

        // Text mode, DEN, RSEL, yscroll=7 (will animate). zp_yscroll
        // stores just the yscroll bits (0-7); irq_top OR's #$18 each
        // frame to rebuild CTRL1. Storing the full $1f here would make
        // the first wrap take 32 frames instead of 8 (the bpl-based
        // wrap detect only fires when the saved value goes negative),
        // and the screen would visibly jump every 8 frames until then.
        lda #$1f
        sta VIC_CTRL1
        lda #$07
        sta zp_yscroll
        // 38-column mode (CSEL=0): the 8-px left/right strips become
        // extended border, which the bar IRQ then rainbows.
        lda #$00
        sta VIC_CTRL2

        lda #$00
        sta VIC_BG              // bg black (under text)
        sta VIC_BORDER          // border starts black (per-line bars overwrite)
        sta SPR_EN              // sprites off
        sta $d418               // silence SID (master vol = 0)

        // Clear screen to space ($20) and colour RAM to BLACK ($00) so the
        // text is invisible until the fade-in reveal (reveal_text pops it
        // to $01 once bars are fully rolled in).
        ldx #0
        lda #$20
!cs:    sta SCREEN+$000,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x       // last partial page → $06e8..$07e7
        inx
        bne !cs-
        ldx #0
        lda #$00                // $00 = black → text invisible on black bg
!cc:    sta COLRAM+$000,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$2e8,x
        inx
        bne !cc-

        // Init scroll state, fade counter, and prime row 24.
        lda #0
        sta zp_text_row
        sta zp_frame
        sta zp_fade
        jsr push_next_credit_row

        // --- SID drone: sustained Am chord (A2 + C3 + E3) with filter ---
        // Frequencies from main.asm sid_freq_lo/hi table (PAL).
        // Voice 1: A2, pulse 12.5%
        lda #$52                     // freq lo A2 (main.asm index 33)
        sta $d400
        lda #$07                     // freq hi A2
        sta $d401
        lda #$00
        sta $d402                     // pulse lo
        lda #$08                     // pulse hi = 12.5%
        sta $d403
        lda #$41                     // gate + pulse, hold
        sta $d404
        lda #$08                     // AD: attack=0, decay=8
        sta $d405
        lda #$f0                     // SR: sustain=15, release=0
        sta $d406
        // Voice 2: C3, pulse 25%
        lda #$b4                     // freq lo C3 (main.asm index 36)
        sta $d407
        lda #$08                     // freq hi C3
        sta $d408
        lda #$00
        sta $d409
        lda #$04
        sta $d40a                    // pulse 25%
        lda #$41
        sta $d40b
        lda #$08
        sta $d40c
        lda #$f0
        sta $d40d
        // Voice 3: E3, pulse 25%
        lda #$fc                     // freq lo E3 (main.asm index 40)
        sta $d40e
        lda #$0a                     // freq hi E3
        sta $d40f
        lda #$00
        sta $d410
        lda #$04
        sta $d411
        lda #$41
        sta $d412
        lda #$08
        sta $d413
        lda #$f0
        sta $d414
        // Master volume: fades in with zp_fade (ramped by irq_top each frame).
        // Route V1+V2+V3 through filter (LP mode), start vol=0.
        lda #%00000111              // route voices 1+2+3 to filter
        sta $d417
        lda #$00                    // LP filter mode, vol = 0 (fade in)
        sta $d418
        // Filter cutoff sweeps via zp_frame in irq_top.

        // Raster IRQ chain: irq_top@$00 (yscroll + maybe row-shift),
        // then irq_bars@$32..$f8 for the side rainbow.
        lda #<irq_top
        sta $fffe
        lda #>irq_top
        sta $ffff
        lda #$00
        sta VIC_RASTER
        lda #$01
        sta VIC_IRQEN
        lda #$ff
        sta VIC_IRQ
        cli

forever:
        jmp forever


//==================================================================
// irq_top — fires at raster $00. Tick yscroll down; on wrap, do a
// hardware-scroll row-up and pull a fresh credit line into row 24.
// Then chain to irq_bars at line $32.
//==================================================================
irq_top:
        pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta VIC_IRQ

        inc zp_frame

        // --- Fade-in counter: saturates at BAR_FADE_DONE (99 frames ~2s) ---
        lda zp_fade
        cmp #BAR_FADE_DONE
        beq !fade_done+
        inc zp_fade
        lda zp_fade
        cmp #TEXT_REVEAL
        bne !fade_done+
        jsr reveal_text
!fade_done:

        // --- Bar reveal: grow bar_end by BAR_REVEAL_RATE lines/frame ---
        // Self-modifies the cpy operand in irq_bars so the rainbow rolls
        // down from BAR_TOP toward BAR_BOT. BAR_REVEAL_RATE=2 means we
        // multiply zp_fade by 2 (asl) — at zp_fade=BAR_FADE_DONE=99 the
        // result is 198, +BAR_TOP=50 → 248=BAR_BOT (full reveal).
        lda zp_fade
        asl                     // *2 = lines revealed so far
        clc
        adc #BAR_TOP
        cmp #BAR_BOT
        bcc !bar_ok+
        lda #BAR_BOT
!bar_ok:sta bar_end+1

        // --- Bar palette drift with sine modulation ---
        // zp_frame/2 gives a steady drift; adding a sine term makes the
        // bars breathe up-and-down.
        lda zp_frame
        lsr
        sta zp_tmp              // base drift
        lda zp_frame
        tax
        lda bar_offset_mod,x
        lsr
        clc
        adc zp_tmp
        sta bar_lda+1

        // --- SID: master volume fades in with zp_fade ---
        // Volume 0..$0f. $d418 bit 4 enables low-pass filter — voices
        // are routed to filter via $d417 in setup, so we need LP here
        // for the filter cutoff sweep below to actually be audible.
        lda zp_fade
        lsr
        lsr                     // /4, reaches $0f at fade=60 (~1.2s)
        cmp #$10
        bcc !vol_ok+
        lda #$0f
!vol_ok:ora #$10                // bit 4 = LP filter enable
        sta $d418

        // --- Filter cutoff sweep ---
        lda zp_frame
        lsr
        lsr
        lsr                     // 0..31 slow tick
        and #$07                // $d416 hi cutoff = bits 0-2
        sta $d416
        lda #$20
        sta $d415               // cutoff lo fixed, hi sweeps

        // --- Text wave: $D016 xscroll wobble ---
        // CSEL=0 (38-col), xscroll 0..7 from a sine table.  The entire
        // text area rocks left/right for a gentle DYCP-lite feel.
        lda zp_frame
        lsr                     // slower wave (every 2 frames)
        tax
        lda wave_xscroll,x
        and #$07                // only xscroll bits
        sta VIC_CTRL2

        // --- yscroll handling ---
        lda zp_yscroll
        sec
        sbc #1
        bpl !no_wrap+
        // Wrap path: scroll text rows up by 1, pull next credit line.
        jsr scroll_rows_up
        jsr push_next_credit_row
        lda #7
!no_wrap:
        sta zp_yscroll

        // Compose $d011: DEN=1, RSEL=1, BMM=0, ECM=0 → $18 plus yscroll.
        ora #$18
        sta VIC_CTRL1

        // Chain to bar IRQ.
        lda #<irq_bars
        sta $fffe
        lda #>irq_bars
        sta $ffff
        lda #BAR_TOP
        sta VIC_RASTER

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// irq_bars — fires at line BAR_TOP. Tight per-line $d020 write loop
// from BAR_TOP to BAR_BOT, indexing a 256-byte palette by raster +
// zp_frame so the bars drift downward over time. Chains back to
// irq_top at line $00.
//==================================================================
irq_bars:
        pha
        tya
        pha
        lda #$ff
        sta VIC_IRQ

        // bar_lda+1 (palette base lo byte) was already set in irq_top with
        // sine modulation — no need to redo it here.

        // 17-cy loop: ldy raster (4), lda pal,y (4), sta border (4),
        // cpy end (2), bcc (3) = 17. Fits within badline budget.
        // bar_end is self-modified in irq_top to roll the bars in.
!loop:  ldy VIC_RASTER           // 4
bar_lda:
        lda bar_palette,y        // 4
        sta VIC_BORDER           // 4
bar_end:
        cpy #BAR_BOT             // 2  (self-modified operand)
        bcc !loop-               // 3

        lda #$00
        sta VIC_BORDER           // restore black border for safety

        // Chain back to top.
        lda #<irq_top
        sta $fffe
        lda #>irq_top
        sta $ffff
        lda #$00
        sta VIC_RASTER

        pla
        tay
        pla
        rti


//==================================================================
// reveal_text — one-time blast of colour RAM rows 0-23 from $00 to $01.
// Makes the credit text visible after the bars have finished rolling in.
// Called from irq_top when zp_fade hits TEXT_REVEAL.
// Timing: ~3000 cy (~48 lines) — fits in VBL before text display starts.
//==================================================================
reveal_text:
        ldx #0
        lda #$01
!c0:    sta COLRAM+$000,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        inx
        bne !c0-
        ldx #0
!c1:    sta COLRAM+$300,x
        inx
        cpx #(24*40 - 768)      // 960 - 768 = 192 remaining bytes
        bne !c1-
        // Also reveal row 24 (the incoming credit line) — it was placed
        // with colour $00 by push_next_credit_row during the fade phase.
        ldx #0
!c2:    sta COLRAM + 24*40, x
        inx
        cpx #40
        bne !c2-
        rts


//==================================================================
// scroll_rows_up — shift rows 1..24 of SCREEN up into 0..23. Row 24
// is overwritten immediately after by push_next_credit_row. Done in
// ROW-MAJOR order (full row 0 first, then row 1, …) so each row's
// 40-byte write completes before VIC reads it for display.
//
// Timing (called from irq_top at line $00):
//   - Per-row inner: ldy #39 + 40×(lda/sta/dey/bpl) ≈ 561 cy ≈ 9 lines
//   - Row K destination written by line ~9(K+1)
//   - VIC reads row K at line 50 + 8K
//   - margin = 50 + 8K − (9K + 9) = 41 − K  (positive for K ≤ 23 ✓)
//
// Total ~13.5k cy (~213 lines) so the chained bar IRQ doesn't start
// until ~line $D5 on shift frames — a brief 30-line strip at the
// bottom is the only rainbow on those frames. Acceptable trade-off
// to keep the text itself tear-free.
//==================================================================
scroll_rows_up:
        .for (var r = 0; r < 24; r++) {
            ldy #39
        !l: lda SCREEN + (r+1)*40, y
            sta SCREEN +    r *40, y
            dey
            bpl !l-
        }
        rts


//==================================================================
// push_next_credit_row — copy 40 chars from credit_text[zp_text_row]
// into screen row 24, then advance zp_text_row (wrapping at
// N_CREDIT_ROWS for an infinite loop).
//==================================================================
push_next_credit_row:
        // Write screen RAM row 24 (40 bytes).
        ldx zp_text_row
        lda row_ptr_lo,x
        sta !src+ + 1
        lda row_ptr_hi,x
        sta !src+ + 2
        ldy #39
!src:   lda $1234,y               // self-modified above to credit_text + row*40
        sta SCREEN + 24*40, y
        dey
        bpl !src-

        // Write colour RAM for row 24: $01 (visible) if fade-in is complete,
        // $00 (invisible) during the initial bar roll-in phase.
        lda zp_fade
        cmp #TEXT_REVEAL
        bcs !colour_on+
        lda #$00
        jmp !write_col+
!colour_on:
        lda #$01
!write_col:
        ldy #39
!col:   sta COLRAM + 24*40, y
        dey
        bpl !col-

        inc zp_text_row
        lda zp_text_row
        cmp #N_CREDIT_ROWS
        bcc !ok+
        lda #0                    // wrap → loop credit roll forever
!ok:    sta zp_text_row
        rts


//==================================================================
// bar_palette — 512-byte rainbow indexed by raster line (low byte).
// 16 reps of the 32-entry ramp. The self-modified `bar_lda+1` offset
// (frame/2 + sine/2) can reach ~158, plus y up to 248, lands inside
// 512 cleanly without reading past into wave_xscroll.
//==================================================================
.align 256
bar_palette:
.for (var rep = 0; rep < 16; rep++) {
        .byte $00, $06, $06, $0e, $0e, $03, $03, $01
        .byte $01, $03, $03, $0e, $0e, $06, $06, $00
        .byte $00, $02, $02, $0a, $0a, $07, $07, $01
        .byte $01, $07, $07, $0a, $0a, $02, $02, $00
}

//==================================================================
// wave_xscroll — 256-byte sine for $D016 horizontal wobble.
// CSEL=0 (38-column), xscroll 0..7. The text rocks smoothly left/right.
// Amplitude centred on 3.5 so the rounded range is exactly 0..7 with
// no discontinuity at the peaks (a 4-centred version with `and #$07`
// wrapped 8→0 and visibly jittered).
//==================================================================
.align 256
wave_xscroll:
        .fill 256, round(3.5 + 3.5 * sin(toRadians(i * 360 / 256)))

//==================================================================
// bar_offset_mod — 256-byte sine for modulating the bar palette drift.
// Added to zp_frame/2 so the bar colours breathe up and down.
// Range 0..63, page-aligned for fast LDA abs,X.
//==================================================================
.align 256
bar_offset_mod:
        .fill 256, round(32 + 31 * sin(toRadians(i * 360 / 256)))


//==================================================================
// credit_text — N_CREDIT_ROWS rows × 40 chars each (space-padded
// via the row() macro). Update N_CREDIT_ROWS at the top when adding
// or removing lines. Renders in lowercase via screencode_mixed so
// the font's $01-$1A slots cover everything.
//==================================================================
.encoding "screencode_mixed"

.macro row(s) {
        .text s
        .fill 40 - s.size(), $20
}

credit_text:
        row("                                        ")
        row("                                        ")
        row("                                        ")
        row("              defeest presents          ")
        row("                                        ")
        row("              outline 2026 demo         ")
        row("                                        ")
        row("                                        ")
        row("                                        ")
        row("           code                         ")
        row("              anne jan brouwer          ")
        row("              claude opus 4.7           ")
        row("                                        ")
        row("           music                        ")
        row("              hand-written 3-voice sid  ")
        row("                                        ")
        row("           graphics                     ")
        row("              defeest.nl                ")
        row("                                        ")
        row("           tools                        ")
        row("              kickassembler             ")
        row("              spindle 2.3               ")
        row("              vice x64sc                ")
        row("                                        ")
        row("           greetings                    ")
        row("              outline 2026 crew         ")
        row("              codebase64                ")
        row("              linus akesson             ")
        row("              mads nielsen              ")
        row("                                        ")
        row("                                        ")
        row("              thanks for watching       ")
        row("                                        ")
        row("                                        ")
        row("                                        ")
        row("                                        ")

// Per-row pointer tables — KA evaluates these at assembly time so we
// avoid a runtime row×40 multiply.
row_ptr_lo:
.for (var r = 0; r < N_CREDIT_ROWS; r++) {
        .byte <(credit_text + r * 40)
}
row_ptr_hi:
.for (var r = 0; r < N_CREDIT_ROWS; r++) {
        .byte >(credit_text + r * 40)
}
