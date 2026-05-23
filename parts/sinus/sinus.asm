//==================================================================
// outline-64 — Sinus: the breath.
//
// Dual-phase emotional heart of the demo. Phase 1 (frames 0-119):
// accusation text in red tones, harsh wobble. Phase 2 (frames
// 120-249): answer text in cyan, gentle wobble. LP filter close,
// volume fade, then $f6 = $30 triggers greets.
//==================================================================

.const VIC_CTRL1  = $d011
.const VIC_RASTER = $d012
.const VIC_CTRL2  = $d016
.const VIC_MEM    = $d018
.const VIC_IRQ    = $d019
.const VIC_IRQEN  = $d01a
.const VIC_BORDER = $d020
.const VIC_BG     = $d021
.const VIC_SPR_EN = $d015
.const SCREEN     = $0400
.const COL_RAM    = $d800
.const SID_VOL    = $d418
.const SID_FILT_CUT_LO = $d415
.const SID_FILT_CUT_HI = $d416
.const SID_FILT_CTRL   = $d417
.const FIRST_LINE = $32
.const N_FRAMES   = 250
.const FADE_START = 200
.const SWAP_FRAME = 120
.const MSG_TOP    = 10
.const MSG_ROWS   = 2
.const INTRO_MUSIC_PLAY = $119e
.const zp_timer  = $f6
.const zp_line   = $f8
.const zp_dst_lo = $f9
.const zp_dst_hi = $fa
.const zp_frame  = $fc
.const zp_ptr    = $fd
.const zp_col_lo = $fb
.const zp_col_hi = $fc

* = $0800 "Sinus"

setup:
        lda #0
        sta zp_timer
        sta zp_frame
        sta swap_flag
        sta VIC_SPR_EN

        // Screen fill: rows 0-24
        lda #<SCREEN
        sta zp_dst_lo
        lda #>SCREEN
        sta zp_dst_hi
        ldx #0
!row:
        stx zp_line
        cpx #MSG_TOP
        bcc !src_def+
        cpx #(MSG_TOP + MSG_ROWS)
        bcs !src_def+
        cpx #MSG_TOP
        bne !msg1+
        lda #<msg_phase1
        sta zp_ptr
        lda #>msg_phase1
        sta zp_ptr + 1
        jmp !fill+
!msg1:
        lda #<(msg_phase1 + 40)
        sta zp_ptr
        lda #>(msg_phase1 + 40)
        sta zp_ptr + 1
        jmp !fill+
!src_def:
        lda #<defeest_row
        sta zp_ptr
        lda #>defeest_row
        sta zp_ptr + 1
        cpx #(MSG_TOP + MSG_ROWS)
        bne !fill+
        lda #$20
        ldy #0
!bl:    sta (zp_dst_lo),y
        iny
        cpy #40
        bne !bl-
        jmp !next+
!fill:
        ldy #0
!cp:    lda (zp_ptr),y
        sta (zp_dst_lo),y
        iny
        cpy #40
        bne !cp-
!next:
        lda zp_dst_lo
        clc
        adc #40
        sta zp_dst_lo
        bcc !+
        inc zp_dst_hi
!:
        ldx zp_line
        inx
        cpx #25
        bne !row-

        // Colour RAM fill
        lda #<COL_RAM
        sta zp_col_lo
        lda #>COL_RAM
        sta zp_col_hi
        ldx #0
!crow:
        stx zp_line
        lda pal_phase1,x
        ldy #39
!cc:    sta (zp_col_lo),y
        dey
        bpl !cc-
        lda zp_col_lo
        clc
        adc #40
        sta zp_col_lo
        bcc !+
        inc zp_col_hi
