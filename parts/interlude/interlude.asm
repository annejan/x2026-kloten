//==================================================================
// outline-64 — interlude: text-mode plasma + raster bars
//
// Two visual layers over the pad + build-up music arc:
//
//   1. PLASMA — diagonal colour bars scrolling through color RAM.
//      A 256-byte wave scrolls horizontally; each 40-col row has
//      a staggered phase offset, creating a diagonal bar pattern.
//      Half the rows update each frame (packed 2×4-bit per byte)
//      to fit PAL budget.
//
//   2. RASTER BARS — 6 horizontal bars in the border, colours
//      cycling per beat. IRQ chain (main -> 6 bars -> main) flips
//      border at each bar's raster position.
//
// Memory:
//   $8000-$84FF  code + tables (5 pages)
//   $1000-$125D  intro music tables (inherited)
//
//==================================================================

.const VIC_CTRL1  = $d011
.const VIC_RASTER = $d012
.const SPR_EN     = $d015
.const VIC_CTRL2  = $d016
.const VIC_MEM    = $d018
.const VIC_IRQ    = $d019
.const VIC_BORDER = $d020
.const VIC_BG     = $d021
.const SPR_X      = $d000
.const SPR_MSB    = $d010
.const SPR_PRIO   = $d01b
.const SPR_XEXP   = $d01d
.const SPR_YEXP   = $d017
.const SPR_MC     = $d01c
.const SPR_COL    = $d027
.const SPR_PTRS   = $07f8
.const IRQ_VEC    = $fffe

.const INTRO_MUSIC_PLAY = $119e

.const BEAT_PERIOD   = 20         // frames per beat — was 24, tightened
.const BUILDUP_BEAT  = 4          // pad ends, bass+filter+bars in — was 8
.const TRANSITION_BEAT = 10       // pefchain advances at zp_beat_count == this — was 16
.const FILT_CUT_LO   = $40
.const FILT_CUT_STEP = $20        // steeper sweep so the shorter buildup still tops out

// Sprite-letter line B — "AI WROTE" drops in on the buildup, bounces
// briefly, then flies up before the transition. 8 sprites, 1 char each,
// hires, no expand. Shape pointers $80..$87 → $2000..$21C0.
.const SPR_TARGET_Y    = 154      // raster row 13 top — letters sit above the "now AI WROTE the code" reveal
.const SPR_SPAWN_Y     = 0        // off-screen above; falls into place
.const PHASE_OFF       = 0
.const PHASE_FLY_IN    = 1
.const PHASE_BOUNCE    = 2
.const PHASE_FLY_OUT   = 3
.const FLY_IN_LEN      = 32       // frames between first letter dropping and last letter settling
.const FLY_OUT_LEN     = 20

.const zp_beat_phase = $f4
.const zp_filt_cut   = $f5
.const zp_beat_count = $f6
.const zp_xphase     = $f7        // global plasma X phase (per-frame)
.const zp_plasma_tgl = $f8
.const zp_bar_clr_ofs= $f9
.const zp_wave_phs   = $fa        // per-row cell phase tracker
.const zp_yphase     = $fb        // global plasma Y phase (slower)
.const zp_tmp        = $fc
.const zp_y_contrib  = $fd        // per-row precomputed Y wave value

* = $8000 "Interlude"

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
        sta SPR_EN
        sta VIC_BORDER
        sta VIC_BG

        lda #$1f
        sta $d418
        lda #$00
        sta $d404
        sta $d416
        sta $d417

        lda #0
        sta zp_beat_phase
        sta zp_beat_count
        sta zp_filt_cut
        sta zp_xphase
        sta zp_yphase
        sta zp_plasma_tgl
        sta zp_bar_clr_ofs
        sta sp_phase
        sta sp_frame
        sta line_a_pos
        sta line_a_tick

        // Fill screen with solid block ($A0 reverse-space in screencode_mixed)
        // so the per-cell colour-RAM plasma is actually visible. Plain
        // $20 (space) is transparent — colour RAM cycling without any
        // foreground pixels would render nothing on screen.
        ldx #0
        lda #$a0
