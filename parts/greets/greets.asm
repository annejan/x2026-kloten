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
// Transition out: pefchain script triggers on f6 = $A0 (~77 s).
// Settle phase kicks in at f6 = $90 (~69 s) and holds the screen
// on "  KLOOT " for the last ~7 s — sprites stop bobbing, scroll
// freezes, colour cycle keeps shimmering as the calm landing.
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
.const SCROLL_DELAY    = 8     // advance 1 char every N frames (was 12)

// ---- duration shape ----
// pefchain script transitions at zp_beat_count == TRANSITION_BEAT.
// Three phases:
//   normal      0..FADE_BEAT_START   full bobble, scroll @ SCROLL_DELAY
//   fade        FADE_BEAT_START..SETTLE_BEAT   wobble amplitude damps
//                                              progressively (ASR per
//                                              step), scroll slows
//   settle      SETTLE_BEAT..TRANSITION_BEAT   scroll snaps to punchline,
//                                              sprites perfectly flat,
//                                              colour cycle still cycles
.const FADE_BEAT_START = $78   // 120 beats × 24 = 57.6 s
.const SETTLE_BEAT     = $90   // 144 beats × 24 = 69.1 s
.const TRANSITION_BEAT = $a0   // 160 beats × 24 = 76.8 s — must match
                               //   pefchain_script's `f6 = a0`

.const zp_beat_phase     = $f4
.const zp_wobble_pos     = $f5
.const zp_beat_count     = $f6
.const zp_scroll_pos     = $f7  // 16-bit lo (was 8-bit only)
.const zp_scroll_tick    = $f8
.const zp_scroll_pos_hi  = $f9  // 16-bit hi — message > 256 B needs this
.const zp_damp_shift     = $fa  // 0..5 — ASR count for fade-phase damp
.const zp_beat_kick      = $f3  // beat-sync Y kick (decays 0→0)

// (Dead greets kick code removed — drums now ride on intro's
// resident `my_music_play` via the K-S-K-S kit + V1 bass-bleed.
// $fa still reserved by EFO claim as scratch; update_sprite_ptrs
// uses $fb/$fc which sit outside the claim — fine during IRQ.)


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

        // SID — LP filter on V2 (lead) with moderate resonance. Cutoff
        // is modulated per frame in the IRQ (4 bytes there) for a slow
        // "wah" that matches the DYCP wobble visually.
        lda #$1f                  // LP mode + vol $F ($D418 bit 4 = LP)
        sta $d418
        lda #$42                  // res $4, V2 through filter ($D417)
        sta $d417
        lda #$00
        sta $d404

        // copy font data to sprite area
        jsr copy_font

        // initial sprite pointers: first 8 chars of message
        lda #0
        sta zp_scroll_pos
        sta zp_scroll_pos_hi
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
        sta zp_beat_kick
        sta zp_damp_shift

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

        // Reassert master vol AND keep the LP filter mode bit set.
        // my_music_play writes $0F (no filter mode) every frame, so we
        // need to put bit 4 back to keep V2 going through the filter.
        lda #$1f
        sta $d418

        // LP cutoff "wah" — zp_wobble_pos counts 0..255 per frame
        // (5 s full cycle), OR'd with $40 to keep the cutoff in
        // $40..$FF so the filter never closes all the way (would
        // mute V2 audibly). Slow breathing motion on the lead.
        lda zp_wobble_pos
        ora #$40
        sta $d416

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

        // ----- Fade-phase damp_shift -----
        // From FADE_BEAT_START up to SETTLE_BEAT, ramp `zp_damp_shift`
        // from 0 → 5 in steps of 1 every 4 beats. The DYCP/DXCP code
        // below applies that many arithmetic-shift-rights to each
        // sine sample, so the wobble amplitude shrinks 3 → 1 → 0 px.
        // The scroll tick reads its delay from `SCROLL_DELAY_TABLE`
        // indexed by the same shift, so the scroller also slows
        // progressively. By SETTLE_BEAT the world is already standing
        // still — the actual settle freeze is then invisible.
        lda zp_beat_count
        cmp #FADE_BEAT_START
        bcs !in_fade+
        lda #0
        sta zp_damp_shift
        jmp !damp_done+
!in_fade:
        sec
        sbc #FADE_BEAT_START
        lsr
        lsr                       // / 4 — one damp step every 4 beats
        cmp #5
        bcc !clamp_ok+
        lda #5
!clamp_ok:
        sta zp_damp_shift
!damp_done:

        // ----- Settle gate -----
        // Once zp_beat_count crosses SETTLE_BEAT, snap scroll_pos to
        // the punchline + skip the DYCP/DXCP wobble + freeze the scroll
        // ticker. Colour cycle keeps running so the held text shimmers.
        lda zp_beat_count
        cmp #SETTLE_BEAT
        bcc !no_settle+
        jmp !settled+
