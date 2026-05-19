//==================================================================
// outline-64 — Coda: title card hold between greets' scroller and
// the end credit roll.
//
// Narrative role: the breather where the story lands. Greets has
// said its piece via the DYCP scroller; the credits are about to
// roll. Between them, the title sits centered on a quiet screen
// for ~10 seconds while the resident chord progression drifts on.
//
// Visuals:
//   row 11  KLOOT AND THE BREADBIN          (chargen ROM uppercase)
//   row 13  BY DEFEEST   FOR X2026
//   border  slow sine colour cycle through col_tab
//   bg      stays black
//   top 5 rows: 16 stars twinkle via colour-RAM toggle (4 banks of 4)
//
// Music: jsr INTRO_MUSIC_PLAY each frame. Drums silent because
// setup zeros $F6 (the gating byte for percussion in my_music_play)
// — the title sits quiet, then the credit roll music takes over.
//
// Transition: after N_FRAMES ticks (~10 s) the IRQ writes $F6 = $30
// and pefchain advances to end.
//
// Memory:
//   $0800-$0AFF  code + col_tab (overlays sinus's old footprint —
//                sinus is no longer resident, so we can reuse)
//   $1000-$125D  intro music tables (inherited via 'I' tag)
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

.const SID_VOL    = $d418
.const SID_V3_FREQLO = $d40e
.const SID_V3_FREQHI = $d40f
.const SID_V3_PULSEL = $d410
.const SID_V3_PULSEH = $d411
.const SID_V3_CTRL = $d412
.const SID_V3_AD = $d413
.const SID_V3_SR = $d414

.const N_FRAMES   = 250               // ~10 s at the half-rate divider
                                      // (250 ticks @ 25 Hz)

// Kloot star — Stage B: 4-sprite 2×2 quad, each X+Y-expanded, forming a
// 96×84 12-lobe Claude-style burst behind the title text.
//
// Each quadrant is a separate 24×21 sprite frame, pre-rendered by
// tools/render_kloot_star.py --quadrant 0..3 with shape params
// (--lobes 12 --inner 2.5 --curve 2.0 --outer 22.0). The --outer
// doubles from Stage A's 11 because the logical star is now 48×42
// (each tile shows one quarter, so the polar function sees a star
// centred just outside the sprite at radius up to 22).
//
//   tile layout (in screen coords)        sprite slot
//   +---------+---------+                 +-----+-----+
//   | TL  q=1 | TR  q=0 |  ←  spr 1, 0  → | spr1| spr0|
//   +---------+---------+                 +-----+-----+
//   | BL  q=2 | BR  q=3 |  ←  spr 2, 3  → | spr2| spr3|
//   +---------+---------+                 +-----+-----+
//
// Memory layout (VIC bank 0; all sprite shape data must live in
// $0000-$0FFF or $2000-$3FFF — VIC sees the chargen ROM at $1000-$1FFF
// in bank 0, so sprite bytes placed there are read as glyph data and
// the sprites render as garbled text. Sprite bases are also chosen as
// multiples of $10 (bits 0-3 clear) so the per-IRQ "ORA #base /
// sta $07f8.." pointer cycling produces all 16 unique frames in
// lockstep:
//   $2800-$2BFF  spr 0 (TR), 16 frames, ptr values $A0..$AF
//   $2C00-$2FFF  spr 1 (TL), 16 frames, ptr values $B0..$BF
//   $3000-$33FF  spr 2 (BL), 16 frames, ptr values $C0..$CF
//   $3400-$37FF  spr 3 (BR), 16 frames, ptr values $D0..$DF
//
// The $30-$37 range overlaps with end's `'P', $30, $44` claim, so
// pefchain has to defer ~2 KB of end's payload (the $3000-$37FF half)
// to a post-coda load chunk. That's a ~0.5 s visible delay at the
// coda → end transition — acceptable for a 96×84 star.
//
// Composition: the quad is horizontally centred on screen (col 160) so
// the title text "KLOOT AND THE BREADBIN" (which spans cols 72-248)
// runs through the middle of the star. $D01B = $0F sets sprites 0-3
// to BACKGROUND priority — the title chars sit on top of the star.
//
// The star fades in at half-rate frame 13 (= ~26 raw frames, aligned
// with the first audible kick from coda_kick) and rotates one shape
// per zp_frame tick (40 ms per shape). 16 unique shapes span 0..30°
// of true rotation; 12-fold symmetry makes the loop seamless. Visual
// full-rotation period: ~0.64 s.
.const KLOOT_SHAPE_BASE_TR = $a0      // $2800 / 64 — spr 0 (TR)
.const KLOOT_SHAPE_BASE_TL = $b0      // $2C00 / 64 — spr 1 (TL)
.const KLOOT_SHAPE_BASE_BL = $c0      // $3000 / 64 — spr 2 (BL)
.const KLOOT_SHAPE_BASE_BR = $d0      // $3400 / 64 — spr 3 (BR)

