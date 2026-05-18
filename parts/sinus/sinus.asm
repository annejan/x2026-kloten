//==================================================================
// outline-64 — Sinus part: sine-displaced char-mode display with
// colour cycling.
//
// Narrative role: visual comedown after greets' kick climax. The
// inherited intro chords drift through with LP filter closing, while
// a screen of 256 characters sways under per-scanline $D016 sine
// wobble. Colour cycling on border + bg adds movement.
//
// After ~5 seconds the visual fades out and $f6 = $30 triggers the
// pefchain transition to end.
//
// Music arc:
//   Phase 1 (0-4s):  LP filter closes, at ~full wobble
//   Phase 2 (4-5s):  fade colours + volume toward black
//
// Memory:
//   $0800-$0XXX  code + tables
//   $1000-$125D  intro music tables (inherited)
//   $2000-$27FF  charset (2 KB, 256 chars × 8 bytes)
//   $0400-$07FF  screen RAM
//
// Transition: after N_FRAMES sets $f6 = $30 → pefchain advances.
//==================================================================

.const VIC_CTRL1  = $d011
.const VIC_RASTER = $d012
.const VIC_CTRL2  = $d016
.const VIC_MEM    = $d018
.const VIC_IRQ    = $d019
.const VIC_IRQEN  = $d01a
.const VIC_BORDER = $d020
.const VIC_BG     = $d021

.const SCREEN     = $0400
.const COL_RAM    = $d800
.const CHARSET    = $2000

.const SID_VOL    = $d418
.const SID_FILT_CUT_LO = $d415
.const SID_FILT_CUT_HI = $d416
.const SID_FILT_CTRL   = $d417

.const FIRST_LINE = $32               // 50 — first visible scanline
.const N_LINES    = 200               // visible scanlines per frame
.const N_FRAMES   = 250               // ~5 seconds @ 50 Hz (keep < 256)

.const FADE_START = 200               // frame at which fade begins

.const INTRO_MUSIC_PLAY = $119e

.const zp_timer  = $f6                // transition: set to $30 to trigger pefchain
.const zp_tmp    = $f7                // temporary
.const zp_line   = $fb                // current scanline (0-199)  (intro uses $fb as zp_text_ptr; safe across music_play)
.const zp_frame  = $fc                // frame counter (0..N_FRAMES-1)
                                      // MUST avoid $f9/$fa — intro's my_music_play clobbers
                                      // them as zp_tmp/zp_msb on every JSR.


* = $0800 "Sinus"


//==================================================================
// setup
//==================================================================
setup:
        lda #0
        sta zp_timer
        sta zp_line
        sta zp_frame

        // Disable sprites (greets may have left them enabled)
        lda #$00
        sta $d015

        // Fill screen RAM with repeating "DEFEEST" using ROM chargen
        // at $1000 (uppercase). Connects visually back to the screenfill
        // bloom that opened the demo. 1024 cells written (24 extra past
        // visible area into sprite-ptr region — harmless since sprites
        // are disabled). Each char takes 7 cycles: D E F E E S T.
        ldx #0
        ldy #0
!p1:    lda defeest_codes,y
        sta SCREEN,x
        iny
        cpy #7
        bne !sk1+
        ldy #0
!sk1:   inx
        bne !p1-
!p2:    lda defeest_codes,y
        sta SCREEN + $100,x
        iny
        cpy #7
        bne !sk2+
        ldy #0
!sk2:   inx
        bne !p2-
!p3:    lda defeest_codes,y
        sta SCREEN + $200,x
        iny
        cpy #7
        bne !sk3+
        ldy #0
!sk3:   inx
        bne !p3-
!p4:    lda defeest_codes,y
        sta SCREEN + $300,x
        iny
        cpy #7
        bne !sk4+
        ldy #0
!sk4:   inx
        bne !p4-

        // Colour RAM — light cyan everywhere. Letters appear as cyan
        // foreground on black background. Border/bg cycle via raster
        // IRQ for movement.
        ldx #0
        lda #$03
