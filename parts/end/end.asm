//==================================================================
// outline-64 — Part 3: credit roll
//
// Loaded after main's outro via `jsr $200 / jmp $3800`. Overwrites
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

.const N_CREDIT_ROWS = 68        // KEEP IN SYNC with the .text blocks below
.const FADE_DONE     = 99        // fade-in completes after 99 frames (~2 sec @50Hz)
.const TEXT_REVEAL   = FADE_DONE // colour RAM flips from black to the gradient at this fade tick
.const SCROLL_TICK_MASK = $03    // tick yscroll every (mask+1) frames — $03 = every 4 frames
                                 //   → 32 frames/row × 36 rows ≈ 23 sec per full credit cycle.
                                 //   Bump to $07 for ~46 sec, drop to $01 for ~11 sec.

// ----- end music tables / state -----
.const zp_mu_step    = $f4       // music step 0..127 (lead pattern index; chord = step & 31)
.const zp_mu_frame   = $f3       // within-step frame counter, 0..END_STEP_FRAMES-1
.const END_STEP_FRAMES = 24      // 4× slower than intro's 6 — chord lasts ~3.8s, full progression ~15s
.const NOTE_REST     = $FF

// Music data lives in intro.asm's $1000-$125D segment which is still
// resident in RAM when end loads (end's chunk is $3000+). Pefchain
// inherits intro's music pages via 'I',$10,$12 in interlude's EFO
// header — they survive through interlude and into end. Addresses
// copied from parts/intro/intro.sym — bump these if intro's Music
// segment layout shifts.
.const MAIN_SID_FREQ_LO    = $1000
.const MAIN_SID_FREQ_HI    = $103C
.const MAIN_CHORD_PER_STEP = $1078
.const MAIN_ARP_NOTES      = $1098
.const MAIN_LEAD_PATTERN   = $10C8


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

// $2f '/'
        .byte %00000110
        .byte %00001100
        .byte %00011000
        .byte %00110000
        .byte %01100000
        .byte %11000000
        .byte %00000000
        .byte %00000000

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

// $3b..$40 — unused gap before capitals
        .fill 8 * ($41 - $3b), 0

// Capital glyphs — all uppercase A-Z that credit_text needs.
// All other uppercase slots stay zero (invisible chars).
// Custom Å glyph at $5B for "Linus Åkesson".

// $41 'A'
        .byte %00111000
        .byte %01101100
        .byte %11000110
        .byte %11000110
        .byte %11111110
        .byte %11000110
        .byte %11000110
        .byte %00000000
// $42 'B'
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %11111100
        .byte %00000000
// $43 'C'
        .byte %01111110
        .byte %11000110
        .byte %11000000
        .byte %11000000
        .byte %11000000
        .byte %11000110
        .byte %01111110
        .byte %00000000
// $44 — unused (D)
        .fill 8, 0
// $45 'E'
        .byte %11111110
        .byte %11000000
        .byte %11000000
        .byte %11111100
        .byte %11000000
        .byte %11000000
        .byte %11111110
        .byte %00000000
// $46 'F'
        .byte %11111110
        .byte %11000000
        .byte %11000000
        .byte %11111100
        .byte %11000000
        .byte %11000000
        .byte %11000000
        .byte %00000000
// $47..$48 — unused (G-H)
        .fill 8 * 2, 0
// $49 'I'
        .byte %01111110
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %01111110
        .byte %00000000
// $4a — unused (J)
        .fill 8, 0
// $4b 'K'
        .byte %11000110
        .byte %11001100
        .byte %11011000
        .byte %11110000
        .byte %11011000
        .byte %11001100
        .byte %11000110
        .byte %00000000
// $4c 'L'
        .byte %11000000
        .byte %11000000
        .byte %11000000
        .byte %11000000
        .byte %11000000
        .byte %11000000
        .byte %11111110
        .byte %00000000
// $4d 'M'
        .byte %11000110
        .byte %11101110
        .byte %11111110
        .byte %11010110
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %00000000
// $4e 'N'
        .byte %11000110
        .byte %11100110
        .byte %11110110
        .byte %11011110
        .byte %11001110
        .byte %11000110
        .byte %11000110
        .byte %00000000
// $4f..$51 — unused (O-Q)
        .fill 8 * 3, 0
// $52 'R'
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %11111100
        .byte %11011000
        .byte %11001100
        .byte %11000110
        .byte %00000000