// Sprite position registers ($D000/$D001 etc.) use VIC's native raster
// coordinate system, NOT 0-indexed display-pixel rows/cols:
//   - Sprite X = 24 puts the sprite's LEFT edge at display column 0
//     (start of the visible 320-px area). Sprite X = 24 + N puts the
//     left edge at display col N.
//   - Sprite Y is the raster line where the TOP of the sprite appears.
//     With $D011 = $1B (25-row mode, RSEL=1), display row N starts at
//     raster 51 + N*8.
//
// 96×84 quad centred at display col 160 / raster 150:
//   star spans cols 112-208, rasters 108-192 (display rows 7-17)
//   title rows 11-13 (rasters 139-162) fall inside the lower-middle band
.const KLOOT_X_LEFT   = 136           // left column of quad: spr 1 (TL), spr 2 (BL)
                                      //   sprite X = 136 → left edge at display col 112
.const KLOOT_X_RIGHT  = 184           // right column: spr 0 (TR), spr 3 (BR)
                                      //   sprite X = 184 → left edge at display col 160
.const KLOOT_Y_TOP    = 108           // top row of quad: spr 0 (TR), spr 1 (TL)
.const KLOOT_Y_BOT    = 150           // bottom row: spr 2 (BL), spr 3 (BR) — top at raster
                                      //   150, sprite 42 tall (Y-expanded), ends at 192

// Stage D animate-in: all 4 sprites start stacked at the centre of the
// quad and interpolate outward over KLOOT_REVEAL_FRAMES zp_frame ticks
// (≈ 480 ms at 25 Hz). The reveal completes one zp_frame tick before
// the first audible kick (zp_kick_count=25 → raw frame 26 ≈ zp_frame 13).
.const KLOOT_X_CENTRE = 160           // midpoint of KLOOT_X_LEFT and KLOOT_X_RIGHT
.const KLOOT_Y_CENTRE = 129           // midpoint of KLOOT_Y_TOP and KLOOT_Y_BOT
.const KLOOT_REVEAL_FRAMES = 24       // 0..23 interpolating, 24+ final positions
                                      // ≈ 960 ms at 25 Hz — slow enough to read

// Coda V3 kick — coda has the unique luxury of "owning" V3 for the
// duration of the part (zp_outro=0 keeps intro's drum gate closed,
// and we override the arp's per-frame writes every IRQ). So we can
// use a real kick ADSR and a proper hard-restart cycle without
// breaking the arp recovery the way it would in intro/interlude.
//
// Technique (a simplified take on lft's "new hard-restart" idea —
// the full stabiliseRC3 dance is overkill for a single sub-bass kick
// at 60 BPM):
//   beat frame   :  CTRL = $10  (triangle, gate OFF) → envelope
//                   releases through R=0 = instant down to 0.
//                   Set freq HIGH (the click transient).
//   next frame   :  CTRL = $11  (triangle, gate ON)  → fresh attack,
//                   envelope rises A=0 to peak, then D=8 decay.
//   body frames  :  sweep freq down for the 808 thump.
//
// V3's ADSR is set once in setup ($d413=$08, $d414=$00) and stays
// kick-shaped for the whole part — there's no arp on V3 here to
// fight with.
.const KICK_PERIOD  = 50              // ~1 s between kicks @ 50 Hz (60 BPM)
.const KICK_LEN     = 12              // body frames
.const KICK_FREQ_HI = $18             // start pitch (~360 Hz click)
.const KICK_FLOOR   = $03             // end pitch (~46 Hz body)
.const KICK_SWEEP   = $02             // hi-byte decrement per frame