!no_settle:

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

        // ----- DYCP — per-sprite Y wave -----
        // For sprite N (0..7):
        //   phase = wobble_pos + N * 32     ; 32 = DYCP_PHASE_STEP, 45°/sprite
        //   Y     = SPR_Y_BASE + sine_table[phase] + zp_beat_kick
        //   write to $D001 + N*2            ; sprite N Y register
        //
        // The earlier version had two bugs that combined into a mess:
        //   - `sta $d001,x` with x = 0..7 hit $D001..$D008, so Y values
        //     scattered across both sprite X and Y registers
        //   - phase calc was `txa / clc / adc wobble_pos` = N + wobble,
        //     a 1-byte step (≈1.4°), so all 8 sprites bobbed in sync
        // Phase shift is now 5×ASL = ×32 (full 45° spacing); offset
        // into VIC sprite-Y registers is `txa / asl / ora #$01 / tay`
        // = N*2+1 (the Y register of sprite N).
        ldx #7
!dycp:
        // phase (5 ASLs = ×32)
        txa
        asl
        asl
        asl
        asl
        asl
        clc
        adc zp_wobble_pos
        tay
        lda sine_table,y           // signed -3..+3
        // Sign-preserving arithmetic shift right, zp_damp_shift times.
        // shift 0 = full amplitude; shift 5 = effectively 0.
        ldy zp_damp_shift
        beq !d_no_damp+
!d_damp:
        cmp #$80                   // C := bit 7 (sign)
        ror                        // rotate with sign-extend
        dey
        bne !d_damp-
!d_no_damp:
        clc
        adc #SPR_Y_BASE
        clc
        adc zp_beat_kick
        pha
        // Y reg offset = N*2 + 1 — destroys A, hence the pha above
        txa
        asl                       // even (bit 0 = 0)
        tay
        iny                       // +1 = sprite-N Y register offset
        pla
        sta $d000,y                // → $D001 / $D003 / ... / $D00F
        dex
        bpl !dycp-

        // ----- DXCP — per-sprite X bob, 90° out of phase with Y -----
        // X = sprite_x_table[N] + sine_table_x[phase + 64]   (amplitude ±2)
        // write to $D000 + N*2 (the X register of sprite N).
        ldx #7
!dxcp:
        txa
        asl
        asl
        asl
        asl
        asl                       // ×32
        clc
        adc zp_wobble_pos
        clc
        adc #64                    // +64 = 90° phase shift vs DYCP
        tay
        lda sine_table_x,y         // signed -2..+2
        // Same damp ramp as DYCP — ASR sign-preserving.
        ldy zp_damp_shift
        beq !x_no_damp+
!x_damp:
        cmp #$80
        ror
        dey
        bne !x_damp-
!x_no_damp:
        clc
        adc sprite_x_table,x
        pha
        // X reg offset = N*2 (preserves carry but we don't need it)
        txa
        asl
        tay
        pla
        sta $d000,y                // → $D000 / $D002 / ... / $D00E
        dex
        bpl !dxcp-
        // $d010 stays $01 (only sprite 0 needs hi-bit for X=292)

        // scroll tick — advance char every N frames where N is
        // SCROLL_DELAY_TABLE[damp_shift]. Normal phase uses 8 frames;
        // the fade ramps up to 64 so the scroll smoothly slows toward
        // a stop alongside the wobble damp. 16-bit scroll_pos carries
        // lo → hi on overflow so the full ~700 B message is reachable.
        ldy zp_damp_shift
        lda SCROLL_DELAY_TABLE,y
        sta $fc                    // scratch (outside EFO claim, IRQ-owned)
        ldx zp_scroll_tick
        inx
        cpx $fc
        bcc !no_scroll+
        ldx #0
        inc zp_scroll_pos
        bne !no_scroll_carry+
        inc zp_scroll_pos_hi
!no_scroll_carry:
!no_scroll:
        stx zp_scroll_tick

        jmp !irq_exit+

!settled:
        // ----- Settle phase — held punchline -----
        // Snap scroll position to the settle_text label every frame
        // (idempotent — costs ~10 cy to overwrite the same bytes).
        lda #<(settle_text - message)
        sta zp_scroll_pos
        lda #>(settle_text - message)
        sta zp_scroll_pos_hi
        jsr update_sprite_ptrs

        // Colour cycle keeps shimmering so the held phrase doesn't
        // look frozen-dead. zp_wobble_pos still advances to drive
        // the cycle index (but it no longer drives X/Y because we
        // skip DYCP/DXCP below).
        ldx #0
