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
.const zp_kick_state  = $f9    // V3 kick state machine (0=idle)
.const zp_kick_freq   = $fa    // shadow of V3 freq hi (SID regs are write-only)

// Pitch-swept kick state machine. SID 6581 ignores gate-on if gate
// is already high, and music_play writes V3 ctrl = $41 (pulse + gate)
// every frame. The trick: state 1 drops gate AND installs the kick's
// AD/SR so when music_play raises gate in the NEXT frame, the envelope
// attacks using OUR ADSR rather than something stale.
//
// State values:
//   0       = idle (arp on V3, restore intro AD/SR each frame)
//   1       = HARD RESTART: gate off + INSTALL kick AD/SR + set freq.
//             Envelope releases during this frame.
//   2       = ATTACK frame: music_play's $41 will trigger envelope
//             with kick AD/SR. We override wave to noise for click.
//   3..N    = BODY frames: pulse (let music_play's $41 do it), sweep
//             freq from shadow var (SID $D40F is write-only).
//   N+1     = END: restore intro arp AD/SR, back to idle.
.const KICK_LAST_FRAME = 12      // body frames run 3..LAST inclusive
.const KICK_FREQ_HI    = $0C     // starting freq hi (~183 Hz, audible kick attack)
.const KICK_SWEEP      = $01     // freq hi decrement per body frame
.const KICK_FLOOR      = $03     // sub-bass floor (~46 Hz)


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
        sta zp_kick_state         // CRITICAL: was leaking stale interlude value
        sta zp_kick_freq

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

        // ----- beat counter + V3 kick state machine -----
        inc zp_beat_phase
        lda zp_beat_phase
        cmp #BEAT_PERIOD
        bcc !no_beat+
        lda #0
        sta zp_beat_phase
        inc zp_beat_count
        // Beat hit — arm hard-restart (state 1). The audible attack
        // lands on state 2 (next frame, ~20 ms after the beat — close
        // enough to feel on the beat).
        lda #1
        sta zp_kick_state
!no_beat:

        lda zp_kick_state
        beq !kick_arp+               // 0 = idle, leave V3 to the arp

        cmp #1
        bne !chk_attack+
        // STATE 1 — HARD RESTART: gate off + INSTALL kick AD/SR
        // (NOT zero — we need these to be the kick envelope when
        // music_play's gate-on rising edge fires in the next frame).
        // Also install the freq + shadow.
        lda #$00
        sta $d412                    // V3 control = 0 (gate off, no wave)
        lda #$09
        sta $d413                    // V3 AD: attack 0 (2ms), decay 9 (~750ms)
        lda #$00
        sta $d414                    // V3 SR: no sustain (decays to 0)
        sta $d40e                    // V3 freq lo = 0
        lda #KICK_FREQ_HI
        sta $d40f                    // V3 freq hi (start pitch)
        sta zp_kick_freq             // shadow
        inc zp_kick_state
        jmp !kick_done+

!chk_attack:
        cmp #2
        bne !kick_body+
        // STATE 2 — ATTACK frame. music_play this frame writes
        // ctrl = $41 (gate ON, rising edge from state 1's gate off) —
        // that fires the envelope using the kick AD/SR we installed
        // in state 1. We then override the waveform to noise for a
        // percussive click. AD/SR are already kick values, gate is
        // already on; we just change wave.
        lda #$81                     // noise + gate (gate already 1)
        sta $d412
        inc zp_kick_state
        jmp !kick_done+

!kick_body:
        // STATES 3..KICK_LAST_FRAME — pulse body + freq sweep down.
        cmp #KICK_LAST_FRAME
        bcs !kick_end+
        // Wave: leave as pulse (music_play wrote $41 already this
        // frame, gate stays on, envelope continues its decay).
        // Sweep freq from shadow (SID $D40F is write-only — can't
        // read back what music_play just wrote).
        lda zp_kick_freq
        sec
        sbc #KICK_SWEEP
        cmp #KICK_FLOOR
        bcs !sweep_ok+
        lda #KICK_FLOOR
!sweep_ok:
        sta zp_kick_freq
        sta $d40f
        inc zp_kick_state
        jmp !kick_done+

!kick_end:
        // Kick done — restore intro's arp envelope so the arp resumes.
        lda #$00
        sta $d413
        lda #$f0
        sta $d414
        lda #$00
        sta zp_kick_state            // back to idle — explicit (not via A)
        jmp !kick_done+

!kick_arp:
        // Idle — keep V3 AD/SR at intro's arp settings every frame.
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
