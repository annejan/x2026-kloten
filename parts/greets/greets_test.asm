//==================================================================
// greets_test.asm — standalone test harness for greets
//
// Build:  java -jar ../../kickass/KickAss.jar greets_test.asm
// Run:    x64sc -autostart greets_test.prg
//==================================================================

.var chargen = LoadBinary("chargen.bin")

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
.const SPR_COL     = $d027

.const SPR_PTR_BASE = $07F8
.const SPRITE_SHAPE = $2000

.const INTRO_MUSIC_PLAY = $119e

.const SPR_BASE_X  = 24
.const SPR_STRIDE  = 36
.const SPR_Y_BASE  = 130

.const BEAT_PERIOD     = 24
.const DYCP_PHASE_STEP = 32
.const SCROLL_DELAY    = 6

.const zp_beat_phase  = $f4
.const zp_wobble_pos  = $f5
.const zp_beat_count  = $f6
.const zp_scroll_pos  = $f7
.const zp_scroll_tick = $f8
.const zp_kick_state  = $f9
.const zp_kick_freq   = $fa

//==================================================================
// BASIC loader: SYS 2064 ($0810)
//==================================================================
* = $0801 "BASIC loader"
BasicUpstart($0810)

//==================================================================
// Boot code at $0810
//==================================================================
* = $0810 "Boot"

        sei

        // VIC bank 0 ($0000-$3FFF) — make sure CIA2 port A bits 0-1 outputs
        lda $dd02
        ora #$03
        sta $dd02
        lda $dd00
        ora #$03                  // bits 0-1 = 11 → VIC bank 0
        sta $dd00

        // disable CIA IRQs
        lda #$7f
        sta $dc0d
        sta $dd0d

        // clear any pending VIC IRQ
        lda VIC_IRQ
        sta VIC_IRQ

        // call greets setup
        jsr setup

        // set up raster IRQ at line 50
        lda #50
        sta VIC_RASTER
        lda #$1b
        sta VIC_CTRL1

        lda #$01
        sta $d01a

        lda #<irq_stub
        sta $0314
        lda #>irq_stub
        sta $0315

        cli

!loop:  jmp !loop-


irq_stub:
        pha
        txa
        pha
        tya
        pha

        lda #$ff
        sta VIC_IRQ

        jsr interrupt

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// Music stub at $119E
//==================================================================
* = $119E "Music stub"
        rts


//==================================================================
// Greets code at $8000
//==================================================================
* = $8000 "Greets"

setup:
        lda #$3c
        sta $dd02
        lda #%00010100
        sta VIC_MEM
        lda #$1b
        sta VIC_CTRL1
        lda #$08
        sta VIC_CTRL2
        lda #$00
        sta VIC_BORDER
        sta VIC_BG

        ldx #0
        lda #$20
!clr:   sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne !clr-

        lda #$1f
        sta $d418
        lda #$00
        sta $d404

        jsr copy_font

        lda #0
        sta zp_scroll_pos
        jsr update_sprite_ptrs

        lda #$FF
        sta SPR_XEXP
        lda #$00
        sta SPR_YEXP
        sta SPR_MC
        sta SPR_PRIO

        ldx #0
!pcol:
        txa
        and #3
        tay
        lda sprite_cols,y
        sta SPR_COL,x
        inx
        cpx #8
        bne !pcol-

        ldx #0
        ldy #0
!ppos:  lda sprite_x_table,x
        sta $d000,y
        lda #SPR_Y_BASE
        sta $d001,y
        inx
        iny
        iny
        cpx #8
        bne !ppos-

        lda #$00
        sta $d010

        lda #$ff
        sta SPR_EN

        lda #0
        sta zp_beat_phase
        sta zp_beat_count
        sta zp_scroll_tick
        sta zp_kick_state
        sta zp_kick_freq

        lda #$00
        sta VIC_RASTER
        rts


interrupt:
        pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta VIC_IRQ

        jsr INTRO_MUSIC_PLAY

        lda #$0f
        sta $d418

        inc zp_beat_phase
        lda zp_beat_phase
        cmp #BEAT_PERIOD
        bcc !no_beat+
        lda #0
        sta zp_beat_phase
        inc zp_beat_count
!no_beat:

        inc zp_wobble_pos

        ldx #0
!dycp:
        txa
        clc
        adc zp_wobble_pos
        tay
        lda sine_table,y
        clc
        adc #SPR_Y_BASE
        sta $d001,x
        inx
        cpx #8
        bne !dycp-

        ldx zp_scroll_tick
        inx
        cpx #SCROLL_DELAY
        bcc !no_scroll+
        ldx #0
        inc zp_scroll_pos
        jsr update_sprite_ptrs
!no_scroll:
        stx zp_scroll_tick

        pla
        tay
        pla
        tax
        pla
        rti


fadeout:
        sec
        rts


update_sprite_ptrs:
        ldx #0