// $53 'S'
        .byte %01111110
        .byte %11000000
        .byte %11000000
        .byte %01111100
        .byte %00000110
        .byte %00000110
        .byte %11111100
        .byte %00000000
// $54 'T'
        .byte %11111110
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00000000
// $55..$57 — unused (U-W)
        .fill 8 * 3, 0
// $58 'X' (needed for "X2026")
        .byte %11000011
        .byte %01100110
        .byte %00111100
        .byte %00011000
        .byte %00111100
        .byte %01100110
        .byte %11000011
        .byte %00000000
// $59..$5a — unused (Y-Z)
        .fill 8 * 2, 0
// $5b 'Å' (A with ring, custom glyph)
        .byte %00011000
        .byte %00100100
        .byte %00011000
        .byte %00111000
        .byte %01101100
        .byte %11000110
        .byte %11111110
        .byte %11000110
// $5c..$ff — rest unused, zero fill up to $3800
        .fill (FONT + $800) - *, 0


//==================================================================
// End code at $3800. Entry: start.
//==================================================================
.pc = $3800 "End"

// === Spindle 3.1 effect lifecycle ===
// setup:     called once with interrupts disabled, $01 already $35.
//            Sets up VIC, music, scroll state.
// interrupt: called every raster IRQ (vector installed by pefchain
//            from EFO header). Runs the per-frame scroll + music tick.
// (no main/fadeout/cleanup — credit roll loops forever via "stay")

setup:
        // VIC bank 0 ($3c → $0000-$3FFF). pefchain leaves $01=$35.
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

        // --- SID: slow meandering chord/lead progression ---
        // intro.asm leaves its music tables resident at $1000-$125D
        // after the end-part load (end writes $3000+ only).
        // end_music_init sets pad-flavoured ADSR + LP filter;
        // end_music_play (called from interrupt) reads intro's
        // chord_per_step / arp_notes / lead_pattern / sid_freq tables
        // at a quarter the main tempo.
        jsr end_music_init

        // Raster IRQ at line $00. Pefchain installs $fffe to point at
        // `interrupt:` from the EFO header, and enables raster IRQ in
        // its early-setup, so we just set the line.
        lda #$00
        sta VIC_RASTER
        rts


//==================================================================
// interrupt — fires at raster $00. Tick yscroll down; on wrap, do a
// hardware-scroll row-up and pull a fresh credit line into row 24.
// Vector installed by pefchain from the EFO header.
//==================================================================
interrupt:
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

        // --- yscroll: tick on every (SCROLL_TICK_MASK+1)th frame. ---
        // CTRL1 is always written before display so badlines stay
        // stable for the entire frame; the SCROLL_TICK_MASK gate just
        // controls how often we DEC yscroll (slows the credit roll).
        ldx #0
        stx zp_wrap_pending     // default no wrap this frame
        lda zp_frame
        and #SCROLL_TICK_MASK
        bne !skip_tick+
        lda zp_yscroll
        sec
        sbc #1
        bpl !y_ok+
        // wrap
        ldx #1
        stx zp_wrap_pending
        lda #7
!y_ok:  sta zp_yscroll
!skip_tick:
        lda zp_yscroll
        ora #$18                // DEN + RSEL + BMM=0 + ECM=0 + yscroll
        sta VIC_CTRL1

        // --- SID: slow chord/melody progression (volume + voices) ---
        jsr end_music_play

        // --- Text wave: $D016 xscroll wobble ---
        // CSEL=0 (38-col), xscroll 0..7 from a sine table.
        lda zp_frame
        lsr                     // slower wave (every 2 frames)
        tax
        lda wave_xscroll,x
        and #$07                // only xscroll bits
        sta VIC_CTRL2

        // --- Wrap action: shift screen up + pull next credit line ---
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
// end_music_init — soft pad sound, LP filter, all 3 voices routed.
// V1/V2 triangle for warm pad, V3 pulse for arp shimmer.
//==================================================================
end_music_init:
        // Clear SID
        ldx #$1c
        lda #0
