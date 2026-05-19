//==================================================================
// outline-64 — Sinus part: checker-field wobble + colour cycle.
//
// Dual-axis sine wobble (horizontal $D016 + vertical $D011) on a
// screen of alternating S-space characters. Colour cycling on
// border + bg sweeps through blues/cyan. LP filter closes + volume
// fades toward the end.
//
// After ~5 seconds the visual fades out and $f6 = $30 triggers the
// pefchain transition to end.
//
// Memory:
//   $0800-$0CFF  code + tables
//   $1000-$125D  intro music tables (inherited)
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

        // Fill screen RAM with spaces ($20) — a clean canvas for the
        // wobble + colour cycling to animate.
        ldx #0
        lda #$20
!f:     sta SCREEN,x
        sta SCREEN + $100,x
        sta SCREEN + $200,x
        sta SCREEN + $300,x
        inx
        bne !f-

        // Colour RAM — per-row stripe palette. Each row gets a single
        // colour from row_palette; text on that row inherits its row's
        // colour, giving a banded blue/cyan field for the wobble to
        // sweep through. zp $f7/$f8 are overloaded as a 16-bit pointer
        // here (only used in setup; the IRQ reuses $f7 as zp_tmp once
        // it starts).
        ldx #0
!srow:
        lda col_row_lo,x
        sta zp_tmp
        lda col_row_hi,x
        sta zp_tmp + 1
        lda row_palette,x
        ldy #39
!scell: sta (zp_tmp),y
        dey
        bpl !scell-
        inx
        cpx #25
        bne !srow-

        // Narrative text — sinus is the demo's story moment. Ten
        // fragments scattered across the screen, lowercase chargen so
        // they read as thinking/remembering rather than announcing.
        // Tells the whole arc: gap → catalyst → partnership →
        // discovery (sid / vic / open borders) → resolution → cast
        // + dedication. Wobble + colour stripes let it drift in and
        // out as the bg cycles through its palette.
        //
        // Row 2 col 5: "years went by"
        ldx #12
!t1:    lda text_years,x
        sta $0455,x
        dex
        bpl !t1-
        // Row 4 col 5: "no time for breadbin code"
        ldx #24
!t2:    lda text_no_time,x
        sta $04A5,x
        dex
        bpl !t2-
        // Row 7 col 10: "then kloot walked in" — the catalyst, echoes
        // the interlude plasma's "BUT THEN KLOOT WALKED IN" tease.
        ldx #19
!t3:    lda text_kloot_walked,x
        sta $0522,x
        dex
        bpl !t3-
        // Row 10 col 11: "patient pair coder"
        ldx #17
!t4:    lda text_pair,x
        sta $059B,x
        dex
        bpl !t4-
        // Row 13 col 5: "sid voices"  — the discovery beat: anus
        // re-learns demo coding alongside kloot, one chip at a time
        ldx #9
!t5:    lda text_sid,x
        sta $060D,x
        dex
        bpl !t5-
        // Row 14 col 5: "vic rasters"
        ldx #10
!t6:    lda text_vic,x
        sta $0635,x
        dex
        bpl !t6-
        // Row 15 col 5: "open borders"
        ldx #11
!t7:    lda text_borders,x
        sta $065D,x
        dex
        bpl !t7-
        // Row 18 col 11: "curiosity returned" — the resolution
        ldx #17
!t8:    lda text_curiosity,x
        sta $06DB,x
        dex
        bpl !t8-
        // Row 21 col 5: cast
        ldx #27
!t9:    lda text_cast,x
        sta $074D,x
        dex
        bpl !t9-
        // Row 23 col 11: dedication
        ldx #16
!t10:   lda text_credits,x
        sta $07A3,x
        dex
        bpl !t10-

        // Init SID — LP filter mode + volume
        lda #$1f
        sta SID_VOL
        lda #$10                        // LP filter mode bit
        sta SID_FILT_CTRL
        lda #$70                        // mid filter cutoff
        sta SID_FILT_CUT_HI
        lda #$00
        sta SID_FILT_CUT_LO

        // Text mode, ROM chargen at $1800 (lowercase set), no MCM.
        // Lowercase chargen makes the narrative fragments read as
        // thinking-out-loud rather than headline announcements.
        // YSCROLL=0 initially — vertical wobble in IRQ sets it per frame.
        lda #$18                        // DEN=1, RSEL=1, YSCROLL=0
        sta VIC_CTRL1
        lda #$16                        // screen $0400, chargen $1800 (lowercase ROM)
        sta VIC_MEM
        lda #$08                        // CSEL=1, no MCM, xscroll cleared
        sta VIC_CTRL2
        lda #$00
        sta VIC_BORDER
        sta VIC_BG

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
//   - dual-axis wobble: horizontal ($D016) + vertical ($D011) with
//     90° phase offset for a circular wave
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
        // Dual-axis wobble. Horizontal ($D016 fine scroll) plus
        // vertical ($D011 fine scroll) with a 90° phase offset
        // for a circular wave feel.
        ldy zp_frame
        lda sine_tab,y
        ora #$08                        // preserve CSEL (40-col mode)
        sta VIC_CTRL2

        // Vertical wobble — reuse sine_tab with 90° phase shift
        lda sine_tab + 64,y
        ora #$18                        // DEN=1, RSEL=1
        sta VIC_CTRL1

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