!clr:   sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne !clr-

        // Line A is now revealed by update_line_a one char every 2 frames
        // during the pad phase — see story_line_a section. The screen is
        // already filled with $A0 above, so row 11 starts as a wash of
        // plasma-coloured blocks; chars overwrite them as they "type".
        // Line B is the AI WROTE sprite-letter drop (init_sprites below).

        // fill ALL 25 color RAM rows
        lda #0
        sta zp_plasma_tgl
!all:   ldx zp_plasma_tgl
        jsr write_plasma_row
        inc zp_plasma_tgl
        lda zp_plasma_tgl
        cmp #25
        bne !all-
        lda #0
        sta zp_plasma_tgl

        jsr init_sprites

        // vsync IRQ
        lda #$ff
        sta VIC_RASTER
        rts


//==================================================================
// init_sprites — sprite-letter line B setup. 8 hires sprites point at
// pre-rendered chargen glyphs in $2000..$21C0; X positions span 152..208
// to centre the 8-char phrase under row 11; Y position is patched per
// frame by update_sprites depending on the global animation phase.
//==================================================================
init_sprites:
        // block pointers $80..$87 → $2000..$21C0
        ldx #0
!ptr:   txa
        clc
        adc #$80
        sta SPR_PTRS,x
        inx
        cpx #8
        bne !ptr-

        // X positions (low byte; all sprites have MSB clear since 208<256)
        ldx #0
        ldy #0
!xp:    lda spr_x_table,x
        sta SPR_X,y
        lda #SPR_SPAWN_Y          // park off-screen above
        sta SPR_X+1,y
        inx
        iny
        iny
        cpx #8
        bne !xp-
        lda #$00
        sta SPR_MSB

        // hires, no expand, in front of plasma
        lda #$00
        sta SPR_XEXP
        sta SPR_YEXP
        sta SPR_MC
        sta SPR_PRIO

        // sprite colours — alternating white / light-cyan keeps the
        // letters legible against any plasma colour underneath.
        ldx #0
!col:   lda spr_color_table,x
        sta SPR_COL,x
        inx
        cpx #8
        bne !col-

        // sprites off until the buildup beat fires update_sprites' fly-in
        lda #$00
        sta SPR_EN
        rts


//==================================================================
// write_plasma_row — true 2D plasma into row X's 40 colour-RAM cells.
//   X = row index 0..24.
//
// Algorithm: per cell, colour = palette[ (wave[X-phase] + wave[Y-phase]) & 0x0F ].
// Two independent phases (`zp_xphase`, `zp_yphase`) advance at
// different rates each frame, so the interference pattern morphs
// rather than just scrolling. Y-contribution is constant for the
// whole row — computed once at row start, reused for all 40 cells.
//==================================================================
write_plasma_row:
        // Per-row Y contribution: wave[(row_offset[X] + yphase) & 0xff].
        // row_offset has non-linear stagger so vertical bands curve.
        lda row_offset,x
        clc
        adc zp_yphase
        tay
        lda wave,y
        sta zp_y_contrib

        // Per-row X phase: starts at zp_xphase, increments per cell.
        lda zp_xphase
        sta zp_wave_phs

        // Self-modify destination ($D800 + X*40).
        lda row_cr_lo,x
        sta smc+1
        lda row_cr_hi,x
        sta smc+2

        // Per-cell loop: 40 colour-RAM writes.
        ldx #0
!lp:    ldy zp_wave_phs
        lda wave,y
        clc
        adc zp_y_contrib          // 2D plasma sum
        and #$0f
        tay
        lda plasma_palette,y      // hue-stable gradient
smc:    sta $d800,x
        inc zp_wave_phs
        inx
        cpx #40
        bcc !lp-
        rts


//==================================================================
// interrupt — main vsync handler, raster $FF
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
        lda #$1f
        sta $d418

        // V1 mute / build-up
        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcs !buildup+
        lda #$00
        sta $d404
        jmp !beat+
!buildup:
        lda #$01
        sta $d417
        lda zp_filt_cut
        sta $d416
        // Line B reveal is now the sprite-letter drop — see
        // update_sprites for the fly-in / bounce / fly-out state machine.
!beat:
        inc zp_beat_phase
        lda zp_beat_phase
        cmp #BEAT_PERIOD
        bcc !no_beat+
        lda #0
        sta zp_beat_phase
        inc zp_beat_count

        // rotate bar colours on beat
        inc zp_bar_clr_ofs

        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcc !no_beat+
        cmp #BUILDUP_BEAT
        bne !ramp+
        lda #FILT_CUT_LO
        sta zp_filt_cut
        jmp !no_beat+
