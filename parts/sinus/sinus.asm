//==================================================================
// outline-64 — Sinus part: the breath.
//
// A hypnotic field of repeating "DEFEEST" text gently wobbling on a
// dual-axis sine, colour cycling through breadbin blues, LP filter
// closing on bass + lead until they are a muffled warm hum. Drums
// stop. Volume fades. The eye of the storm before greets.
//
// After ~5 seconds the visual fades out and $f6 = $30 triggers the
// pefchain transition to greets.
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

        // Fill screen with repeating "DEFEEST" — a hypnotic text field
        // that echoes the screenfill bloom. Each row is the same 40-char
        // pattern of D/E/F/E/E/S/T, creating a woven grid for the
        // wobble + colour banding to sweep through.
        lda #<SCREEN
        sta $fb                     // ptr lo (zp_line, safe in setup)
        lda #>SCREEN
        sta $fc                     // ptr hi (zp_frame, safe in setup)
        ldx #25                     // 25 rows
!row:
        ldy #0
!cell:
        lda defeest_row,y
        sta ($fb),y
        iny
        cpy #40
        bne !cell-
        clc
        lda $fb
        adc #40
        sta $fb
        bcc !+
        inc $fc
!:
        dex
        bne !row-

        // Colour RAM — per-row stripe palette. Each row gets a single
        // colour from row_palette; text on that row picks up its row's
        // colour, giving banded blue/cyan bands for the wobble sweep.
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

        // Init SID — LP filter on, V1 (bass) + V2 (lead) routed through it.
        // $D418 bit 4 = LP mode; volume in low nibble.
        // $D417 bit 0 = V1 filtered, bit 1 = V2 filtered, bits 4-7 = resonance.
        // V3 stays unfiltered so arp + any drum hits keep their bite.
        // The interrupt ramps SID_FILT_CUT_HI from $70 down to $08 over
        // the duration, so the bass + lead progressively close down to a
        // dull throb as sinus winds out into greets.
        lda #$1f
        sta SID_VOL
        lda #$23                        // V1+V2 filtered, resonance $2
        sta SID_FILT_CTRL
        lda #$70                        // start cutoff — bright
        sta SID_FILT_CUT_HI
        lda #$00
        sta SID_FILT_CUT_LO

        // Text mode, ROM chargen at $1800 (lowercase set), no MCM.
        // Lowercase keeps the DEFEEST text field soft — screen filler
        // rather than headlines.
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

        // intro music_play writes $0F to $D418 every frame, which
        // CLEARS the LP filter mode bit. Re-assert $1F so V1+V2 keep
        // going through the LP filter (with the cutoff sweep below).
        lda #$1f
        sta SID_VOL

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
// DEFEEST row pattern — "DEFEEST" repeating across 40 columns.
// Precomputed at assembly time; 40 bytes = one screen row.
//==================================================================
defeest_row:
        .byte $04, $05, $06, $05, $05, $13, $14   // D E F E E S T
        .byte $04, $05, $06, $05, $05, $13, $14
        .byte $04, $05, $06, $05, $05, $13, $14
        .byte $04, $05, $06, $05, $05, $13, $14
        .byte $04, $05, $06, $05, $05, $13, $14
        .byte $04, $05, $06, $05, $05            // D E F E E (40th col)


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
