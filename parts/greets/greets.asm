//==================================================================
// outline-64 — greets: DYCP-scrolling sprite font
//
// Displays a 8-char window of a scrolling greetings message using
// 8 X-expanded sprites (24×21, scaled from C64 chargen). Each sprite
// wobbles in Y via a per-sprite DYCP sine offset, giving a wave
// across the row.
//
// Memory:
//   $8000-$86FF  code + state + tables + inline font data
//   $2000-$27FF  sprite font shapes (32 glyphs × 64 B = 2 KB),
//                copied from inline data at setup.
//   $07F8-$07FF  sprite pointers (screen at $0400)
//
// Transition out: pefchain script triggers on f6 = $20 (~15 s).
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
.const SPR_COL     = $d027

.const SPR_PTR_BASE = $07F8
.const SPRITE_SHAPE = $2000

.const INTRO_MUSIC_PLAY = $119e

.const SPR_BASE_X  = 24
.const SPR_STRIDE  = 36
.const SPR_Y_BASE  = 130

.const BEAT_PERIOD     = 24    // frames per beat
.const DYCP_PHASE_STEP = 32    // phase shift between sprites
.const SCROLL_DELAY    = 6     // advance 1 char every N frames

.const zp_beat_phase  = $f4
.const zp_wobble_pos  = $f5
.const zp_beat_count  = $f6
.const zp_scroll_pos  = $f7
.const zp_scroll_tick = $f8
.const zp_kick_remain = $f9    // frames left in current kick window

// Pitch-swept kick (808/Tel-style): noise+gate for the first frame
// gives a percussive transient, then pulse with a fast downward
// pitch sweep over the rest of the window for the deep thump.
// Total ≈ 200 ms, plenty of body to land on the beat.
.const KICK_FRAMES   = 10
.const KICK_FREQ_HI  = $20     // starting freq hi byte (mid-bass)
.const KICK_SWEEP    = $03     // freq hi decrement per frame


* = $8000 "Greets"

//==================================================================
// setup
//==================================================================
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

        // clear screen RAM
        ldx #0
        lda #$20
!clr:   sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne !clr-

        // SID master volume, mute V1
        lda #$1f
        sta $d418
        lda #$00
        sta $d404

        // copy font data to sprite area
        jsr copy_font

        // initial sprite pointers: first 8 chars of message
        lda #0
        sta zp_scroll_pos
        jsr update_sprite_ptrs

        // X-expand all 8, no Y-expand, mono, in front
        lda #$FF
        sta SPR_XEXP
        lda #$00
        sta SPR_YEXP
        sta SPR_MC
        sta SPR_PRIO

        // sprite colours:  cyan (3) / purple (4) / green (5) / blue (6)
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

        // sprite X positions
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
        sta $d010         // hi-bit X = 0 (all < 256)

        lda #$ff
        sta SPR_EN

        lda #0
        sta zp_beat_phase
        sta zp_beat_count
        sta zp_scroll_tick

        lda #$00
        sta VIC_RASTER
        rts


//==================================================================
// interrupt
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

        // Reassert master vol (my_music_play writes vol_in here every
        // frame; without a re-write the SID would stay at $0F with no
        // filter mode — fine for greets since we're going wide-open).
        lda #$0f
        sta $d418

        // V1 (bass) plays naturally — this is the payoff. The previous
        // mute (sta $d404) is gone, the bass returns with intro's
        // punchy ADSR ($04 / $61) intact.

        // ----- beat counter + V3 kick trigger -----
        inc zp_beat_phase
        lda zp_beat_phase
        cmp #BEAT_PERIOD
        bcc !no_beat+
        lda #0
        sta zp_beat_phase
        inc zp_beat_count
        // Beat hit — arm a new kick window on V3.
        lda #KICK_FRAMES
        sta zp_kick_remain
!no_beat:

        // V3 kick override (pitch-sweep style). While the kick window
        // is active, we override the music engine's V3 writes:
        //   • Frame N=KICK_FRAMES (just-armed): noise wave + gate +
        //     short percussive AD/SR for the attack transient.
        //   • Frames N-1..1: pulse wave + gate, freq swept down
        //     (mid → sub) for the deep body.
        //   • Frame N=0: idle — restore intro's arp ADSR so the
        //     engine's next V3 freq/control write resumes the arp.
        lda zp_kick_remain
        beq !no_kick+
        cmp #KICK_FRAMES
        bne !kick_sustain+

        // First frame of kick: noise transient + reset envelope.
        lda #$00
        sta $d413                  // V3 AD = $00 (instant attack/decay)
        lda #$30
        sta $d414                  // V3 SR = $30 (mid sustain for body)
        lda #$00
        sta $d40e                  // V3 freq lo = 0
        lda #KICK_FREQ_HI
        sta $d40f
        lda #$81                   // noise wave + gate on
        sta $d412
        jmp !kick_tick+

