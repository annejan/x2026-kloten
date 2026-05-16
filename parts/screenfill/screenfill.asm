//==================================================================
// outline-64 — Spindle "screenfill" part (loading screen)
//
// First part loaded from the .d64 by Spindle's boot loader.
// Port of ranzbak's defeest-screenfill: walks a "DEFEEST" string
// over the screen, choosing upper or lower case per cell via a
// rotating bit-mask. Waits ~3 sec, then triggers Spindle's loader
// (jsr $c90) and JMPs into the main demo at $0810.
//
// Lives at $4000 so it never overlaps main code at $0810..$09f9.
//
// Spindle conventions observed:
//   - $01 stays at $35 (CPU sees full RAM)
//   - VIC bank via $dd02 ($3c → bank 0)
//   - leaves Spindle's resident loader at $0c00..$0dff intact
//==================================================================

.const VIC_MEM    = $d018
.const VIC_BORDER = $d020
.const VIC_BG     = $d021
.const COLOUR_RAM = $d800

.const MASK    = $fb           // bit-mask scratch
.const CHARCNT = $02           // position within "DEFEEST" (0..6)
.const SCRPOS  = $03           // 0..255 within current screen page
.const WCNT    = $04           // word counter / mask seed

* = $4000 "ScreenFill"
start:
        sei
        lda #$35
        sta $01

        // VIC bank 0, screen $0400, lower-case chargen at $1800.
        lda #$3c
        sta $dd02
        lda #%00010111
        sta VIC_MEM

        lda #$00                // border black
        sta VIC_BORDER
        lda #$06                // bg blue
        sta VIC_BG

        // Colour RAM → light blue.
        ldx #0
        lda #$0e
!col:   sta COLOUR_RAM+$000,x
        sta COLOUR_RAM+$100,x
        sta COLOUR_RAM+$200,x
        sta COLOUR_RAM+$2e8,x
        inx
        bne !col-

        // Init counters.
        lda #0
        sta WCNT
        sta SCRPOS

loop_outer:
        lda #0
        sta CHARCNT

loop_char:
        // mask = 1 << ((CHARCNT & 7) + 1)
        lda CHARCNT
        and #%00000111
        clc
        adc #1
        tax
        lda #$01
!rol:   asl
        dex
        bne !rol-
        sta MASK

        // upper vs lower decision: (WCNT & mask) ? upper : lower
        lda WCNT
        and MASK
        beq is_lower

        // Upper: emit raw screen code (already upper in screencode_mixed).
        ldx CHARCNT
        lda dtext,x
        jmp emit

is_lower:
        ldx CHARCNT
        lda dtext,x
        cmp #$20                // keep space
        beq emit
        sec
        sbc #$40                // upper → lower in screencode_mixed

emit:
        ldx SCRPOS
scroffset:
        sta $0400,x
        inc SCRPOS
        bne !nowrap+
        // SCRPOS wrapped → advance scroffset to next page.
        inc scroffset+2
        // After page $07 we're past the screen — stop.
        lda scroffset+2
        cmp #$08
        beq end_fill
!nowrap:

        inc CHARCNT
        lda CHARCNT
        cmp #7                  // "DEFEEST" len
        bne loop_char

        inc WCNT
        jmp loop_outer

end_fill:
        // Hold ~3 sec (150 frames at 50Hz).
        ldx #150
hold:
        lda #$ff
!w1:    cmp $d012
        bne !w1-
!w2:    cmp $d012
        beq !w2-
        dex
        bne hold

        // Spindle: load next paragraph (main demo).
        jsr $c90

        // Jump to main demo entry.
        jmp $0810

// "DEFEEST" as upper-case screencodes in screencode_mixed:
// D=$44 E=$45 F=$46 E=$45 E=$45 S=$53 T=$54
dtext:
        .byte $44, $45, $46, $45, $45, $53, $54
