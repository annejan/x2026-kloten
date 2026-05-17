//==================================================================
// outline-64 — Part 2.7: greets (DYCP scroller — first iteration)
//
// 8 X-expanded sprites carrying one glyph each in a 24×21 mono
// sprite font. First pass: static "boxes" so we can verify the
// part loads + renders + transitions. Real font + scroll + DYCP
// sine wobble come in follow-up iterations.
//
// Memory:
//   - $8000-$83FF  code + state + tables
//   - $2000-$23FF  sprite font shapes (16 glyphs × 64 B = 1 KB).
//                  Overwrites intro's bitmap area, which is unused
//                  once we're past intro.
//   - $07F8-$07FF  sprite pointers (default for screen at $0400)
//
// Transition:
//   - Inherits $f6 counter from interlude (was $20 there). We reset
//     it to 0 in setup, tick once per beat (24 fr ≈ 0.48 s), and the
//     pefchain script transitions to end at f6 = $20 (~15 s).
//==================================================================

.const VIC_CTRL1   = $d011
.const VIC_RASTER  = $d012
.const SPR_EN      = $d015
.const VIC_CTRL2   = $d016
.const VIC_MEM     = $d018
.const VIC_IRQ     = $d019
.const SPR_YEXP    = $d017
.const SPR_PRIO    = $d01b
.const SPR_MC      = $d01c
.const SPR_XEXP    = $d01d
.const VIC_BORDER  = $d020
.const VIC_BG      = $d021
.const SPR_COL     = $d027         // sprite 0 colour, +i for sprite i

.const SPR_PTR_BASE = $07F8        // 8 sprite pointer bytes in screen RAM
.const SPRITE_SHAPE = $2000        // VIC bank 0; pointer value = $80

.const INTRO_MUSIC_PLAY = $119e

// 8 sprites at fixed X stride. X-expanded → ~48 px wide each.
.const SPR_BASE_X  = 24
.const SPR_STRIDE  = 36
.const SPR_Y_BASE  = 120

// Beat pacing — same 24 fr/beat tempo as interlude
.const BEAT_PERIOD = 24

// DYCP wobble — phase shift between adjacent sprites (in sine-table
// steps). 32 = a full quarter-wave across the 8-sprite row.
.const DYCP_PHASE_STEP = 24

// Zero-page
.const zp_beat_phase  = $f4
.const zp_wobble_pos  = $f5        // global phase, advances each frame
.const zp_beat_count  = $f6        // script transitions on f6 = $20


* = $8000 "Greets"

setup:
        // Black bg + border. Default text-mode setup; we use sprites.
        lda #$3c
        sta $dd02
        lda #%00010100             // screen $0400, chargen $1000
        sta VIC_MEM
        lda #$1b                   // text mode, DEN, RSEL, yscroll=3
        sta VIC_CTRL1
        lda #$08                   // CSEL, mono
        sta VIC_CTRL2
        lda #$00
        sta VIC_BORDER
        sta VIC_BG

        // Clear screen RAM to space so no residual text/char garbage
        // shows behind the sprites.
        ldx #0
        lda #$20                    // space
!clr:   sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne !clr-

        // SID: full vol, no filter mode (interlude left LP mode +
        // routing on for its sweep — clear that here so greets gets
        // a clean dry mix). V1 (bass) is NOT muted: greets is the
        // payoff — bass returns, layered with lead + arp.
        lda #$0f
        sta $d418
        lda #$00
        sta $d417                  // no voices routed to filter
        sta $d416                  // cutoff 0 (filter unused)

        // Copy 16-glyph font into sprite shape area ($2000-$23FF).
        jsr copy_font

        // Sprite pointers: sprite i → glyph i (placeholder mapping).
        // Pointer value = shape_addr / 64. $2000 / 64 = $80.
        ldx #0
!psp:   txa
        clc
        adc #$80
        sta SPR_PTR_BASE,x
        inx
        cpx #8
        bne !psp-

        // X-expand all 8, no Y-expand, mono, sprites in front.
        lda #$FF
        sta SPR_XEXP
        lda #$00
        sta SPR_YEXP
        sta SPR_MC
        sta SPR_PRIO

        // Sprite colours: steady cyan for now.
        ldx #0
        lda #$03
!pcol:  sta SPR_COL,x
        inx
        cpx #8
        bne !pcol-

        // Sprite positions: X from sprite_x_table, Y all SPR_Y_BASE.
        // Sprite N's X reg lives at $D000 + N*2, Y at $D001 + N*2.
        ldx #0
        ldy #0                     // X-reg / Y-reg offset (= N*2)
!ppos:  lda sprite_x_table,x
        sta $d000,y
        lda #SPR_Y_BASE
        sta $d001,y
        inx
        iny
        iny
        cpx #8
        bne !ppos-

        // Clear hi-bit X register (all sprites within X < 256 for now).
        lda #$00
        sta $d010

        // Enable all 8 sprites.
        lda #$ff
        sta SPR_EN

        // Reset beat counter ($f6 was $20 from interlude — pefchain
        // already consumed that condition. Restart from 0.)
        lda #0
        sta zp_beat_phase
        sta zp_beat_count

        // Raster IRQ at top of frame.
        lda #$00
        sta VIC_RASTER
        rts


//==================================================================
// interrupt — per-frame. Continue intro's music, tick beat counter.
//==================================================================
interrupt:
        pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta VIC_IRQ

        jsr INTRO_MUSIC_PLAY
        // V1 (bass) plays naturally now — no per-frame mute. Re-assert
        // master vol $0F since my_music_play wrote vol_in there.
        lda #$0f
        sta $d418

        // Beat counter → drives pefchain transition condition
        inc zp_beat_phase
        lda zp_beat_phase
        cmp #BEAT_PERIOD
        bcc !no_beat+
        lda #0
        sta zp_beat_phase
        inc zp_beat_count
!no_beat:
        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// fadeout — pefchain calls when the script condition fires (f6 = $20).
//==================================================================
fadeout:
        sec
        rts


//==================================================================
// copy_font — bulk copy of font_data into sprite shape area at $2000.
// 1024 bytes (16 glyphs × 64 B).
//==================================================================
copy_font:
        ldx #0
!cp:    lda font_data+$000,x
        sta SPRITE_SHAPE+$000,x
        lda font_data+$100,x
        sta SPRITE_SHAPE+$100,x
        lda font_data+$200,x
        sta SPRITE_SHAPE+$200,x
        lda font_data+$300,x
        sta SPRITE_SHAPE+$300,x
        inx
        bne !cp-
        rts


//==================================================================
// sprite_x_table — pre-computed X positions for sprites 0..7.
// Sprite 0 at SPR_BASE_X, then stride SPR_STRIDE pixels per sprite.
//==================================================================
sprite_x_table:
.for (var i = 0; i < 8; i++) {
        .byte SPR_BASE_X + i * SPR_STRIDE
}


//==================================================================
// font_data — 16 glyphs × 64 bytes. First pass: each glyph is a
// hollow box outline (top + bottom rows solid, sides solid). All
// glyphs identical for now — refine to a real font next iteration.
// 21 rows × 3 bytes = 63 bytes used per glyph + 1 byte padding.
//==================================================================
font_data:
.for (var g = 0; g < 16; g++) {
    .for (var row = 0; row < 21; row++) {
        .if (row == 0 || row == 20) {
                .byte $ff, $ff, $ff
        } else {
                .byte $80, $00, $01
        }
    }
    .byte $00                       // padding to 64 B
}