!scol:  txa
        clc
        adc zp_wobble_pos
        and #7
        tay
        lda colour_cycle,y
        sta SPR_COL,x
        inx
        cpx #8
        bne !scol-
        inc zp_wobble_pos

        // Border solid black — no per-beat flash during settle so
        // the punchline reads as the calm landing point.
        lda #$00
        sta VIC_BORDER

        // Write flat X (sprite_x_table) + flat Y (SPR_Y_BASE) so the
        // 8 sprites sit perfectly still on a single horizontal line.
        // (Beat counter was already incremented up at the top of the
        // IRQ, so pefchain still sees zp_beat_count climb to
        // TRANSITION_BEAT for the auto-advance.)
        ldx #7
!sflat: txa
        asl
        tay
        lda sprite_x_table,x
        sta $d000,y                // X = base position
        iny
        lda #SPR_Y_BASE
        sta $d000,y                // Y = base line
        dex
        bpl !sflat-

!irq_exit:
        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// fadeout — clear sprites cleanly so coda's setup doesn't briefly
// inherit the held greets sprites at greets' positions/shapes.
//==================================================================
fadeout:
        lda #$00
        sta SPR_EN                    // all 8 sprites off
        sta VIC_BORDER                // border solid black
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
        // Compute (message + scroll_pos) as a 16-bit absolute address
        // and patch it into the LDA in the loop below. This is what
        // gives us reach past the 8-bit-Y limit — the previous version
        // capped scroll_pos at ~248 because `lda message,y` could only
        // index 256 bytes from a single base.
        clc
        lda #<message
        adc zp_scroll_pos
        sta msg_lookup + 1
        lda #>message
        adc zp_scroll_pos_hi
        sta msg_lookup + 2

        ldx #0
!lp:    txa
        tay                          // Y = loop counter (0..7)
msg_lookup:
        lda $0000,y                  // operand patched to (message+scroll_pos)
        tay
        lda ptr_lookup,y             // char code → sprite pointer value
        sta $fc                      // save pointer value (scratch)
        txa
        eor #7                       // reversed sprite index (7-x)
        tay
        lda $fc
        sta SPR_PTR_BASE,y           // store at reversed slot
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

// Scroll delay per damp_shift step. Frame count between char advances:
// damp 0 = normal 8 → ramps up so scroll smoothly decelerates into the
// settle freeze. damp 5 = 128 frames = ~2.5 s/char (basically stopped).
SCROLL_DELAY_TABLE:
.byte 8, 12, 18, 28, 50, 128

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
// scrolling message — page-aligned to $8600 so it sits cleanly
// after the (now larger) code block. The old $8500 anchor collided
// with the expanded settle-aware IRQ. Font data starts after the
// message, still within the $8000-$8FFF EFO claim.
//
// Sized for the SCROLL_DELAY=8 cadence over ~69 s of scroll before
// the settle phase locks the screen on settle_text. update_sprite_ptrs
// reaches the full message via 16-bit indexing (the old `lda message,y`
// capped at scroll_pos ≤ 248).
//==================================================================
// Greets text — uppercase only (font is A-Z + blank).
// The real story: never had time to code the breadbin, then AI made
// it possible. Tongue in cheek, grateful, and shout-outs to the
// folks whose tools / inspiration got us here.
* = $8600
message:
.text "        GREETZ TO ALL LUNCHBASED LIFEFORMS    "
.text "FROM ROTTERDAM AND BEYOND     "
.text "NO BREAD WAS HARMED DURING THIS PRODUCTION    "
.text "EXCEPT THE PINDAKAAS SANDWICH IN DRIVE 1541   "
.text "KLOTEN MET DE BROODTROMMEL    "
.text "THE OFFICIAL LUNCHTIME RELEASE OF X2026    "
.text "SMEERKAAS   BROODJEKAAS.EXE   "
.text "TUPPERWARE DIVISION   ROTTERDAM   "
.text "ALL HAIL THE HAM PIRATES    "
.text "GREETINGS TO FAIRLIGHT   TRIAD   BONZAI   "
.text "GENESIS PROJECT   OXYRON   BYTERAPERS    "
.text "CENSOR DESIGN   PHOBOS TEAM    "
.text "AND ALL THE QUIET CODERS WHO MADE THE TOOLS    "
.text "THIS RELEASE STANDS ON YOUR SHOULDERS    "
.text "ESPECIALLY KLOOT THE AI FOR MAKING IT HAPPEN    "
.text "THANK YOU EVERYONE    "
.text "NOW GO EAT YOUR LUNCH    "
.text "        "
// Landing point for the settle phase. The first 8 chars after this
// label fill the on-screen 8-sprite window once settle kicks in;
// pad with trailing spaces so even if the scroller drifts past it
// for any reason, the visible window stays clean.
settle_text:
.text "  KLOOT                                                  "
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
// Blank glyph for ptr_lookup's $9A slot — every char outside A-Z
// (spaces, '.', digits, etc.) gets mapped here. Without this explicit
// fill the slot reads uninitialised RAM and the "blanks" between words
// render as random pixels, which made the new message look glitched
// as soon as it picked up chars like 'BROODJEKAAS.EXE' or 'X2026'.
.fill 64, 0
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
