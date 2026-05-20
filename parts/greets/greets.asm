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

.const SPR_BASE_X  = 12
.const SPR_STRIDE  = 40
.const SPR_Y_BASE  = 130

.const BEAT_PERIOD     = 24    // frames per beat
.const DYCP_PHASE_STEP = 32    // phase shift between sprites
.const SCROLL_DELAY    = 12    // advance 1 char every N frames

.const zp_beat_phase  = $f4
.const zp_wobble_pos  = $f5
.const zp_beat_count  = $f6
.const zp_scroll_pos  = $f7
.const zp_scroll_tick = $f8
.const zp_kick_state  = $f9    // V3 kick state machine (0=idle)
.const zp_kick_freq   = $fa    // shadow of V3 freq hi (SID regs are write-only)
.const zp_beat_kick   = $f3    // beat-sync Y kick (decays 0→0)

// Brute-force loud kick. Don't try to be clever with envelope
// retriggers — just FORCE V3 to noise + sustain=15 + gate on
// every frame in the kick window (overriding music_play's $41
// writes), sweep freq down per frame. At end of window: gate off
// + restore intro's arp ADSR so the arp resumes audibly.
//
// State values:
//   0          = idle (arp running on V3)
//   1..N       = kick playing (noise at peak vol, freq sweeping)
//   N+1        = release frame: gate off + restore arp ADSR
.const KICK_LAST_FRAME = 10      // kick plays for 10 frames (~200ms)
.const KICK_FREQ_HI    = $80     // starting freq hi (~1953 Hz noise pitch)
.const KICK_SWEEP      = $10     // freq hi decrement per frame
.const KICK_FLOOR      = $04     // floor (~61 Hz sub-bass)


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

        lda #$01
        sta $d010         // hi-bit X: sprite 0 rightmost at X=292

        lda #$ff
        sta SPR_EN

        lda #0
        sta zp_beat_phase
        sta zp_beat_count
        sta zp_scroll_tick
        sta zp_kick_state         // CRITICAL: was leaking stale interlude value
        sta zp_kick_freq
        sta zp_beat_kick

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

        // ----- beat counter (only — drums now live in intro's
        // my_music_play and carry through every part) -----
        inc zp_beat_phase
        lda zp_beat_phase
        cmp #BEAT_PERIOD
        bcc !no_beat+
        lda #0
        sta zp_beat_phase
        inc zp_beat_count
!no_beat:

        // Always re-write sprite pointers every frame. The Spindle NMI
        // loader can clobber $07F8-$07FF during background loads, and
        // we only advance scroll_pos every N frames, so we'd lose the
        // pointers between scroll ticks. Wasting 8 stores beats having
        // space invaders on screen.
        jsr update_sprite_ptrs

        // colour cycle — rotate sprite colours each frame
        // using warm palette for best readability on black bg
        ldx #0
!col:   txa
        clc
        adc zp_wobble_pos
        and #7
        tay
        lda colour_cycle,y
        sta SPR_COL,x
        inx
        cpx #8
        bne !col-

        // DYCP — advance wobble phase each frame
        inc zp_wobble_pos

        // beat-sync: on beat (zp_beat_phase == 0, just wrapped),
// flash border, push Y down, boost colours
        lda zp_beat_phase
        bne !no_beat_flash+
        // border flash — bright cyan on beat, fades next frame
        lda #$0e
        sta VIC_BORDER
        // Y kick — push sprites down 2px on beat
        lda #2
        sta zp_beat_kick
        jmp !aft_flash+
!no_beat_flash:
        // fade border back to black
        lda #$00
        sta VIC_BORDER
        // decay kick safely (clamp at 0)
        lda zp_beat_kick
        beq !aft_flash+
        sec
        sbc #1
        bpl !set_kick+
        lda #0
!set_kick:
        sta zp_beat_kick
!aft_flash:

        // apply DYCP Y offsets to each sprite (amplitude ±3)
        ldx #0                     // sprite index
!dycp:
        txa
        clc
        adc zp_wobble_pos          // phase = wobble_pos + i * PHASE_STEP
        tay
        lda sine_table,y           // signed -3..+3 (visible wave)
        clc
        adc #SPR_Y_BASE
        // add beat kick
        pha
        lda zp_beat_kick
        sta $fb
        pla
        clc
        adc $fb
        sta $d001,x                // Y register: d001, d003, ...
        inx
        cpx #8
        bne !dycp-

        // horizontal bob — sine offset to X positions, 90° out of phase
        // with Y wobble for a subtle circular motion. Uses sine_table_x
        // (amplitude ±2), phase-shifted by +64 (90° of 256-entry table).
        ldx #0