.const INTRO_MUSIC_PLAY = $119e

.const zp_timer       = $f6           // transition: set to $30 to trigger pefchain
.const zp_kick_count  = $f7           // IRQ countdown to next beat
.const zp_kick_state  = $f8           // 0=idle, KICK_LEN+1=hard-restart frame,
                                      //         1..KICK_LEN=body frames
                                      // Avoid $f9/$fa — intro's my_music_play
                                      // clobbers them every JSR.
.const zp_subtick     = $fb           // half-rate divider toggle
.const zp_frame       = $fc           // animation tick (0..N_FRAMES-1)
                                      // zp_kick_freq lives in code RAM (not zp)
                                      // since we're tight on $F6..$FC zp.


* = $0800 "Coda"


//==================================================================
// setup
//==================================================================
setup:
        lda #0
        sta zp_timer
        sta zp_subtick
        sta zp_frame
        sta zp_kick_state                // idle until first beat

        // Coda owns V3 — pre-load the kick ADSR shape so each beat
        // gets a real attack→decay envelope. The arp (V3) would
        // normally fight with this, but in coda we never let it run:
        // the IRQ overrides $D40E/$D40F/$D412 every frame.
        lda #$08                        // A=0, D=8 → ~150 ms decay
        sta SID_V3_AD
        lda #$00                        // S=0, R=0 → silence between hits
        sta SID_V3_SR
        // Triangle waveform, gate off — V3 is silent until first beat.
        lda #$10
        sta SID_V3_CTRL
        // Float kick_freq sentinel so the first body frame paints it.
        sta kick_freq
        // First kick fires after a longer lead-in so the animate-in
        // reveal (KLOOT_REVEAL_FRAMES × 2 raw frames ≈ 960 ms) has
        // time to complete before the first thump lands.
        lda #55                         // ~1.1 s lead-in
        sta zp_kick_count

        // ---- Kloot star quad — 96×84 12-lobe Claude burst (Stage B+D) ----
        // Sprites 0-3 form a 2×2 grid, each X+Y-expanded (48×42 on screen).
        // All four start COLLAPSED at the centre of the final layout
        // (KLOOT_X_CENTRE, KLOOT_Y_CENTRE) and animate-in outward over
        // the first KLOOT_REVEAL_FRAMES zp_frame ticks via the IRQ's
        // position-interpolation tables (Stage D).
        lda #$0f                        // bits 0-3 = sprites 0-3
        sta $d017                       // Y expand all 4
        sta $d01d                       // X expand all 4
        sta $d01b                       // background priority: title chars in front

        // Initial positions: all 4 sprites stacked at the centre.
        lda #KLOOT_X_CENTRE
        sta $d000
        sta $d002
        sta $d004
        sta $d006
        lda $d010
        and #$f0                        // clear X-high bits for sprites 0-3
        sta $d010
        lda #KLOOT_Y_CENTRE
        sta $d001
        sta $d003
        sta $d005
        sta $d007

        // Sprites enabled from frame 0 — the explode-out IS the reveal.
        lda #$0f
        sta $d015

        // All four quadrants share the Claude orange.
        lda #$08
        sta $d027                       // spr 0
        sta $d028                       // spr 1
        sta $d029                       // spr 2
        sta $d02a                       // spr 3

        // Sprite shape pointers — each quadrant lives at a different base
        // address but all advance through their 16-frame rotation in lockstep.
        lda #KLOOT_SHAPE_BASE_TR        // $A0 → $2800 (TR)
        sta $07f8
        lda #KLOOT_SHAPE_BASE_TL        // $4C → $1300 (TL)
        sta $07f9
        lda #KLOOT_SHAPE_BASE_BL        // $5C → $1700 (BL)
        sta $07fa
        lda #KLOOT_SHAPE_BASE_BR        // $6C → $1B00 (BR)
        sta $07fb

        lda #$00
        sta kloot_shape                 // counter 0..15 (incremented before write)

        // VIC: text mode, ROM chargen $1000 (uppercase), screen $0400.
        lda #$1b                        // DEN=1, RSEL=1, YSCROLL=3
        sta VIC_CTRL1
        lda #$14                        // screen $0400, chargen $1000
        sta VIC_MEM
        lda #$08                        // CSEL=1, no MCM
        sta VIC_CTRL2

        // Clear $D011 bit 7 so raster compare lands on visible scanlines.
        lda VIC_CTRL1
        and #%01111111
        sta VIC_CTRL1

        // Border + bg black to start (border cycles per frame).
        lda #$00
        sta VIC_BORDER
        sta VIC_BG

        // Clear screen RAM to space ($20).
        lda #$20
        ldx #0