!lp:    txa
        clc
        adc zp_scroll_pos
        tay
        lda message,y
        tay
        lda ptr_lookup,y
        sta SPR_PTR_BASE,x
        inx
        cpx #8
        bne !lp-
        rts


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
        lda font_data+$400,x
        sta SPRITE_SHAPE+$400,x
        lda font_data+$500,x
        sta SPRITE_SHAPE+$500,x
        lda font_data+$600,x
        sta SPRITE_SHAPE+$600,x
        lda font_data+$700,x
        sta SPRITE_SHAPE+$700,x
        inx
        bne !cp-
        rts


ptr_lookup:
.for (var i = 0; i < 256; i++) {
        .if (i >= $41 && i <= $5A) { .byte $80 + i - $41 }
        .if (i < $41 || i > $5A) { .byte $9A }
}

sprite_x_table:
.for (var i = 0; i < 8; i++) {
        .byte SPR_BASE_X + i * SPR_STRIDE
}

sprite_cols:
.byte $03, $04, $05, $06

sine_table:
.for (var i = 0; i < 256; i++) {
        .byte floor(4 * sin(i * 2 * PI / 256) + 0.5)
}

message:
.text "      GREETZ TO ALL LUNCHBASED LIFEFORMS   "
.text "      IN ROTTERDAM AND BEYOND               "
.text "      NO BREAD WAS HARMED DURING            "
.text "      THIS PRODUCTION                       "
.text "      EXCEPT THE PINDKAAS SANDWICH          "
.text "      LEFT IN DRIVE 1541                    "
.text "      KLOTEN MET DE BROODTROMMEL            "
.text "      IS THE OFFICIAL LUNCHTIME             "
.text "      RELEASE OF X2026                      "
.text "      GREETINGS                             "
.text "      SMEERKAAS   BROODJEKAAS.EXE           "
.text "      TUPPERWARE DIVISION   ROTTERDAM       "
.text "      ALL HAIL THE HAM PIRATES              "
.text "      XENON   SILICON LTD   SCS TRC         "
.text "      FOCUS   FAIRLIGHT   REFLEX            "
.text "      BONZAI   GENESIS PROJECT   EXTEND     "
.text "      TRSI   OXYRON   BYTERAPERS            "
.text "      CENSOR DESIGN   CHANNEL FOUR          "
.text "      PADUA   ATLANTIS   ELYSIUM            "
.text "      EXCESS   TRIAD   NEOPLASIA            "
.text "      THE DREAMS   RADWAR   PERFORMERS      "
.text "      VANDALISM NEWS   NAH-KOLOR   LOTEK    "
.text "      CHOCOTROPHY   PHOBOS TEAM             "
.text "      SIDMASTERS   THE WEEKENDERS           "
.text "      LETHARGY   ONSLAUGHT   LEVEL          "
.text "      SUCCESS   ARTLINE   RESOURCE          "
.text "      PLUSH   FINNISH GOLD   ABYSS CONNECTION "
.text "      OFFENCE   POO-BRAIN   RABENAUGE       "
.text "      HOKUTO FORCE                          "
.text "      AND ALL THE QUIET CODERS              "
.text "      ESPECIALLY KLOOT                      "
.text "      FOR MAKING IT HAPPEN                  "
.text "      THANK YOU EVERYONE                    "
.text "      NOW GO EAT YOUR LUNCH                 "
.text "                                            "
.byte $00


.function glyph_data_21x24(code) {
        .var base = $0800 + code * 8
        .var result = List()
        .for (var row = 0; row < 21; row++) {
                .var srcRow = floor(row * 8 / 21)
                .var srcByte = chargen.get(base + srcRow)
                .var b0 = 0
                .var b1 = 0
                .var b2 = 0
                .for (var col = 0; col < 24; col++) {
                        .var srcCol = floor(col * 8 / 24)
                        .if (((srcByte >> (7 - srcCol)) & 1) != 0) {
                                .var byteIdx = 0
                                .if (col >= 8) { .eval byteIdx = 1 }
                                .if (col >= 16) { .eval byteIdx = 2 }
                                .var bitIdx = col - byteIdx * 8
                                .if (byteIdx == 0) { .eval b0 = b0 | (1 << (7 - bitIdx)) }
                                .if (byteIdx == 1) { .eval b1 = b1 | (1 << (7 - bitIdx)) }
                                .if (byteIdx == 2) { .eval b2 = b2 | (1 << (7 - bitIdx)) }
                        }
                }
                .eval result.add(b0)
                .eval result.add(b1)
                .eval result.add(b2)
        }
        .eval result.add(0)
        .return result
}

font_data:
.for (var c = $41; c <= $5A; c++) {
        .var g = glyph_data_21x24(c)
        .for (var i = 0; i < g.size(); i++) {
                .byte g.get(i)
        }
}
.for (var i = 0; i < 64; i++) {
        .byte 0
}
.for (var s = 0; s < 5; s++) {
        .for (var i = 0; i < 64; i++) {
                .byte 0
        }
}