!dxcp:  txa
        clc
        adc zp_wobble_pos
        clc
        adc #64                    // +64 = 90° phase shift
        tay
        lda sine_table_x,y         // signed -2..+2
        clc
        adc sprite_x_table,x
        sta $d000,x
        inx
        cpx #8
        bne !dxcp-
        // $d010 stays $01 (only sprite 0 needs hi-bit for X=292)

        // scroll tick — advance char every SCROLL_DELAY frames
        ldx zp_scroll_tick
        inx
        cpx #SCROLL_DELAY
        bcc !no_scroll+
        ldx #0
        inc zp_scroll_pos
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
//
// Pointers are REVERSED: sprite 7 (leftmost) gets the leftmost
// character, sprite 0 (rightmost) gets the rightmost. This makes
// overlap show the RIGHT sprite's left edge in front (since sprite
// 0 > sprite 7 in VIC priority), so text reads cleanly left-to-right.
//
// Uses $fb (x temp) and $fc (ptr temp) — outside EFO's Z $f4-$fa
// claim, safe as scratch during IRQ.
//==================================================================
update_sprite_ptrs:
        ldx #0
!lp:    stx $fb                     // save loop counter
        txa
        clc
        adc zp_scroll_pos           // A = scroll_pos + x
        tay
        lda message,y               // char code from message
        tay
        lda ptr_lookup,y            // sprite pointer value
        sta $fc                     // save pointer value
        ldx $fb                     // restore loop counter
        txa
        eor #7                      // reversed sprite index (7-x)
        tay
        lda $fc                     // get pointer value back
        sta SPR_PTR_BASE,y          // store at reversed position
        ldx $fb                     // restore counter
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
// Reversed: sprite 7 is leftmost (X=24), sprite 0 is rightmost (X=276).
// Matches VIC's fixed priority (sprite 0 > sprite 7) — the highest-priority
// sprite is at the rightmost position, so overlap shows each character's
// left edge in front.
.for (var i = 0; i < 8; i++) {
        .byte SPR_BASE_X + (7 - i) * SPR_STRIDE
}

sprite_cols:
.byte $07, $08, $0a, $0c, $0e, $03, $05, $0d

// Warm colour cycle table — rotates through yellow/orange/red/magenta/cyan/green
// for good readability on black background, with sprite-to-sprite phase offset.
colour_cycle:
.byte $07, $08, $0a, $0c, $0e, $03, $05, $0d
.byte $01, $07, $09, $0a, $0c, $0e, $03, $05
.byte $01, $01, $07, $09, $0a, $0c, $0e, $03
.byte $01, $01, $01, $07, $09, $0a, $0c, $0e
.byte $0e, $01, $01, $01, $07, $09, $0a, $0c
.byte $0c, $0e, $01, $01, $01, $07, $09, $0a
.byte $0a, $0c, $0e, $01, $01, $01, $07, $09
.byte $09, $0a, $0c, $0e, $01, $01, $01, $07

sine_table:
// Amplitude 3 for visible wave (±3 px). X wobble uses 90° phase shift
// (offset +64) for a circular bob combined with Y.
.for (var i = 0; i < 256; i++) {
        .byte floor(3 * sin(i * 2 * PI / 256) + 0.5)
}

sine_table_x:
// Amplitude 2 for horizontal bob (±2 px), used with 90° phase offset.
.for (var i = 0; i < 256; i++) {
        .byte floor(2 * sin(i * 2 * PI / 256) + 0.5)
}


//==================================================================
// scrolling message — aligned to $8500 to avoid pefchain load split
// at $84FF/$8500 (first segment $8000-$84FF skips message data).
//==================================================================
* = $8500
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


//==================================================================
// Font data — 26 letters (A-Z) + space + 5 unused slots
// Generated from the C64 chargen ROM at build time.
//==================================================================
.var chargen = LoadBinary("chargen.bin")

.function glyph_data_21x24(code) {
        .var base = $0800 + code * 8
        .var result = List()
        // Each source pixel → 3×3 block (integer 3× scale).
        // 8 rows × 3 = 24 output rows; drop 3 to fit 64-byte sprite slot
        // (21 rows × 3 bytes = 63 + 1 pad). Rows 2, 5, 7 get 2 rows instead of 3.
        .var outRow = 0
        .for (var srcRow = 0; srcRow < 8; srcRow++) {
                .var srcByte = chargen.get(base + srcRow)
                // 3 sub-rows per source row, except rows 2/5/7 which get 2
                .var maxSub = 3
                .if (srcRow == 2 || srcRow == 5 || srcRow == 7) { .eval maxSub = 2 }
                .for (var subRow = 0; subRow < maxSub; subRow++) {
                        .var b0 = 0
                        .var b1 = 0
                        .var b2 = 0
                        // Each source column → 3 output columns
                        .for (var srcCol = 0; srcCol < 8; srcCol++) {
                                .if (((srcByte >> (7 - srcCol)) & 1) != 0) {
                                        .for (var dx = 0; dx < 3; dx++) {
                                                .var col = srcCol * 3 + dx
                                                .var byteIdx = floor(col / 8)
                                                .var bitIdx = col - byteIdx * 8
                                                .if (byteIdx == 0) { .eval b0 = b0 | (1 << (7 - bitIdx)) }
                                                .if (byteIdx == 1) { .eval b1 = b1 | (1 << (7 - bitIdx)) }
                                                .if (byteIdx == 2) { .eval b2 = b2 | (1 << (7 - bitIdx)) }
                                        }
                                }
                        }
                        .eval result.add(b0)
                        .eval result.add(b1)
                        .eval result.add(b2)
                        .eval outRow++
                }
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