!ramp:  lda zp_filt_cut
        clc
        adc #FILT_CUT_STEP
        bcs !sat+
        sta zp_filt_cut
        jmp !no_beat+
!sat:   lda #$ff
        sta zp_filt_cut
!no_beat:

        jsr update_line_a
        jsr update_sprites

        // plasma — advance both phases at different rates so the
        // interference pattern morphs rather than just scrolls.
        // xphase = +2 per frame (faster horizontal flow)
        // yphase = +1 per frame (slower vertical drift)
        inc zp_xphase
        inc zp_xphase
        inc zp_yphase

        lda zp_plasma_tgl
        and #1
        bne !odd+
        lda #0
        sta row_base
        lda #13
        sta row_cnt
        jmp !go+
!odd:   lda #1
        sta row_base
        lda #12
        sta row_cnt
!go:
        ldx row_base
!row_lp:
        // write_plasma_row clobbers X (uses it as the per-cell counter
        // inside the inner loop). Stash + restore so the outer loop's
        // row index survives the call. Was a bug: only first row of
        // each half-frame got animated.
        txa
        pha
        jsr write_plasma_row
        pla
        tax
        inx
        inx
        dec row_cnt
        bne !row_lp-

        inc zp_plasma_tgl

        // Bars only render during the buildup phase — pad phase stays
        // calm (just plasma + line A in the dark border). The bars
        // arriving WITH the filter sweep + bass makes them a payoff
        // signal, not constant decoration.
        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcs !bars_on+
        // Pad phase: skip bars, re-trigger this IRQ next frame.
        lda #$ff
        sta VIC_RASTER
        lda #<interrupt
        sta IRQ_VEC
        lda #>interrupt
        sta IRQ_VEC + 1
        jmp !done+
!bars_on:
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters
        sta VIC_RASTER
        lda #<bar_chain_0
        sta IRQ_VEC
        lda #>bar_chain_0
        sta IRQ_VEC + 1
!done:
        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// update_line_a — typewriter reveal of "FOR YEARS NO TIME FOR BREADBIN
// CODE" into row 11. 1 char every LINE_A_PERIOD frames. Cursor is a
// $A0 block at the next-to-reveal position; once all 35 chars are out,
// the cursor disappears and we no-op. Screen is pre-filled with $A0 in
// setup so unrevealed cells already match the plasma backdrop.
//==================================================================
.const LINE_A_PERIOD = 2          // frames per char — 35 chars × 2 = 70 frames (~1.4 s) of typing

update_line_a:
        lda line_a_pos
        cmp #35
        bcs !done+                // line fully revealed → nothing to do
        inc line_a_tick
        lda line_a_tick
        cmp #LINE_A_PERIOD
        bcc !no_advance+
        lda #0
        sta line_a_tick
        ldx line_a_pos
        lda story_line_a,x
        sta $05BA,x               // $05B8 + 2 = column-2 start of row 11
        inc line_a_pos
!no_advance:
        // Blinking cursor at the next-to-reveal cell (block $A0) — already
        // sitting there from the screen-fill, but rewriting each frame
        // makes it survive any later clobber and keeps the "the typewriter
        // hasn't reached here yet" surface visually solid.
        ldx line_a_pos
        cpx #35
        bcs !done+
        lda #$a0
        sta $05BA,x
!done:  rts


//==================================================================
// update_sprites — sprite-letter line B animation state machine.
//
//   PHASE_OFF  → all sprites disabled (pad phase, beat < BUILDUP_BEAT).
//                Enters PHASE_FLY_IN the first frame of buildup.
//   PHASE_FLY_IN → letters drop from Y=0 to Y=SPR_TARGET_Y individually.
//                   Each sprite has a 2-frame stagger via spawn_delay,
//                   and uses fly_in_y[clamped (sp_frame - spawn_delay)]
//                   which encodes the gravity drop + 1 over-shoot bounce
//                   ramp before settling. Total ~32 frames for all 8 to
//                   settle = ~640 ms at 50 Hz.
//   PHASE_BOUNCE → at-target, per-sprite Y wobble derived from
//                   bounce_sine[(sp_frame + phase[i]) & $ff] — gentle
//                   ±2 px breathing.
//   PHASE_FLY_OUT → letters fly up out of frame, FLY_OUT_LEN frames
//                   total. Triggered when zp_beat_count hits
//                   TRANSITION_BEAT - 1.
//==================================================================
update_sprites:
        lda sp_phase
        beq sp_off
        cmp #PHASE_FLY_IN
        beq sp_in
        cmp #PHASE_BOUNCE
        beq sp_bounce
        // else PHASE_FLY_OUT
        jmp sp_out