!kick_sustain:
        // Subsequent frames: switch to pulse, sweep pitch down each
        // frame so it goes from mid-bass to sub.
        lda #$81                   // (was already noise+gate; flip to pulse)
        and #$7f                   // clear bit 7 (noise) — leaves gate alone
        ora #$41                   // pulse + gate on
        sta $d412
        // Sweep: subtract KICK_SWEEP from freq hi each frame.
        lda $d40f
        sec
        sbc #KICK_SWEEP
        bcs !sweep_ok+
        lda #$01                   // floor at $0100 so it stays audible
!sweep_ok:
        sta $d40f

!kick_tick:
        dec zp_kick_remain
        jmp !kick_done+

!no_kick:
        // Restore intro's arp envelope so the arp resumes audibly.
        lda #$00
        sta $d413
        lda #$f0
        sta $d414
!kick_done:

        // DYCP — advance wobble phase each frame
        inc zp_wobble_pos

        // apply DYCP Y offsets to each sprite
        ldx #0                     // sprite index
!dycp:
        txa
        clc
        adc zp_wobble_pos          // phase = wobble_pos + i * PHASE_STEP
        tay
        lda sine_table,y           // signed -4..+4
        clc
        adc #SPR_Y_BASE
        sta $d001,x                // Y register: d001, d003, ...
        inx
        cpx #8
        bne !dycp-

        // scroll tick
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


//==================================================================
// fadeout
//==================================================================
fadeout:
        sec
        rts


//==================================================================
// update_sprite_ptrs — set $07F8-$07FF to current 8-char window
//==================================================================
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


//==================================================================
// copy_font — bulk copy inline font data → $2000 (2048 bytes)
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


//==================================================================
// Tables
//==================================================================

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


//==================================================================
// scrolling message
//==================================================================
message:
.text "  GREETINGS TO DEFFEEST AND ALL OUR FRIENDS IN THE SCENE  "
.text "THANKS TO  SCS   TRC   FOCUS   F4CG   SILICON LTD   "
.text "XENON   PADUA   ARTLINE DESIGNS   THE RULING COMPANY   "
.text "UNICESS   TST   ILLUSION   CHANNEL 4   ANCIENTS   "
.text "CENSOR DESIGN   QUANTUM   ATLANTIS   PROJECT SIDFX   "
.text "ABYSS CONNECTION   BOARS HEAD CREW   MULTISTYLE LABS   "
.text "FAIRLIGHT   BONZAI   GENESIS PROJECT   PERFORMERS   "
.text "EXTEND   TRSI   OXYRON   BYTERAPERS   HAUTJOBB   "
.text "ELYSIUM   EXCESS   TRIAD   NEOPLASIA   WISEGUY INDUSTRIES   "
.text "THE DREAMS   MAYDAY   RADWAR   ANUBIS   NAH KOLOR   "
.text "VANDALISM NEWS   SQUOQUO   TELENOVA   STARION   "
.text "LOTEK65   PLASTIC BABY   RETRO8BITSHOP   CHOCOTROPHY   "
.text "PHOBOS TEAM   SIDMASTERS   TREX   THE WEEKENDERS   "
.text "LETHARGY   DKR   ONSLAUGHT   LEVEL64   SUCCESS   "
.text "ARTLINE   GP   BONZAI   FAIRLIGHT   GENESIS PROJECT   "
.text "THANK YOU ALL FOR THE INSPIRATION  "
.text "OUTLINE 64  X 2026                  "
.byte $00


//==================================================================
// Font data — 26 letters (A-Z) + space + 5 unused slots
// Generated from the C64 chargen ROM at build time.
//==================================================================
.var chargen = LoadBinary("chargen.bin")

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
// A-Z
.for (var c = $41; c <= $5A; c++) {
        .var g = glyph_data_21x24(c)
        .for (var i = 0; i < g.size(); i++) {
                .byte g.get(i)
        }
}
// space (blank)
.for (var i = 0; i < 64; i++) {
        .byte 0
}
// unused slots (32 - 27 = 5)
.for (var s = 0; s < 5; s++) {
        .for (var i = 0; i < 64; i++) {
                .byte 0
        }
}