!:
        ldx zp_line
        inx
        cpx #25
        bne !crow-

        lda #0
        sta zp_frame

        lda #$1f
        sta SID_VOL
        lda #$23
        sta SID_FILT_CTRL
        lda #$70
        sta SID_FILT_CUT_HI
        lda #$00
        sta SID_FILT_CUT_LO

        lda #$18
        sta VIC_CTRL1
        lda #$16                   // screen $0400 + chargen $1800
        sta VIC_MEM                // = lowercase ROM (mixed-case set).
                                   // Was $1A which pointed CB to RAM
                                   // $2800 where intro's logo bitmap
                                   // lives → text rendered as garbage.
                                   // $16 = CB 011 = ROM $1800, glyphs
                                   // $01-$1A=a-z, $41-$5A=A-Z, $20=sp.
        lda #$08
        sta VIC_CTRL2
        lda #$00
        sta VIC_BORDER
        sta VIC_BG

        lda VIC_CTRL1
        and #%01111111
        sta VIC_CTRL1
        lda #FIRST_LINE - 1
        sta VIC_RASTER
        lda #$01
        sta VIC_IRQEN
        rts

fadeout:
        sec
        rts

interrupt:
musichook:
        .byte $2c, $00, $00
        lda #$1f
        sta SID_VOL
        inc zp_frame

        lda zp_frame
        cmp #N_FRAMES
        bcc !run+
        lda #$30
        sta zp_timer
        lda #$00
        sta VIC_BORDER
        sta VIC_BG
        lda #$08
        sta VIC_CTRL2
        jmp !ack+

!run:
        lda zp_frame
        cmp #SWAP_FRAME
        bne !no_swap+
        lda swap_flag
        bne !no_swap+
        inc swap_flag
        lda #$01
        sta VIC_BORDER
        ldx #0
!copy:  lda msg_phase2,x
        sta SCREEN + MSG_TOP * 40,x
        inx
        cpx #(MSG_ROWS * 40)
        bne !copy-
        lda pal_phase2 + MSG_TOP + 0
        ldy #39
!:      sta COL_RAM + (MSG_TOP + 0) * 40,y
        dey
        bpl !-
        lda pal_phase2 + MSG_TOP + 1
        ldy #39
!:      sta COL_RAM + (MSG_TOP + 1) * 40,y
        dey
        bpl !-
        lda #$00
        ldy #39
!:      sta COL_RAM + (MSG_TOP + MSG_ROWS) * 40,y
        dey
        bpl !-
        jmp !wobble_done+

!no_swap:
        ldy zp_frame
        lda swap_flag
        beq !full+
        lda sine_tab,y
        lsr
        sta zp_ptr
        lda sine_tab + 64,y
        lsr
        tax
        lda zp_ptr
        jmp !apply+
!full:
        lda sine_tab,y
        ldx sine_tab + 64,y
!apply:
        ora #$08
        sta VIC_CTRL2
        txa
        ora #$18
        sta VIC_CTRL1

        ldy zp_frame
        lda col_tab,y
        sta VIC_BORDER
        lda bg_tab,y
        sta VIC_BG

!wobble_done:
        lda zp_frame
        eor #$ff
        lsr
        lsr
        clc
        adc #$08
        sta SID_FILT_CUT_HI

        lda zp_frame
        cmp #FADE_START
        bcc !raster_bars+
        sec
        sbc #FADE_START
        lsr
        sta zp_ptr
        lda #$0f
        sec
        sbc zp_ptr
        bpl !vol+
        lda #0
!vol:   ora #$10
        sta SID_VOL

!raster_bars:
        // Skip bars on the swap frame so the 1-frame white border
        // flash stays visible across the full frame (otherwise the
        // bar loop overwrites $D020 immediately).
        lda zp_frame
        cmp #SWAP_FRAME
        beq !ack+

        // Open-bar raster colour sweep over the 200 visible scanlines.
        // $D020 + $D021 per scanline, indexed by Y = (zp_frame +
        // line_count) mod 200 so the pattern flows downward as frames
        // advance. No $D016 write (the per-frame sine wobble handles
        // horizontal scroll). Synced via $D012 polling between lines.
        // Loop wraps Y at 200 because col_tab/bg_tab are 200 entries.
        lda #$33
