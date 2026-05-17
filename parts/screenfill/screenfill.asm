//==================================================================
// outline-64 — Spindle "screenfill" part (loading screen)
//
// First part loaded from the .d64 by Spindle's boot loader.
// Port of ranzbak's defeest-screenfill: walks a "DEFEEST" string
// over the screen, choosing upper or lower case per cell via a
// rotating bit-mask. After the fill, runs a water-ripple colour
// cycle for ~3 sec — concentric rings expand from screen centre —
// then triggers Spindle's loader (jsr $c90) and JMPs into the main
// demo at $0810.
//
// Lives at $c000 — well above main demo's $0810..$5dc3 range so the
// screenfill code SURVIVES the `jsr $c90` that loads main into RAM.
// Crucial: $4000-$46ff is main's Tables segment; an earlier $4000
// placement got the screenfill code overwritten mid-load and `jmp
// $0810` was replaced by palette bytes → CPU ran into garbage.
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
.const PHASE   = $05           // ripple phase (incremented per frame)
.const HOLDCNT = $06           // remaining ripple frames

* = $c000 "ScreenFill"
start:
        sei
        lda #$35
        sta $01

        // VIC bank 0, screen $0400, lower-case chargen at $1800.
        lda #$3c
        sta $dd02
        lda #%00010111
        sta VIC_MEM

        lda #$06                // border + bg both blue — solid background
        sta VIC_BORDER          // so the ripple reads edge-to-edge with no frame.
        sta VIC_BG

        // Colour RAM → light blue. (Ripple overwrites it during hold.)
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


//==================================================================
// end_fill — run the water-ripple effect for ~3 sec then load main.
//
// Per frame:
//   1. Vsync on line $ff.
//   2. Build current_pal[i] = ripple_palette[(i - PHASE) & 15]
//      (16 entries — recompute once per frame, then index by dist).
//   3. For every colour-RAM byte, write current_pal[dist_table[c]].
//      dist_table is a precomputed 1024-byte table of scaled radial
//      distances from screen centre, range 0..15. Increasing PHASE
//      walks the palette inward in cell-space which → rings appear
//      to EXPAND outward (drop-on-water look).
//
// Cost per frame: ~18.5k cy (4×256 inner loop + 16-entry palette
// build). Just fits a PAL frame; effectively updates at ~50 Hz.
//==================================================================
end_fill:
        lda #0
        sta PHASE
        lda #150
        sta HOLDCNT

hold:
        // Vsync (wait for line $ff to pass).
        lda #$ff
!w1:    cmp $d012
        bne !w1-
!w2:    cmp $d012
        beq !w2-

        // current_pal[i] = ripple_palette[(i - PHASE) & 15]
        ldy #0
!bp:    tya
        sec
        sbc PHASE
        and #$0f
        tax
        lda ripple_palette,x
        sta current_pal,y
        iny
        cpy #16
        bne !bp-

        // Splatter rings across all four colour-RAM pages.
        ldy #0
!r1:    ldx dist_table+$000,y
        lda current_pal,x
        sta $d800,y
        iny
        bne !r1-
!r2:    ldx dist_table+$100,y
        lda current_pal,x
        sta $d900,y
        iny
        bne !r2-
!r3:    ldx dist_table+$200,y
        lda current_pal,x
        sta $da00,y
        iny
        bne !r3-
!r4:    ldx dist_table+$300,y
        lda current_pal,x
        sta $db00,y
        iny
        bne !r4-

        // ----- staged fadeout -----
        // On new-VIC there is NO luminance step between $06 (blue, lum
        // 63) and $00 (black, lum 0) — $0B (dark grey, lum 79) is
        // actually BRIGHTER than blue, so any $06→$0B→$00 ramp inverts
        // perceived darkness mid-fade. COLFADE v2 also fades $06 → $00
        // directly. So bg+border just snap to black during the ripple.
        lda HOLDCNT
        cmp #85
        bne !nb+
        lda #$00
        sta VIC_BG
        sta VIC_BORDER
!nb:
        // Text palette fade: every 8 frames step ripple_palette through
        // a hue-stable fadetab (each path monotonically darker:
        // $01→$0F→$0C→$0B→$00 and $03→$0E→$06→$00).
        lda HOLDCNT
        cmp #85
        bcs !nofade+
        and #$07
        bne !nofade+
        ldy #15
!fl:    ldx ripple_palette,y
        lda fadetab,x
        sta ripple_palette,y
        dey
        bpl !fl-
!nofade:

        inc PHASE
        dec HOLDCNT
        beq !hold_done+
        jmp hold
!hold_done:

        // Spindle: load next paragraph (main demo).
        jsr $c90

        // Jump to main demo entry.
        jmp $0810

// Hue-preserving fade-to-black table — only the colours that appear in
// ripple_palette (plus their intermediate steps) walk toward black.
// Paths: $01→$0F→$0C→$0B→$00, $03→$0E→$06→$00, $0E→$06→$00, $06→$00.
fadetab:
        .byte $00, $0f, $00, $0e, $00, $00, $00, $00
        .byte $00, $00, $00, $00, $0b, $00, $06, $0c

// "DEFEEST" as upper-case screencodes in screencode_mixed:
// D=$44 E=$45 F=$46 E=$45 E=$45 S=$53 T=$54
dtext:
        .byte $44, $45, $46, $45, $45, $53, $54


//==================================================================
// Ripple data tables — placed at $c200 so they live well above the
// code and don't conflict with Spindle's $0c00 loader or main's
// $0400-$5dxx layout. They're only used BEFORE jsr $c90, so they
// don't need to survive the load.
//==================================================================

* = $c200 "RippleDist"
// dist_table[c] = scaled radial distance from screen centre (20,12),
// mapped to 0..15 so it indexes a 16-entry palette without seams.
// 1024 bytes — last 24 are past row 24 and never displayed.
dist_table:
.for (var i = 0; i < 1024; i++) {
    .var y  = floor(i / 40)
    .var x  = i - y * 40
    .var dx = x - 20
    .var dy = y - 12
    .var d  = round(sqrt(dx*dx + dy*dy) * 15 / 23)
    .byte d & $0f
}

* = $c600 "RipplePal"
// Symmetric palette: black → blue → cyan → white → cyan → blue → black.
// As PHASE advances, each ring index rotates through this ramp, so
// the same brightness band appears to expand outward = water wave.
ripple_palette:
        .byte $00, $06, $06, $0e, $0e, $03, $03, $01
        .byte $01, $03, $03, $0e, $0e, $06, $06, $00

current_pal:
        .fill 16, 0