!clr:   sta SCREEN + $000,x
        sta SCREEN + $100,x
        sta SCREEN + $200,x
        sta SCREEN + $2e8,x
        inx
        bne !clr-

        // Clear colour RAM to dark grey ($0E) — otherwise leftover
        // colours from greets leak into the background.
        lda #$0e
        ldx #0
!cclr:  sta COL_RAM + $000,x
        sta COL_RAM + $100,x
        sta COL_RAM + $200,x
        sta COL_RAM + $2e8,x
        inx
        bne !cclr-

        // ---- paint the title text ----
        // Row 11 starts at $0400 + 11*40 = $05B8.
        // "KLOOT AND THE BREADBIN" = 22 chars, center at col 9.
        // Row 13 ($0608): "BY DEFEEST   FOR X2026" = 22 chars, col 9.
        ldx #0
!t1:    lda title_main,x
        sta $05B8 + 9,x
        inx
        cpx #22
        bne !t1-

        ldx #0
!t2:    lda title_sub,x
        sta $0608 + 9,x
        inx
        cpx #22
        bne !t2-

        // ---- colour the title rows ----
        // Title row: white. Sub row: light grey. Everything else: $0E.
        // Colour RAM row 11 starts at $D800 + 11*40 = $D9B8.
        // Row 13: $DA08.
        ldx #0
        lda #$01                        // white
!c1:    sta $D9B8 + 9,x
        inx
        cpx #22
        bne !c1-

        ldx #0
        lda #$0f                        // light grey
!c2:    sta $DA08 + 9,x
        inx
        cpx #22
        bne !c2-

        // Settle SID: drums OFF (zp_timer = $00 gates the percussion
        // in intro's my_music_play). Vol restored to max.
        lda #$1f
        sta SID_VOL

        // Raster IRQ at top of visible area.
        lda #$32                        // line 50
        sta VIC_RASTER
        lda #$01
        sta VIC_IRQEN

        rts


//==================================================================
// fadeout — no-op, transition is triggered from interrupt.
//==================================================================
fadeout:
        sec
        rts


//==================================================================
// interrupt — per-frame raster IRQ.
//
// Per frame:
//   - jsr INTRO_MUSIC_PLAY (chord pad + lead on V1/V2, V3 arp is
//     about to get overwritten by our kick)
//   - SAMPLE zp_kick_state into kloot_bob_now BEFORE coda_kick runs,
//     so the bob value peaks on the first audible kick frame (state 12)
//     rather than one frame late.
//   - kick state machine on V3 (hard-restart per beat, sweep body)
//   - half-rate tick: zp_frame advances every 2nd IRQ, drives shape +
//     animate-in base positions
//   - 50 Hz: write sprite (X, Y+bob) for all 4 quadrants
//   - star_field: twinkle 16 stars in top rows (4 banks of 4)
//   - if zp_frame >= N_FRAMES, set $F6 = $30 (transition)
//   - else border = col_tab[zp_frame] for slow sine colour cycle
//==================================================================
interrupt:
        jsr INTRO_MUSIC_PLAY

        // Stage D sound-bound bob: sample the kick state BEFORE
        // coda_kick decrements it. State 12 = first audible kick frame
        // (gate-on, peak dip); state 0 = idle (no dip).
        ldx zp_kick_state
        lda bob_table,x
        sta kloot_bob_now

        jsr star_field
        jsr coda_kick

        // half-rate divider — drives shape advance + animate-in lookup
        lda zp_subtick
        eor #1
        sta zp_subtick
        bne !skip_inc+
        inc zp_frame
        // Advance the Kloot star shape on each zp_frame tick (25 Hz).
        // 16 unique shapes cover 0..30° (12-fold symmetric, or 0..360°
        // if --asymmetry was used at render time); the loop is seamless.
        inc kloot_shape
        lda kloot_shape
        and #$0f
        sta kloot_shape
        // Write all 4 sprite pointers (TR, TL, BL, BR) from this single
        // counter — each quadrant uses a different base address but
        // advances in lockstep. ORA works because every base has bits
        // 0-3 clear.
        ora #KLOOT_SHAPE_BASE_TR        // $A0 | shape  → $A0..$AF
        sta $07f8
        lda kloot_shape
        ora #KLOOT_SHAPE_BASE_TL        // $B0 | shape  → $B0..$BF
        sta $07f9
        lda kloot_shape
        ora #KLOOT_SHAPE_BASE_BL        // $C0 | shape  → $C0..$CF
        sta $07fa
        lda kloot_shape
        ora #KLOOT_SHAPE_BASE_BR        // $D0 | shape  → $D0..$DF
        sta $07fb

        // Stage D animate-in: pick the interpolated base positions for
        // this zp_frame. Tables hold 13 entries (0..12); zp_frame is
        // clamped to 12 so post-reveal frames all use the final layout.
        ldx zp_frame
        cpx #KLOOT_REVEAL_FRAMES
        bcc !pos_ok+
        ldx #KLOOT_REVEAL_FRAMES