!c:     sta $d400,x
        dex
        bpl !c-

        // V1 (bass pad): triangle, slow attack, long release
        lda #$71                  // attack=7 (~120ms), decay=1
        sta $d405
        lda #$fa                  // sustain=15, release=10 (~750ms)
        sta $d406

        // V2 (lead pad): triangle, slow attack
        lda #$51                  // attack=5, decay=1
        sta $d40c
        lda #$f9                  // sustain=15, release=9
        sta $d40d

        // V3 (arp): pulse 25%, quick attack
        lda #$00
        sta $d410                 // pulse lo
        lda #$04
        sta $d411                 // pulse hi (~25%)
        lda #$11                  // attack=1, decay=1
        sta $d413
        lda #$f8                  // sustain=15, release=8
        sta $d414

        // Filter: all 3 voices routed, low resonance
        lda #%00000111
        sta $d417
        // Cutoff mid-range; static (no sweep needed for pad)
        lda #$00
        sta $d415                 // cutoff lo
        lda #$20
        sta $d416                 // cutoff hi (~mid)

        // Master vol = 0 (fade-in via irq_top's zp_fade), LP enabled
        lda #$10
        sta $d418

        // Reset music step counters
        lda #0
        sta zp_mu_step
        sta zp_mu_frame
        rts


//==================================================================
// end_music_play — called once per frame from irq_top. Plays a slow
// meandering version of main's chord progression + lead melody.
//
// - Master volume tracks zp_fade (0 → $0f over the first ~1.2s).
// - V3 arp: cycles through the current chord's 4 notes, changing
//   every 4 frames inside each step (so 6 arp swaps per step).
// - V1 bass: chord root, re-triggered each step (every END_STEP_FRAMES
//   frames). Long release lets it bleed into the next note for pad.
// - V2 lead: lead_pattern[mu_step], re-triggered each step. NOTE_REST
//   in the pattern releases the gate so longer rests sound natural.
//==================================================================
end_music_play:
        // --- master volume fade-in ---
        lda zp_fade
        lsr
        lsr                       // /4, reaches $0f at fade=60 (~1.2s)
        cmp #$10
        bcc !vol_ok+
        lda #$0f
!vol_ok:ora #$10                  // bit 4 = LP filter on
        sta $d418

        // --- V3 arp shimmer: PWM + gentle filter cutoff sweep ---
        // PWM affects only V3 (V1/V2 are triangle wave). The pulse hi
        // nibble walks 4..11 over a 5.12s sine cycle for a gentle phaser
        // tone on the arp.  Filter cutoff cycles 90° out of phase across
        // a narrow $20..$58 band so the pad "breathes" without losing
        // its soft character.
        ldx zp_frame
        lda wave_xscroll,x        // 0..7
        clc
        adc #$04                  // 4..11
        and #$0f
        sta $d411                 // V3 pulse hi nibble

        txa
        clc
        adc #$40                  // 90° phase offset
        tax
        lda wave_xscroll,x        // 0..7
        asl
        asl
        asl                       // *8 → 0..56
        clc
        adc #$20                  // baseline → $20..$58
        sta $d416                 // filter cutoff hi

        // --- V3 arp: change freq every 4 frames within step ---
        lda zp_mu_frame
        and #$03
        bne !no_arp+

        // chord_idx = chord_per_step[mu_step & 31]
        lda zp_mu_step
        and #$1f
        tax
        lda MAIN_CHORD_PER_STEP,x
        asl
        asl                       // chord_idx * 4 (= arp group base)
        sta zp_tmp

        // arp_idx = (mu_frame / 4) & 3
        lda zp_mu_frame
        lsr
        lsr
        and #$03
        clc
        adc zp_tmp                // arp group base + arp index
        tax
        lda MAIN_ARP_NOTES,x      // note number
        tay
        lda MAIN_SID_FREQ_LO,y
        sta $d40e
        lda MAIN_SID_FREQ_HI,y
        sta $d40f
        lda #$41                  // pulse + gate (idempotent re-arm)
        sta $d412
!no_arp:

        // --- step boundary ---
        inc zp_mu_frame
        lda zp_mu_frame
        cmp #END_STEP_FRAMES
        bne !done+
        lda #0
        sta zp_mu_frame
        inc zp_mu_step
        lda zp_mu_step
        and #$7f                  // wrap at 128 (lead pattern length)
        sta zp_mu_step

        // --- V1 bass: chord root ---
        and #$1f                  // chord index
        tax
        lda MAIN_CHORD_PER_STEP,x
        asl
        asl                       // chord*4
        tax
        lda MAIN_ARP_NOTES,x      // root note (first arp entry of chord)
        tay
        lda MAIN_SID_FREQ_LO,y
        sta $d400
        lda MAIN_SID_FREQ_HI,y
        sta $d401
        lda #$10                  // triangle, gate off
        sta $d404
        lda #$11                  // triangle, gate on (re-trigger)
        sta $d404

        // --- V2 lead: lead_pattern[mu_step] (or rest) ---
        ldx zp_mu_step
        lda MAIN_LEAD_PATTERN,x
        cmp #NOTE_REST
        beq !v2_rest+
        tay
        lda MAIN_SID_FREQ_LO,y
        sta $d407
        lda MAIN_SID_FREQ_HI,y
        sta $d408
        lda #$10
        sta $d40b
        lda #$11
        sta $d40b
        jmp !done+