sp_off:
        // Wait for buildup to arm the drop.
        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcc !rts+
        lda #PHASE_FLY_IN
        sta sp_phase
        lda #0
        sta sp_frame
        // X positions + arm all 8 sprites; they'll Y-update in sp_in.
        ldx #0
!xp:    txa
        asl
        tay
        lda spr_x_table,x
        sta SPR_X,y
        inx
        cpx #8
        bne !xp-
        lda #$ff
        sta SPR_EN
!rts:   rts

sp_in:
        // Per sprite: idx = sp_frame - spawn_delay[s]. Clamp to
        // [0, FLY_IN_LEN-1] and look up fly_in_y[idx].
        ldx #0
!loop:  lda sp_frame
        sec
        sbc spawn_delay,x
        bcs !ok+                  // sp_frame < spawn_delay → not spawned yet
        lda #SPR_SPAWN_Y
        jmp !setY+
!ok:    cmp #FLY_IN_LEN
        bcc !inrange+
        lda #SPR_TARGET_Y         // past the table — already settled
        jmp !setY+
!inrange:
        tay
        lda fly_in_y,y
!setY:  pha
        txa
        asl
        tay
        iny
        pla
        sta SPR_X,y               // SPR_X[2N+1] = SPR_Y[N]
        inx
        cpx #8
        bne !loop-

        inc sp_frame
        lda sp_frame
        cmp #(FLY_IN_LEN + 16)    // last letter (spawn_delay max = 14) + table tail
        bcc !rts+
        lda #PHASE_BOUNCE
        sta sp_phase
        lda #0
        sta sp_frame
!rts:   // also check: are we close to transition? then go straight to FLY_OUT.
        lda zp_beat_count
        cmp #(TRANSITION_BEAT - 1)
        bcc !nope+
        lda #PHASE_FLY_OUT
        sta sp_phase
        lda #0
        sta sp_frame
!nope:  rts

sp_bounce:
        // Per sprite: Y = SPR_TARGET_Y + bounce_sine[(sp_frame + spawn_delay[s]) & $ff]
        ldx #0
!loop:  lda sp_frame
        clc
        adc spawn_delay,x
        tay
        lda bounce_sine,y
        clc
        adc #SPR_TARGET_Y
        pha
        txa
        asl
        tay
        iny
        pla
        sta SPR_X,y
        inx
        cpx #8
        bne !loop-

        inc sp_frame
        // Hold here until transition is one beat away.
        lda zp_beat_count
        cmp #(TRANSITION_BEAT - 1)
        bcc !rts+
        lda #PHASE_FLY_OUT
        sta sp_phase
        lda #0
        sta sp_frame
!rts:   rts

sp_out:
        // Letters fly UP (Y decreases) — accelerating exit.
        // Y = SPR_TARGET_Y - fly_out_dy[(sp_frame + spawn_delay[s]) clamped]
        ldx #0
!loop:  lda sp_frame
        clc
        adc spawn_delay,x
        cmp #FLY_OUT_LEN
        bcc !inrange+
        lda #FLY_OUT_LEN - 1
!inrange: tay
        lda fly_out_dy,y          // accelerating dy table
        // Y = SPR_TARGET_Y - dy; if Y wraps (negative), park at SPR_SPAWN_Y
        sta zp_tmp
        lda #SPR_TARGET_Y
        sec
        sbc zp_tmp
        bcs !inframe+
        lda #SPR_SPAWN_Y
!inframe: pha
        txa
        asl
        tay
        iny
        pla
        sta SPR_X,y
        inx
        cpx #8
        bne !loop-

        inc sp_frame
        lda sp_frame
        cmp #FLY_OUT_LEN
        bcc !rts+
        // done — disable sprites, back to OFF
        lda #PHASE_OFF
        sta sp_phase
        lda #$00
        sta SPR_EN