!cr:    sta COL_RAM,x
        sta COL_RAM + $100,x
        sta COL_RAM + $200,x
        sta COL_RAM + $2e8,x
        inx
        bne !cr-

        // Init SID — LP filter mode + volume
        lda #$1f
        sta SID_VOL
        lda #$10                        // LP filter mode bit
        sta SID_FILT_CTRL
        lda #$70                        // mid filter cutoff
        sta SID_FILT_CUT_HI
        lda #$00
        sta SID_FILT_CUT_LO

        // Text mode, ROM chargen at $1000 (uppercase), no MCM.
        // Letters are foreground colour (from colour RAM) on black bg.
        lda #$1b                        // DEN=1, RSEL=1, YSCROLL=3
        sta VIC_CTRL1
        lda #$14                        // screen $0400, chargen $1000 (ROM)
        sta VIC_MEM
        lda #$08                        // CSEL=1, no MCM, xscroll cleared
        sta VIC_CTRL2
        lda #$00
        sta VIC_BORDER
        sta VIC_BG

        lda #$1b
        sta VIC_CTRL1

        // Raster IRQ at top of visible area. Clear $D011 bit 7 first
        // (high bit of raster-compare value) — previous parts may have
        // left it set, in which case our $D012 writes of 49/50/etc.
        // would compare to 305+/306+ (offscreen vsync), and the IRQ
        // chain would never advance correctly.
        lda VIC_CTRL1
        and #%01111111                  // clear bit 7 = compare hi
        sta VIC_CTRL1
        lda #FIRST_LINE - 1
        sta VIC_RASTER
        lda #$01
        sta VIC_IRQEN

        rts


//==================================================================
// fadeout
//==================================================================
fadeout:
        sec
        rts


//==================================================================
// interrupt — single per-frame raster IRQ. No scanline chain (an
// earlier per-line setup never advanced past one frame for reasons
// I couldn't pin down — possibly Spindle's NMI loader stealing
// cycles in the middle of the chain. Simpler is more reliable.)
//
// Per frame:
//   - jsr music (drums silent because setup zero'd $F6)
//   - inc zp_frame
//   - if zp_frame >= N_FRAMES, set $F6 = $30 (transition trigger)
//   - else update LP filter cutoff (sweep close) + volume fade
//   - whole-screen wobble: write sine_tab[zp_frame] to $D016 once
//   - border + bg cycle from per-frame colour tables
//==================================================================
interrupt:
        jsr INTRO_MUSIC_PLAY

        inc zp_frame

        // Transition timer: after N_FRAMES, set $f6 = $30 and stop
        // animating (we're about to be replaced).
        lda zp_frame
        cmp #N_FRAMES
        bcc !run+
        lda #$30
        sta zp_timer
        // Black screen — about to transition out.
        lda #$00
        sta VIC_BORDER
        sta VIC_BG
        lda #$08
        sta VIC_CTRL2
        jmp !ack+

!run:
        // Whole-screen wobble. sine_tab[zp_frame] is 0..7, OR \$08
        // to preserve CSEL (40-col mode).
        ldy zp_frame
        lda sine_tab,y
        ora #$08
        sta VIC_CTRL2

        // Border + bg cycle from per-frame tables.
        lda col_tab,y
        sta VIC_BORDER
        lda bg_tab,y
        sta VIC_BG

        // LP filter close over duration: cutoff $70 → $08.
        lda zp_frame
        eor #$ff
        lsr
        lsr
        clc
        adc #$08
        sta SID_FILT_CUT_HI

        // Vol fade in last 50 frames.
        lda zp_frame
        cmp #FADE_START
        bcc !ack+
        sec
        sbc #FADE_START
        lsr
        sta zp_tmp
        lda #$0f
        sec
        sbc zp_tmp
        bpl !vol+
        lda #0
!vol:   ora #$10
        sta SID_VOL

!ack:
        lda #$ff
        sta VIC_IRQ
        rti


//==================================================================
// DEFEEST screencodes (uppercase chargen at $1000): D E F E E S T.
//==================================================================
defeest_codes:
        .byte $04, $05, $06, $05, $05, $13, $14


//==================================================================
// Sine table — 256 entries, range 0-7 for $D016 fine scroll.
//==================================================================
.align 256
sine_tab:
.for (var i = 0; i < 256; i++) {
        .byte floor(3.5 + 3.5 * sin(i * 2 * PI / 256))
}


//==================================================================
// Border colour table.
//==================================================================
.align 256
col_tab:
.for (var i = 0; i < N_LINES; i++) {
        .byte floor(3.5 + 3.5 * sin(i * 4 * PI / 200))
}


//==================================================================
// Background colour table.
//==================================================================
.align 256
bg_tab:
.for (var i = 0; i < N_LINES; i++) {
        .byte floor(4.5 + 3.5 * sin(i * 3 * PI / 200 + 0.5))
}