!v2_rest:
        lda #$10                  // triangle, gate off → release tail
        sta $d40b
!done:
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
        .byte 0,0,0         //  0..2  blank
        .byte 1             //  3     you were watching
        .byte 0             //  4     blank
        .byte 1             //  5     Kloot and
        .byte 0             //  6     the Breadbin
        .byte 0             //  7     blank
        .byte 0             //  8     by deFEEST
        .byte 0             //  9     for X2026
        .byte 0             // 10     blank
        .byte 1             // 11     started at outline
        .byte 0,0           // 12..13 three weeks later / this happened
        .byte 0             // 14     blank
        .byte 1             // 15     code
        .byte 0,0,0,0       // 16..19 four code credits
        .byte 0             // 20     blank
        .byte 1             // 21     music
        .byte 0,0,0         // 22..24 composed/by Anus/with help
        .byte 0             // 25     blank
        .byte 1             // 26     graphics
        .byte 0,0           // 27..28 defeest.nl / hand pixeled with love
        .byte 0             // 29     blank
        .byte 1             // 30     tools
        .byte 0,0,0,0,0     // 31..35 five tools
        .byte 0             // 36     blank
        .byte 1             // 37     documentation
        .byte 0,0,0,0       // 38..41 codebase / spindle / every demo / before this
        .byte 0             // 42     blank
        .byte 1             // 43     greetings
        .byte 0,0,0,0,0     // 44..48 five greet lines
        .byte 0             // 49     blank
        .byte 1             // 50     thanks
        .byte 0,0           // 51..52 dutch lines
        .byte 0             // 53     blank
        .byte 1             // 54     and one last thought
        .byte 0,0,0         // 55..57 forty years / breadbin / and so do we
        .byte 0             // 58     blank
        .byte 0,0,0         // 59..61 thank you / from anus / see you
        .byte 0,0,0,0,0,0   // 62..67 blank tail


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
        row("              you were watching         ")
        row("                                        ")
        row("           Kloot and                    ")
        row("              the Breadbin              ")
        row("                                        ")
        row("              by deFEEST                ")
        row("               for X2026                ")
        row("                                        ")
        row("           started at outline           ")
        row("            three weeks later           ")
        row("              this happened             ")
        row("                                        ")
        row("           code                         ")
        row("              Kloot/deFEEST            ")
        row("              Anus/deFEEST              ")
        row("              Ranzbak/deFEEST           ")
        row("              Cinder/deFEEST            ")
        row("                                        ")
        row("           music                        ")
        row("              composed and arranged     ")
        row("              by Anus                   ")
        row("              with help from Kloot AI   ")
        row("                                        ")
        row("           graphics                     ")
        row("              defeest.nl                ")
        row("              hand pixeled with love    ")
        row("                                        ")
        row("           tools                        ")
        row("              claude code               ")
        row("              opencode                  ")
        row("              kickassembler             ")
        row("              spindle 3.1               ")
        row("              vice-mcp                  ")
        row("                                        ")
        row("           documentation                ")
        row("              codebase.c64.org          ")
        row("              spindle v3 manual         ")
        row("              every demo that came      ")
        row("              before this one           ")
        row("                                        ")
        row("           greetings                    ")
        row("              outline 2026 crew         ")
        // "Linus Åkesson" — manually assembled because screencode_mixed
        // doesn't know Å. $5b is the custom Å glyph in the font.
        .text "              Linus "
        .byte $5b
        .text "kesson             "
        row("              Mads Nielsen              ")
        row("              everyone keeping the      ")
        row("              breadbin singing          ")
        row("                                        ")
        row("           thanks                       ")
        row("              kloot voor de fouten      ")
        row("              en meer slechte ideeen    ")
        row("                                        ")
        row("           and one last thought         ")
        row("              the breadbin              ")
        row("              has been waiting          ")
        row("              for forty years           ")
        row("              kloot finally             ")
        row("              got me here               ")
        row("                                        ")
        row("              thank you for watching    ")
        row("              from anus and kloot       ")
        row("              see you at evoke")
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