!rts:   rts


//==================================================================
// Bar IRQ chain — 6 unrolled handlers
//==================================================================
bar_chain_0:
        lda bar_base_colors+0
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+1
        sta VIC_RASTER
        lda #<bar_chain_1
        sta IRQ_VEC
        lda #>bar_chain_1
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_1:
        lda bar_base_colors+1
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+2
        sta VIC_RASTER
        lda #<bar_chain_2
        sta IRQ_VEC
        lda #>bar_chain_2
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_2:
        lda bar_base_colors+2
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+3
        sta VIC_RASTER
        lda #<bar_chain_3
        sta IRQ_VEC
        lda #>bar_chain_3
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_3:
        lda bar_base_colors+3
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+4
        sta VIC_RASTER
        lda #<bar_chain_4
        sta IRQ_VEC
        lda #>bar_chain_4
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_4:
        lda bar_base_colors+4
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+5
        sta VIC_RASTER
        lda #<bar_chain_5
        sta IRQ_VEC
        lda #>bar_chain_5
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_5:
        lda bar_base_colors+5
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+6
        sta VIC_RASTER
        lda #<bar_chain_end
        sta IRQ_VEC
        lda #>bar_chain_end
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_end:
        lda #$00
        sta VIC_BORDER
        lda #$ff
        sta VIC_RASTER
        lda #<interrupt
        sta IRQ_VEC
        lda #>interrupt
        sta IRQ_VEC + 1
        lda #$ff
        sta VIC_IRQ
        rti


//==================================================================
// fadeout
//==================================================================
fadeout:
        sec
        rts


//==================================================================
// Tables
//==================================================================

// Wave: two overlaid sines, 0..15
.align 256
wave:
.for (var i = 0; i < 256; i++) {
        .var s1 = 7.5 + 7.5 * sin(i * 2 * PI / 256)
        .var s2 = 7.5 + 7.5 * sin(i * 4 * PI / 256)
        .byte floor((s1 + s2) * 0.5 + 0.5)
}

// 16-entry hue-stable plasma palette: symmetric blue→cyan→white→cyan→blue.
// Matches screenfill's ripple_palette for visual continuity. Each
// plasma index 0..15 maps to a C64 colour; the symmetry means the
// pattern flows back through itself rather than wrapping abruptly.
plasma_palette:
        .byte $00, $06, $06, $0e, $0e, $03, $03, $01
        .byte $01, $03, $03, $0e, $0e, $06, $06, $00

// Row stagger — each row's phase offset in the wave
row_offset:
.for (var r = 0; r < 25; r++) {
        .byte floor(r * 197 / 25) & 255
}

// Row color RAM base addresses (precomputed)
row_cr_lo:
.for (var r = 0; r < 25; r++) {
        .byte <($d800 + r * 40)
}
row_cr_hi:
.for (var r = 0; r < 25; r++) {
        .byte >($d800 + r * 40)
}

// Bar raster positions
bar_rasters:
.byte 32, 72, 112, 152, 192, 232

// Bar base colours (0-15, offset by zp_bar_clr_ofs each beat)
bar_base_colors:
.byte 2, 4, 5, 7, 3, 6

// Work area (in code space, not ZP)
row_base: .byte 0
row_cnt:  .byte 0

// Story overlay text — uppercase chargen at $1000, codes $01..$1A
// for letters, $20 for space. 35 chars to fit centered in a 40-col
// row (col 2 .. col 36).
//
// "FOR YEARS NO TIME FOR BREADBIN CODE"
//   F=06 O=0F R=12   sp=20   Y=19 E=05 A=01 R=12 S=13   sp=20
//   N=0E O=0F   sp=20   T=14 I=09 M=0D E=05   sp=20
//   F=06 O=0F R=12   sp=20
//   B=02 R=12 E=05 A=01 D=04 B=02 I=09 N=0E   sp=20
//   C=03 O=0F D=04 E=05
story_line_a:
        .byte $06, $0F, $12, $20             // FOR_
        .byte $19, $05, $01, $12, $13, $20   // YEARS_
        .byte $0E, $0F, $20                  // NO_
        .byte $14, $09, $0D, $05, $20        // TIME_
        .byte $06, $0F, $12, $20             // FOR_
        .byte $02, $12, $05, $01, $04, $02, $09, $0E, $20  // BREADBIN_
        .byte $03, $0F, $04, $05             // CODE