!pos_ok:
        lda kloot_x_left_table,x
        sta kloot_x_left_base
        lda kloot_x_right_table,x
        sta kloot_x_right_base
        lda kloot_y_top_table,x
        sta kloot_y_top_base
        lda kloot_y_bot_table,x
        sta kloot_y_bot_base
!skip_inc:

        // Write sprite positions every IRQ (50 Hz) so the Y-bob has
        // 20 ms granularity even though the animate-in base values
        // only update at 25 Hz.
        lda kloot_x_right_base
        sta $d000                       // spr 0 TR X
        sta $d006                       // spr 3 BR X
        lda kloot_x_left_base
        sta $d002                       // spr 1 TL X
        sta $d004                       // spr 2 BL X

        // Y = base + bob (same bob offset on all 4 sprites).
        lda kloot_y_top_base
        clc
        adc kloot_bob_now
        sta $d001                       // spr 0 TR Y
        sta $d003                       // spr 1 TL Y
        lda kloot_y_bot_base
        clc
        adc kloot_bob_now
        sta $d005                       // spr 2 BL Y
        sta $d007                       // spr 3 BR Y

        lda zp_frame
        cmp #N_FRAMES
        bcc !run+
        lda #$30
        sta zp_timer
        lda #$00
        sta VIC_BORDER                  // settle to black before transition
        sta $d015                       // turn all 4 star sprites off
        jmp !ack+

!run:
        ldy zp_frame
        lda col_tab,y
        sta VIC_BORDER

!ack:
        lda #$ff
        sta VIC_IRQ
        rti


//==================================================================
// coda_kick — V3 percussion state machine.
//
// Runs every IRQ AFTER intro's my_music_play has written its arp
// freq into V3. We overwrite V3 freq + ctrl, so the arp doesn't
// sound. Envelope state is owned by us via V3's ADSR (set in setup).
//
// State machine:
//   zp_kick_state == 0       : idle. Decrement zp_kick_count; when
//                              it reaches 0, arm a new beat by
//                              writing CTRL = $10 (triangle, gate
//                              OFF) — this starts the envelope's
//                              release (R=0 → instant to zero) so
//                              the next frame's gate=1 gives a
//                              clean fresh attack.
//   zp_kick_state == KICK_LEN: body frame 0 — the FIRST tick after
//                              hard restart. Set fresh freq, write
//                              CTRL = $11 (triangle + gate ON). The
//                              envelope sees a 0→1 transition and
//                              starts a fresh attack from zero.
//   zp_kick_state in 1..KL-1 : body frames. Sweep freq down, keep
//                              CTRL = $11 (no waveform retrigger,
//                              envelope decays naturally per AD).
//   zp_kick_state == 0 again : body done. Reset zp_kick_count for
//                              next beat. V3 envelope sits at S=0.
//==================================================================
coda_kick:
        lda zp_kick_state
        bne !body+
        // ---- idle phase: count down to next beat ----
        dec zp_kick_count
        bne !done+
        // arm: hard restart this frame, body starts next frame
        lda #KICK_LEN
        sta zp_kick_state
        lda #KICK_FREQ_HI
        sta kick_freq
        lda #$10                        // triangle + gate OFF
        sta SID_V3_CTRL
        // Reset the period counter NOW so it's already armed for the
        // beat after this one.
        lda #KICK_PERIOD
        sta zp_kick_count
        rts