//==================================================================
// Narrative text fragments — screen codes for lowercase chargen at
// $1800 (a=$01, b=$02, ..., z=$1A; space=$20; digits=$30..$39).
//
// The story: years passed without breadbin code; then kloot walked
// in; result is this demo, dedicated to X2026.
//==================================================================
text_years:        // "years went by" — 13 chars
        .byte $19, $05, $01, $12, $13, $20, $17, $05, $0E, $14, $20, $02, $19
text_no_time:      // "no time for breadbin code" — 25 chars
        .byte $0E, $0F, $20, $14, $09, $0D, $05, $20, $06, $0F, $12, $20
        .byte $02, $12, $05, $01, $04, $02, $09, $0E, $20, $03, $0F, $04, $05
text_kloot_walked: // "then kloot walked in" — 20 chars (catalyst,
                   // echoes interlude bass-return)
        .byte $14, $08, $05, $0E, $20, $0B, $0C, $0F, $0F, $14
        .byte $20, $17, $01, $0C, $0B, $05, $04, $20, $09, $0E
text_pair:         // "patient pair coder" — 18 chars
        .byte $10, $01, $14, $09, $05, $0E, $14, $20, $10, $01, $09, $12
        .byte $20, $03, $0F, $04, $05, $12
text_sid:          // "sid voices" — 10 chars (discovery beat 1)
        .byte $13, $09, $04, $20, $16, $0F, $09, $03, $05, $13
text_vic:          // "vic rasters" — 11 chars (discovery beat 2)
        .byte $16, $09, $03, $20, $12, $01, $13, $14, $05, $12, $13
text_borders:      // "open borders" — 12 chars (discovery beat 3)
        .byte $0F, $10, $05, $0E, $20, $02, $0F, $12, $04, $05, $12, $13
text_curiosity:    // "curiosity returned" — 18 chars (resolution)
        .byte $03, $15, $12, $09, $0F, $13, $09, $14, $19
        .byte $20, $12, $05, $14, $15, $12, $0E, $05, $04
text_cast:         // "anus  kloot  ranzbak  cinder" — 28 chars
        .byte $01, $0E, $15, $13, $20, $20, $0B, $0C, $0F, $0F, $14, $20, $20
        .byte $12, $01, $0E, $1A, $02, $01, $0B, $20, $20, $03, $09, $0E, $04, $05, $12
text_credits:      // "defeest for X2026" — 17 chars (capital X = $58
                   // in lowercase chargen)
        .byte $04, $05, $06, $05, $05, $13, $14, $20, $06, $0F, $12, $20
        .byte $58, $32, $30, $32, $36


//==================================================================
// Per-row colour-RAM stripe tables.
//==================================================================
.align 16
// Row N's colour-RAM start lo / hi byte.
col_row_lo:
.for (var row = 0; row < 25; row++) {
        .byte <(COL_RAM + row * 40)
}
col_row_hi:
.for (var row = 0; row < 25; row++) {
        .byte >(COL_RAM + row * 40)
}

// Row colour palette — symmetric blue / light-blue / cyan / light-blue /
// blue bands. Text rows pick up: 4=blue, 6=light-blue, 12=cyan, 13=cyan,
// 19=light-blue, 21=blue. Wobble + bg cycle sweep through; the stripes
// stay legible against most of the per-frame bg palette.
row_palette:
        .byte $06, $06, $06, $06, $06    // rows 0-4:   blue
        .byte $0E, $0E, $0E, $0E, $0E    // rows 5-9:   light-blue
        .byte $03, $03, $03, $03, $03    // rows 10-14: cyan
        .byte $0E, $0E, $0E, $0E, $0E    // rows 15-19: light-blue
        .byte $06, $06, $06, $06, $06    // rows 20-24: blue