//==================================================================
// Sprite-letter state + tables
//==================================================================

// Phase state — PHASE_OFF / FLY_IN / BOUNCE / FLY_OUT.
sp_phase: .byte 0
sp_frame: .byte 0

// Typewriter state for line A.
line_a_pos:  .byte 0    // chars revealed so far (0..35)
line_a_tick: .byte 0    // frame counter, advances pos every LINE_A_PERIOD

// Horizontal positions for the 8 sprite-letters of "AI WROTE". With
// 8-px spacing the phrase reads "AI" then a 1-letter gap then "WROTE"
// (the gap is the SPACE glyph rendered as blanks in sprite #2).
//
// Sprite N at SPR_X = 152 + N*8 → covers screen cols 16..23 (= centred
// under the row-11 line A text). All values <256 so SPR_MSB stays 0.
spr_x_table:
        .byte 152, 160, 168, 176, 184, 192, 200, 208

// Sprite colours — alternating bright pair stays legible over any
// plasma colour the row-13 area happens to be flowing through.
spr_color_table:
        .byte $01, $0d, $01, $0d, $01, $0d, $01, $0d  // white / light-green

// Per-letter spawn-delay (frames after fly-in start that this letter
// begins dropping). Even spacing reads as a "ripple" of letters
// arriving. 0,2,4,...,14 = 8 letters × 2-frame stagger.
spawn_delay:
        .byte 0, 2, 4, 6, 8, 10, 12, 14

// Fly-in Y table — per-letter idx into this drives Y position during
// PHASE_FLY_IN. 0..15: accelerating drop from Y=0 down to SPR_TARGET_Y;
// 16..23: ~12-px overshoot bounce up then back; 24..31: settled.
.align 32
fly_in_y:
.for (var i = 0; i < 32; i++) {
        .var y = 0
        .if (i < 16) {
                .var t = i / 15.0
                .eval y = floor(SPR_TARGET_Y * t * t)
        } else .if (i < 24) {
                .var bp = (i - 16) / 8.0
                .eval y = floor(SPR_TARGET_Y - 12.0 * sin(bp * PI))
        } else {
                .eval y = SPR_TARGET_Y
        }
        .byte y
}

// Bounce sine — ±3 px wobble around SPR_TARGET_Y during PHASE_BOUNCE.
// Stored as signed 8-bit (negative = $FD..$FF). ADC #SPR_TARGET_Y picks
// up the correct Y mod 256.
.align 256
bounce_sine:
.for (var i = 0; i < 256; i++) {
        .byte round(3 * sin(i * 2 * PI / 256)) & $ff
}

// Fly-out dy — increasing per frame; Y = SPR_TARGET_Y - fly_out_dy[i]
// pushes letters UP off-screen with accelerating velocity.
fly_out_dy:
.for (var i = 0; i < 20; i++) {
        .var t = i / 19.0
        .byte floor(SPR_TARGET_Y * t * t)
}


//==================================================================
// Sprite shape data — 8 sprites × 64 bytes at $2000..$21FF.
// Block pointers $80..$87 in screen RAM at $07F8..$07FF select these.
// Each glyph is the C64 Set A uppercase chargen byte stamped into the
// middle of the top 8 rows of a 21-row sprite (8-px-wide letter, 8-px
// margin left + 8-px margin right within the 24-px-wide sprite).
//==================================================================

* = $2000 "SpriteShapes"
.var chargen = LoadBinary("../greets/chargen.bin")
.var phrase_chars = List().add($01, $09, $20, $17, $12, $0F, $14, $05)
                                          //   A    I    _    W    R    O    T    E

.function letter_sprite(code) {
        .var r = List()
        .var base = code * 8
        .for (var row = 0; row < 21; row++) {
                .if (row < 8) {
                        .eval r.add(0)
                        .eval r.add(chargen.get(base + row))
                        .eval r.add(0)
                } else {
                        .eval r.add(0)
                        .eval r.add(0)
                        .eval r.add(0)
                }
        }
        .eval r.add(0)
        .return r
}

.for (var i = 0; i < 8; i++) {
        .var s = letter_sprite(phrase_chars.get(i))
        .for (var b = 0; b < 64; b++) {
                .byte s.get(b)
        }
}