!body:
        // ---- body phase: drive V3 freq + gate ----
        cmp #KICK_LEN
        beq !first+
        // body frame 1..KICK_LEN-1 — sweep freq down
        lda kick_freq
        sec
        sbc #KICK_SWEEP
        cmp #KICK_FLOOR
        bcs !sweep_ok+
        lda #KICK_FLOOR
!sweep_ok:
        sta kick_freq
        jmp !write+
!first:
        // body frame 0 (first audible tick) — keep starting freq
!write:
        lda #$00
        sta SID_V3_FREQLO
        lda kick_freq
        sta SID_V3_FREQHI
        lda #$11                        // triangle + gate ON
        sta SID_V3_CTRL
        dec zp_kick_state
!done:
        rts


// Kick freq shadow — lives in code RAM rather than zp because the
// zp_f6..f8 window is already crowded.
kick_freq:
        .byte 0


// Kloot star shape counter (0..15), wraps each "quarter rotation"
// visually. Lives in code RAM for the same reason as kick_freq.
kloot_shape:
        .byte 0


//==================================================================
// Stage D scratch + tables for animate-in and sound-bound bob.
//
// kloot_bob_now      — bob_table[zp_kick_state] sampled BEFORE
//                      coda_kick advances the state. Added to every
//                      sprite Y this IRQ.
// kloot_*_base       — base position picked from the animate-in
//                      tables on each zp_frame tick (25 Hz).
//                      Sprite registers get (base + bob) every IRQ.
//==================================================================
kloot_bob_now:        .byte 0
kloot_x_left_base:    .byte 0
kloot_x_right_base:   .byte 0
kloot_y_top_base:     .byte 0
kloot_y_bot_base:     .byte 0

// Animate-in position tables — linear interpolation from
// KLOOT_*_CENTRE at index 0 to the final KLOOT_X_LEFT / RIGHT /
// Y_TOP / BOT at index KLOOT_REVEAL_FRAMES. KA's integer division
// gives slightly stepped progressions which read as smoother than
// the table's 12 unique values would suggest at 25 Hz.
.const KLOOT_DX = KLOOT_X_RIGHT - KLOOT_X_CENTRE    // = 24
.const KLOOT_DY = KLOOT_Y_BOT   - KLOOT_Y_CENTRE    // = 21

kloot_x_left_table:
.for (var i = 0; i <= KLOOT_REVEAL_FRAMES; i++) {
        .byte KLOOT_X_CENTRE - i * KLOOT_DX / KLOOT_REVEAL_FRAMES
}
kloot_x_right_table:
.for (var i = 0; i <= KLOOT_REVEAL_FRAMES; i++) {
        .byte KLOOT_X_CENTRE + i * KLOOT_DX / KLOOT_REVEAL_FRAMES
}
kloot_y_top_table:
.for (var i = 0; i <= KLOOT_REVEAL_FRAMES; i++) {
        .byte KLOOT_Y_CENTRE - i * KLOOT_DY / KLOOT_REVEAL_FRAMES
}
kloot_y_bot_table:
.for (var i = 0; i <= KLOOT_REVEAL_FRAMES; i++) {
        .byte KLOOT_Y_CENTRE + i * KLOOT_DY / KLOOT_REVEAL_FRAMES
}

// Sound-bound bob: indexed by zp_kick_state (0..KICK_LEN=12). The
// state value SAMPLED before coda_kick runs means index 12 = first
// audible kick frame (peak dip), index 0 = idle (no dip). Sprite Y
// values get this added so the star "drops" on each kick and
// recovers over the body window. Max dip is 12 px — about 14% of
// the 84-px tall sprite quad, clearly visible.
bob_table:
        .byte 0     // state 0 — idle, no dip
        .byte 0     // state 1 — last body frame, settled
        .byte 1     // state 2
        .byte 2     // state 3
        .byte 3     // state 4
        .byte 4     // state 5
        .byte 5     // state 6
        .byte 7     // state 7
        .byte 8     // state 8
        .byte 9     // state 9
        .byte 10    // state 10
        .byte 11    // state 11
        .byte 12    // state 12 — first audible kick frame, peak dip