!w_top: cmp $d012
        bne !w_top-
        ldy zp_frame
        cpy #200
        bcc !y_ok+
        ldy #0
!y_ok:  ldx #0
!barloop:
        // No $D016 write here — the per-frame sine wobble upstairs
        // already handles horizontal scroll. Writing $D016 per scanline
        // would override it, killing the visible sine movement.
        lda col_tab,y
        sta VIC_BORDER          // $D020 border bar
        lda bg_tab,y
        sta VIC_BG              // $D021 bg bar
        iny
        cpy #200
        bne !no_wrap+
        ldy #0
!no_wrap:
        inx
        cpx #200
        beq !ack+
        lda $d012
!w_line:
        cmp $d012
        beq !w_line-
        jmp !barloop-

!ack:
        lda #$ff
        sta VIC_IRQ
        rti

//==================================================================
// Tables
//==================================================================

.align 256
sine_tab:
.for (var i = 0; i < 256; i++) {
        .byte floor(3.5 + 3.5 * sin(i * 2 * PI / 256))
}

.align 256
col_tab:
.for (var i = 0; i < 200; i++) {
        .byte floor(3.5 + 3.5 * sin(i * 4 * PI / 200))
}

.align 256
bg_tab:
.for (var i = 0; i < 200; i++) {
        .byte floor(4.5 + 3.5 * sin(i * 3 * PI / 200 + 0.5))
}

msg_phase1:
        .byte $54, $48, $45, $59, $20, $53, $41, $49, $44, $20
        .byte $41, $49, $20, $44, $45, $53, $54, $52, $4F, $59
        .byte $53, $20, $43, $52, $45, $41, $54, $49, $56, $49
        .byte $54, $59, $20, $20, $20, $20, $20, $20, $20, $20
        .byte $4B, $49, $4C, $4C, $49, $4E, $47, $20, $4A, $4F
        .byte $59, $20, $41, $4E, $44, $20, $4E, $55, $4D, $42
        .byte $49, $4E, $47, $20, $4F, $55, $52, $20, $4D, $49
        .byte $4E, $44, $53, $20, $20, $20, $20, $20, $20, $20

msg_phase2:
        .byte $57, $45, $20, $46, $4F, $55, $4E, $44, $20, $54
        .byte $48, $45, $20, $4F, $50, $50, $4F, $53, $49, $54
        .byte $45, $20, $20, $20, $20, $20, $20, $20, $20, $20
        .byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
        .byte $4E, $4F, $54, $20, $41, $20, $54, $48, $52, $45
        .byte $41, $54, $20, $42, $55, $54, $20, $41, $20, $54
        .byte $4F, $4F, $4C, $20, $20, $20, $20, $20, $20, $20
        .byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20

swap_flag:      .byte 0

pal_phase1:
        .byte $06, $06, $06, $06, $06
        .byte $0E, $0E, $0E, $0E, $0E
        .byte $02, $0E
        .byte $06
        .byte $0E, $0E, $0E, $0E, $0E
        .byte $06, $06, $06, $06, $06
        .byte $0E

pal_phase2:
        .byte $06, $06, $06, $06, $06
        .byte $0E, $0E, $0E, $0E, $0E
        .byte $03, $0E
        .byte $00
        .byte $0E, $0E, $0E, $0E, $0E
        .byte $06, $06, $06, $06, $06
        .byte $0E

// Wallpaper row: "deFEEST" — lowercase d/e, uppercase FEEST.
defeest_row:
        .byte $44, $45, $06, $05, $05, $13, $14
        .byte $44, $45, $06, $05, $05, $13, $14
        .byte $44, $45, $06, $05, $05, $13, $14
        .byte $44, $45, $06, $05, $05, $13, $14
        .byte $44, $45, $06, $05, $05, $13, $14
        .byte $44, $45, $06, $05, $05
