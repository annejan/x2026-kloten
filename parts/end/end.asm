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
//   $3800-….     end code, IRQ, scroll state, credit text + tables
//
// Visual: 38-column text mode, sides + top/bottom borders pure black
// to keep focus on the text. Credit text scrolls up 1 px / frame
// (yscroll bits 0-2) with a 24-row block-move every 8 frames pulling
// the next line in at row 24. Colour-RAM rows hold a fixed cool
// gradient (light-blue → cyan → light-green → white → back), so each
// credit line slides UP through the gradient. Section headers ("code",
// "music", …) flash yellow when they first appear at the bottom,
// then dissolve into the gradient as they scroll past — colour RAM
// doesn't shift with the screen content. $D016 xscroll wobbles the
// whole text block left/right and an LP-filtered SID drone underpins
// the roll. Loops the credit text forever.
//
// TODO: per-row vertical sine wobble (FLD-style yscroll per row).
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

.const zp_yscroll  = $f7         // current $d011 yscroll bits (0-7), decrements each frame; wrap triggers scroll_rows_up
.const zp_text_row = $f8         // index into credit_text (advances on hardware-scroll wrap)
.const zp_frame    = $f9         // free-running frame counter (for $D016 wobble + SID filter sweep)
.const zp_tmp      = $fa
.const zp_fade     = $fb         // fade-in counter, 0..FADE_DONE, ticks each frame; drives SID volume + text reveal
.const zp_wrap_pending = $fc     // set non-zero in irq_top when yscroll wraps; consumed later to fire scroll_rows_up

.const N_CREDIT_ROWS = 36        // KEEP IN SYNC with the .text blocks below
.const FADE_DONE     = 99        // fade-in completes after 99 frames (~2 sec @50Hz)
.const TEXT_REVEAL   = FADE_DONE // colour RAM flips from black to the gradient at this fade tick


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
// $07 'g'  — with descender so it doesn't read as a '9'
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %11000110
        .byte %11000110
        .byte %01111110
        .byte %00000110
        .byte %01111100
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
        sta zp_wrap_pending
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

        // --- Fade-in counter: saturates at FADE_DONE (99 frames ~2s) ---
        lda zp_fade
        cmp #FADE_DONE
        beq !fade_done+
        inc zp_fade
        lda zp_fade
        cmp #TEXT_REVEAL
        bne !fade_done+
        jsr reveal_text
!fade_done:

        // --- yscroll: compute first so CTRL1 is stable BEFORE display ---
        // Previously this block ran AFTER scroll_rows_up, so on shift
        // frames CTRL1 got updated ~line 220 (mid-screen). Badlines
        // before the update used the OLD yscroll, after used the NEW;
        // the 0..7-line gap between old-badline-window and new-badline-
        // window left rows stuck on the same char pointer, repeating
        // the row across that strip. Setting CTRL1 here (line ~3)
        // makes badlines consistent for the entire frame.
        lda zp_yscroll
        sec
        sbc #1
        bpl !no_wrap+
        // Wrap: flag scroll_rows_up to run later, reset yscroll to 7.
        ldx #1
        stx zp_wrap_pending
        lda #7
        bne !apply_y+           // bne always taken (A=7)
!no_wrap:
        ldx #0
        stx zp_wrap_pending
!apply_y:
        sta zp_yscroll
        ora #$18                // DEN + RSEL + BMM=0 + ECM=0 + yscroll
        sta VIC_CTRL1

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

        // --- Wrap action: shift screen up + pull next credit line ---
        // Runs AFTER CTRL1 is settled. The scroll_rows_up row-major
        // writes still race the beam (row K written by line ~12+9K,
        // VIC reads row K at line $32+yscroll+8K → margin 22+ for the
        // worst row even with new yscroll=7).
        lda zp_wrap_pending
        beq !skip_wrap+
        jsr scroll_rows_up
        jsr push_next_credit_row
!skip_wrap:

        // Re-arm raster IRQ for line $00 of next frame (we are the only IRQ).
        lda #$00
        sta VIC_RASTER

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// reveal_text — paint colour RAM rows 0-23 with the row_colour
// gradient. Fired once from irq_top when zp_fade hits TEXT_REVEAL.
// Row 24's colour is owned by push_next_credit_row (so each new
// credit line can flash yellow on header rows). Unrolled per-row
// fill races the beam: row K written by line ~6(K+1), VIC reads
// row K colour at line 50+8K → safe margin every row.
//==================================================================
reveal_text:
        .for (var r = 0; r < 24; r++) {
            lda row_colour + r
            ldy #39
        !l: sta COLRAM + r*40, y
            dey
            bpl !l-
        }
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

        // Write colour RAM for row 24. During the fade phase ($00 = text
        // invisible). After fade: $07 yellow if this credit row is a
        // header (title or section), otherwise the bottom gradient
        // colour. As the line scrolls up over the next 8 frames, colour
        // RAM doesn't follow, so the yellow flash dissolves into the
        // gradient — that's the desired header-pop effect.
        lda zp_fade
        cmp #TEXT_REVEAL
        bcc !invisible+
        lda is_header,x           // x still holds zp_text_row from above
        bne !header+
        lda row_colour+24         // body: bottom-row gradient colour
        jmp !write_col+
!header:
        lda #$07                  // header: yellow flash
        jmp !write_col+
!invisible:
        lda #$00
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
// row_colour — 25-entry cool gradient (light-blue → cyan → light-
// green → white → back). reveal_text paints colour RAM rows 0-23
// from this table; push_next_credit_row uses entry 24 as the
// "body" colour for the bottom row (overridden to $07 yellow when
// a header credit line is pushed).
//==================================================================
row_colour:
        .byte $0e, $0e, $0e        // rows  0- 2: light blue
        .byte $03, $03, $03        // rows  3- 5: cyan
        .byte $0d, $0d, $0d        // rows  6- 8: light green
        .byte $0f, $0f, $0f        // rows  9-11: light grey
        .byte $01, $01, $01        // rows 12-14: white (centre highlight)
        .byte $0f, $0f, $0f        // rows 15-17: light grey
        .byte $0d, $0d, $0d        // rows 18-20: light green
        .byte $03, $03, $03        // rows 21-23: cyan
        .byte $0e                  // row  24:    light blue (header-flash falls back to this)

//==================================================================
// is_header — flag per credit_text row: 1 if the row is a title or
// section header (gets a yellow flash when pushed into row 24), 0
// for body lines and blanks. KEEP IN SYNC with credit_text below.
//==================================================================
is_header:
        .byte 0,0,0     // 0..2 blank
        .byte 1         // 3 "defeest presents"
        .byte 0         // 4 blank
        .byte 1         // 5 "outline 2026 demo"
        .byte 0,0,0     // 6..8 blank
        .byte 1         // 9 "code"
        .byte 0,0       // 10..11 names
        .byte 0         // 12 blank
        .byte 1         // 13 "music"
        .byte 0         // 14 body
        .byte 0         // 15 blank
        .byte 1         // 16 "graphics"
        .byte 0         // 17 body
        .byte 0         // 18 blank
        .byte 1         // 19 "tools"
        .byte 0,0,0     // 20..22 body
        .byte 0         // 23 blank
        .byte 1         // 24 "greetings"
        .byte 0,0,0,0   // 25..28 body
        .byte 0,0       // 29..30 blank
        .byte 1         // 31 "thanks for watching"
        .byte 0,0,0,0   // 32..35 blank tail


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