//==================================================================
// star_field — twinkle 16 stars in the top 5 screen rows.
//
// Runs every frame, only updates on half-rate ticks (zp_subtick==0).
// 16 pre-defined colour RAM positions are grouped into 4 banks of 4.
// Each update writes all 16: bright white ($0F) for the active bank,
// dark grey ($0E) for the others. The active bank rotates every 4
// frames of zp_frame (~160ms per bank).
//
// Uses $f9 as temp (safe: my_music_play clobbers it before we run).
//==================================================================
star_field:
        lda zp_subtick
        bne !skip+

        lda zp_frame
        and #$0c                // active bank: 0,4,8,12
        sta $f9

        ldx #15
!loop:
        txa
        and #$0c                // which bank this star belongs to
        cmp $f9
        bne !dim+
        lda #$0f                // bright white
        jmp !wcol+
!dim:   lda #$0e                // dark grey (matches bg rows)
!wcol:
        ldy star_pos,x
        sta COL_RAM,y
        dex
        bpl !loop-
!skip:
        rts


//==================================================================
// Star position table — 16 offsets into COL_RAM ($D800), rows 0-4.
// Grouped as 4 banks of 4 for the active-bank twinkle scheme.
// All offsets < 256 so they index via Y register.
//==================================================================
star_pos:
        .byte $02, $2e, $5a, $a8         // bank 0: top spread
        .byte $0a, $3c, $68, $7c         // bank 1: mid-top spread
        .byte $1c, $4a, $76, $8c         // bank 2: mid spread
        .byte $24, $9c, $b8, $c8         // bank 3: side spread


//==================================================================
// title text — uppercase chargen at $1000, screencodes $01..$1A
// for A..Z, $20 for space.
//
// "KLOOT AND THE BREADBIN"
//   K=0B L=0C O=0F O=0F T=14 _=20
//   A=01 N=0E D=04 _=20
//   T=14 H=08 E=05 _=20
//   B=02 R=12 E=05 A=01 D=04 B=02 I=09 N=0E
//==================================================================
title_main:
        .byte $0B, $0C, $0F, $0F, $14, $20    // KLOOT_
        .byte $01, $0E, $04, $20              // AND_
        .byte $14, $08, $05, $20              // THE_
        .byte $02, $12, $05, $01, $04, $02, $09, $0E    // BREADBIN

// "BY DEFEEST   FOR X2026"  (22 chars)
//   B=02 Y=19 _=20  D=04 E=05 F=06 E=05 E=05 S=13 T=14 _=20 _=20 _=20
//   F=06 O=0F R=12 _=20  X=18  2=32 0=30 2=32 6=36
title_sub:
        .byte $02, $19, $20                                 // BY_
        .byte $04, $05, $06, $05, $05, $13, $14, $20        // DEFEEST_
        .byte $20, $20                                       // __
        .byte $06, $0F, $12, $20                            // FOR_
        .byte $18                                            // X
        .byte $32, $30, $32, $36                            // 2026


//==================================================================
// Border colour table — 256-entry slow sine through a calm palette
// (mostly blues / cyans, no harsh contrasts — this is the breather).
//==================================================================
.align 256
col_tab:
.for (var i = 0; i < 256; i++) {
        // 4-step low-saturation palette indexed by sine phase.
        // Bands: $00 black / $06 blue / $0E light-blue / $0F light-grey.
        .var s = floor(2 + 1.99 * sin(i * 2 * PI / 256))   // 0..3
        .if (s == 0) { .byte $00 }
        .if (s == 1) { .byte $06 }
        .if (s == 2) { .byte $0e }
        .if (s == 3) { .byte $0f }
}


//==================================================================
// Kloot star sprite shapes live at $2800-$2BFF (sprite pointer values
// $A0..$AF). NOT emitted from this source — they're a separate binary
// (parts/coda/kloot_star.bin) passed to mkpef as a second data file
// in build.sh, so the KA PRG stays contiguous within $0800-$0AFF and
// doesn't drag a 7 KB zero-padded chunk along the way (which would
// collide with greets' $20-$27 sprite font during background loading).
// To re-render the star: run tools/render_kloot_star.py — see header
// at the top of this file for the parameters used.
//==================================================================
