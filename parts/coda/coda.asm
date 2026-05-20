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
//   row 11  KLOTEN MET DE BROODTROMMEL      (chargen ROM uppercase)
//   row 13  A DIGITAL LUNCH EXPERIENCE
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
//   $0800-$09xx  code
//   $0A00-$0AFF  col_tab (border colour cycle)
//   $0B00-$0BFF  sin_tab (twin-star orbital motion)
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
// the title text "KLOTEN MET DE BROODTROMMEL" (which spans cols 56-264)
// runs through the middle of the star. $D01B alternates between $FF
// (sprites behind title) and $00 (sprites in front) every ~1.3 s,
// so the stars appear to orbit through the text plane in 3D.
//
// Stage E — PRE-RENDERED zoom. Each quadrant's binary now holds 24
// frames concatenated: 8 zoom (small → full, with rotation built in)
// + 16 steady-rotation. Sprite positions stay FIXED at the final
// quad layout for the entire part — the "growth" comes from the
// rendered content getting bigger inside the same sprite cells,
// which avoids the centre-stack overlap mess the position-animate
// approach had (each quadrant's star centre lives at a different
// corner, so stacking them looks like a 4-cornered cross).
//
// Single counter `kloot_shape` (0..23) walks the sequence. After
// frame 23 it wraps to frame 8 — zoom plays once, rotation loops
// forever from there. 12-fold star symmetry + continuous rotation
// step across both phases makes the loop seamless.
//
// Pointer values (sprite block = byte address / 64). Stride 24 per
// quadrant = $18 → each quadrant's 24 pointers span its 1.5 KB:
//   $80..$97   TR  ($2000-$25FF)
//   $98..$AF   TL  ($2600-$2BFF)
//   $B0..$C7   BL  ($2C00-$31FF)
//   $C8..$DF   BR  ($3200-$37FF)
.const KLOOT_SHAPE_BASE_TR = $80      // $2000 / 64 — spr 0 (TR)
.const KLOOT_SHAPE_BASE_TL = $98      // $2600 / 64 — spr 1 (TL)
.const KLOOT_SHAPE_BASE_BL = $b0      // $2C00 / 64 — spr 2 (BL)
.const KLOOT_SHAPE_BASE_BR = $c8      // $3200 / 64 — spr 3 (BR)
.const KLOOT_FRAMES_TOTAL  = 24       // 8 zoom + 16 rotation
.const KLOOT_FRAMES_ZOOM   = 8        // zoom plays once, then wrap-to-8

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

// Twin-star orbit centre + quad half-dimensions.
.const KLOOT_X_CENTRE = (KLOOT_X_LEFT + KLOOT_X_RIGHT) / 2  // = 160
.const KLOOT_Y_CENTRE = (KLOOT_Y_TOP  + KLOOT_Y_BOT)  / 2  // = 129
.const KLOOT_DX = KLOOT_X_RIGHT - KLOOT_X_CENTRE      // = 24 — quad half-width
.const KLOOT_DY = KLOOT_Y_BOT   - KLOOT_Y_CENTRE      // = 21 — quad half-height

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

// Twin-star orbital motion parameters.
.const ORBIT_RADIUS  = 40               // pixel radius (±40 px)
.const ORBIT_SPEED_1 = 1                // star 1: ~5 s per cycle at 50 Hz
.const ORBIT_SPEED_2 = 2                // star 2: ~2.5 s per cycle

// Shape advance dividers — each star's shape counter advances every
// N half-rate ticks so they rotate at fundamentally different speeds.
// Star 1: /3 ≈ 8.3 Hz, star 2: /2 = 12.5 Hz. Try /1 + /3 for 25+8 Hz.
.const SHAPE_DIV_1 = 3                  // star 1: advance every 3rd half-rate tick
.const SHAPE_DIV_2 = 2                  // star 2: advance every 2nd tick

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
        // First kick fires after the animate-in reveal completes
        // (KLOOT_REVEAL_FRAMES × 2 raw frames ≈ 2 s) so the slow
        // zoom-in lands fully before the first thump.
        lda #110                        // ~2.2 s lead-in
        sta zp_kick_count

        // ---- Kloot star quad — 96×84 12-lobe Claude burst (Stage E) ----
        // Sprites 0-3 form a 2×2 grid at fixed positions for the whole
        // part. The pre-rendered 24-frame sequence per quadrant supplies
        // the visible zoom (small → full) + ongoing rotation; no per-IRQ
        // sprite-position math needed.
        lda #$0f                        // bits 0-3 = sprites 0-3
        sta $d017                       // Y expand all 4
        sta $d01d                       // X expand all 4
        sta $d01b                       // initial: sprites behind text
                                        // (toggled by priority-swap later)

        // Final positions written ONCE — never touched again.
        lda #KLOOT_X_RIGHT
        sta $d000                       // spr 0 TR X
        sta $d006                       // spr 3 BR X
        lda #KLOOT_X_LEFT
        sta $d002                       // spr 1 TL X
        sta $d004                       // spr 2 BL X
        lda $d010
        and #$f0                        // clear X-high bits for sprites 0-3
        sta $d010
        lda #KLOOT_Y_TOP
        sta $d001                       // spr 0 TR Y
        sta $d003                       // spr 1 TL Y
        lda #KLOOT_Y_BOT
        sta $d005                       // spr 2 BL Y
        sta $d007                       // spr 3 BR Y

        // Sprites enabled from frame 0 — frame 0 is the smallest zoom
        // step (a tiny brown point at the quad centre), grows from there.
        lda #$0f
        sta $d015

        // All four quadrants share the Kloot brown ($09).
        lda #$09
        sta $d027                       // spr 0
        sta $d028                       // spr 1
        sta $d029                       // spr 2
        sta $d02a                       // spr 3

        // Initial shape pointers = frame 0 of each quadrant's sequence
        // (the smallest zoom step).
        lda #KLOOT_SHAPE_BASE_TR        // $80 → $2000 (TR frame 0)
        sta $07f8
        lda #KLOOT_SHAPE_BASE_TL        // $98 → $2600 (TL frame 0)
        sta $07f9
        lda #KLOOT_SHAPE_BASE_BL        // $B0 → $2C00 (BL frame 0)
        sta $07fa
        lda #KLOOT_SHAPE_BASE_BR        // $C8 → $3200 (BR frame 0)
        sta $07fb

        // ---- Star 2 — second Kloot star quad (sprites 4-7) ----
        // Enable sprites 4-7 with same expand + bg priority as star 1.
        // Reuses the same shape data at $2000-$37FF but with an
        // independent rotation counter, so the lobe angles drift apart.
        lda $d015
        ora #$f0                        // bits 4-7
        sta $d015
        lda $d017
        ora #$f0
        sta $d017                       // Y expand
        lda $d01d
        ora #$f0
        sta $d01d                       // X expand
        lda $d01b
        ora #$f0
        sta $d01b                       // bg priority: tracks swap_flag

        // Sprite positions — same quad layout as star 1.
        lda #KLOOT_X_RIGHT
        sta $d008                       // spr 4 TR X
        sta $d00e                       // spr 7 BR X
        lda #KLOOT_X_LEFT
        sta $d00a                       // spr 5 TL X
        sta $d00c                       // spr 6 BL X
        lda $d010
        and #$0f                        // clear bits 4-7
        sta $d010
        lda #KLOOT_Y_TOP
        sta $d009                       // spr 4 TR Y
        sta $d00b                       // spr 5 TL Y
        lda #KLOOT_Y_BOT
        sta $d00d                       // spr 6 BL Y
        sta $d00f                       // spr 7 BR Y

        // Star 2 colours: cyan ($0E) vs star 1's brown ($09).
        lda #$0e
        sta $d02b                       // spr 4
        sta $d02c                       // spr 5
        sta $d02d                       // spr 6
        sta $d02e                       // spr 7

        // Star 2 starts at frame 8 (first rotation frame) so the two
        // stars are out of phase — one zooms in from a dot while the
        // other is already full-size and rotating.
        lda #KLOOT_SHAPE_BASE_TR + 8
        sta $07fc                       // spr 4 = TR
        lda #KLOOT_SHAPE_BASE_TL + 8
        sta $07fd                       // spr 5 = TL
        lda #KLOOT_SHAPE_BASE_BL + 8
        sta $07fe                       // spr 6 = BL
        lda #KLOOT_SHAPE_BASE_BR + 8
        sta $07ff                       // spr 7 = BR

        lda #$00
        sta kloot_shape_1               // star 1 counter 0..23
        lda #KLOOT_FRAMES_ZOOM          // star 2 starts at rotation frame 0
        sta kloot_shape_2               // (= frame 8 in 24-frame sequence)
        lda #SHAPE_DIV_1
        sta shape_div1                  // init divider so first tick fires
        lda #SHAPE_DIV_2
        sta shape_div2
        lda #$00
        sta star1_orbit_phase           // orbital phase counters
        lda #192                        // star 2 starts near opposite side
        sta star2_orbit_phase

        // Initialise priority-swap state.
        lda #$00
        sta swap_flag
        // Pre-compute the initial phase-difference bit 6 so the first
        // frame's comparison works correctly.
        lda star2_orbit_phase
        sec
        sbc star1_orbit_phase
        and #$40
        sta last_safe_bit

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

        // ---- paint star chars (asterisks) at 32 full-screen positions ----
        // star_field below animates COLOUR RAM at these positions; chars
        // must exist for colour writes to have visible pixels. Asterisk
        // ($2A) on the dark-grey background reads like sparkles.
        // Self-modifying STA patches the screen address per-star to avoid
        // ZP indirect (which would clobber zp_subtick / zp_frame).
        ldx #31
!star:  txa
        asl                            // *2 for .word offset
        tay
        lda star_pos,y                 // COL_RAM address low
        sta star_patch_scr              // patch into STA operand
        lda star_pos + 1,y             // COL_RAM address high
        sta star_patch_scr + 1
        // Convert COL_RAM -> SCREEN:  SCREEN = COL_RAM - ($D800 - $0400)
        sec
        lda star_patch_scr
        sbc #$00
        sta star_patch_scr
        lda star_patch_scr + 1
        sbc #$d4
        sta star_patch_scr + 1
        lda #$2a                       // asterisk char
star_patch_scr:
        sta $0400                      // operand patched per star
        dex
        bpl !star-

        // ---- paint the title text ----
        // Row 11 starts at $0400 + 11*40 = $05B8.
        // "KLOTEN MET DE BROODTROMMEL" = 26 chars, center at col 7.
        // Row 13 ($0608): "A DIGITAL LUNCH EXPERIENCE" = 26 chars, col 7.
        ldx #0
!t1:    lda title_main,x
        sta $05B8 + 7,x
        inx
        cpx #26
        bne !t1-

        ldx #0
!t2:    lda title_sub,x
        sta $0608 + 7,x
        inx
        cpx #26
        bne !t2-

        // ---- colour the title rows ----
        // Title row: white. Sub row: light grey. Everything else: $0E.
        // Colour RAM row 11 starts at $D800 + 11*40 = $D9B8.
        // Row 13: $DA08.
        ldx #0
        lda #$01                        // white
!c1:    sta $D9B8 + 7,x
        inx
        cpx #26
        bne !c1-

        ldx #0
        lda #$0f                        // light grey
!c2:    sta $DA08 + 7,x
        inx
        cpx #26
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
//   - kick state machine on V3 (hard-restart per beat, sweep body)
//   - half-rate tick: zp_frame++ + kloot_shape++ (wrap 24→8) +
//     4 sprite pointer writes
//   - star_field: twinkle 16 stars in top rows (4 banks of 4)
//   - if zp_frame >= N_FRAMES, set $F6 = $30 (transition)
//   - else border = col_tab[zp_frame] for slow sine colour cycle
//
// Sprite positions are FIXED in setup (Stage E pre-rendered zoom) —
// no per-IRQ X/Y math here. The "growth" lives in the sprite shapes.
//==================================================================
interrupt:
        jsr INTRO_MUSIC_PLAY

        jsr star_field
        jsr coda_kick

        // half-rate divider — drives shape advance
        lda zp_subtick
        eor #1
        sta zp_subtick
        bne !over+
        jmp !half_rate+
!over:  jmp !skip_inc+
!half_rate:
        inc zp_frame
        // Advance shape counters via independent dividers so each star
        // rotates at a fundamentally different speed (/3 vs /2).
        dec shape_div1
        bne !skip1+
        inc kloot_shape_1
        lda kloot_shape_1
        cmp #KLOOT_FRAMES_TOTAL
        bne !no_wrap1+
        lda #KLOOT_FRAMES_ZOOM
        sta kloot_shape_1
!no_wrap1:
        lda #SHAPE_DIV_1
        sta shape_div1
!skip1:
        dec shape_div2
        bne !skip2+
        inc kloot_shape_2
        lda kloot_shape_2
        cmp #KLOOT_FRAMES_TOTAL
        bne !no_wrap2+
        lda #KLOOT_FRAMES_ZOOM
        sta kloot_shape_2
!no_wrap2:
        lda #SHAPE_DIV_2
        sta shape_div2
!skip2:
        // ---- Write sprite pointers — conditional on swap_flag ----
        // swap_flag=0: star 1 (brown) → sprites 0-3, star 2 (cyan) → 4-7
        // swap_flag=1: star 2 (cyan)  → sprites 0-3, star 1 (brown) → 4-7
        lda swap_flag
        beq !normal_ptr+
        // Swapped: spr 0-3 = star2, spr 4-7 = star1
        lda kloot_shape_2
        clc
        adc #KLOOT_SHAPE_BASE_TR
        sta $07f8
        lda kloot_shape_2
        clc
        adc #KLOOT_SHAPE_BASE_TL
        sta $07f9
        lda kloot_shape_2
        clc
        adc #KLOOT_SHAPE_BASE_BL
        sta $07fa
        lda kloot_shape_2
        clc
        adc #KLOOT_SHAPE_BASE_BR
        sta $07fb
        lda kloot_shape_1
        clc
        adc #KLOOT_SHAPE_BASE_TR
        sta $07fc
        lda kloot_shape_1
        clc
        adc #KLOOT_SHAPE_BASE_TL
        sta $07fd
        lda kloot_shape_1
        clc
        adc #KLOOT_SHAPE_BASE_BL
        sta $07fe
        lda kloot_shape_1
        clc
        adc #KLOOT_SHAPE_BASE_BR
        sta $07ff
        jmp !done_ptr+
!normal_ptr:
        // Normal order: star1 → sprites 0-3, star2 → sprites 4-7
        lda kloot_shape_1
        clc
        adc #KLOOT_SHAPE_BASE_TR
        sta $07f8
        lda kloot_shape_1
        clc
        adc #KLOOT_SHAPE_BASE_TL
        sta $07f9
        lda kloot_shape_1
        clc
        adc #KLOOT_SHAPE_BASE_BL
        sta $07fa
        lda kloot_shape_1
        clc
        adc #KLOOT_SHAPE_BASE_BR
        sta $07fb
        lda kloot_shape_2
        clc
        adc #KLOOT_SHAPE_BASE_TR
        sta $07fc
        lda kloot_shape_2
        clc
        adc #KLOOT_SHAPE_BASE_TL
        sta $07fd
        lda kloot_shape_2
        clc
        adc #KLOOT_SHAPE_BASE_BL
        sta $07fe
        lda kloot_shape_2
        clc
        adc #KLOOT_SHAPE_BASE_BR
        sta $07ff
!done_ptr:
!skip_inc:

        // ---- Orbital motion (50 Hz) — both stars drift on sine paths ----
        // Star 1: advance phase, read X/Y offsets from sine table.
        // Cosine by offset +64 into the table (quarter cycle).
        lda star1_orbit_phase
        clc
        adc #ORBIT_SPEED_1
        sta star1_orbit_phase
        tax
        lda sin_tab,x
        clc
        adc #KLOOT_X_CENTRE
        sta star1_cx
        txa
        clc
        adc #64
        tax
        lda sin_tab,x
        clc
        adc #KLOOT_Y_CENTRE
        sta star1_cy

        // Star 2: independent speed/phase
        lda star2_orbit_phase
        clc
        adc #ORBIT_SPEED_2
        sta star2_orbit_phase
        tax
        lda sin_tab,x
        clc
        adc #KLOOT_X_CENTRE
        sta star2_cx
        txa
        clc
        adc #64
        tax
        lda sin_tab,x
        clc
        adc #KLOOT_Y_CENTRE
        sta star2_cy

        // ---- Priority-swap detection — phase-difference bit 6 ----
        // Star 1 advances at speed 1, star 2 at speed 2, so the
        // difference grows by 1 each frame. Bit 6 of the difference
        // toggles every 64 frames, at which point the stars are ~90°
        // apart on their orbits (= max separation). That's the safe
        // window to swap sprite-slot assignments — no blink at crossing.
        lda star2_orbit_phase
        sec
        sbc star1_orbit_phase
        and #$40                       // isolate bit 6
        sta $f9                        // stash current bit ($f9 safe after my_music_play)
        eor last_safe_bit
        beq !safe_same+
        // Bit 6 transitioned — toggle swap_flag and swap sprite colours.
        lda $f9
        sta last_safe_bit
        lda swap_flag
        eor #1
        sta swap_flag
        // Swap colour registers between sprite groups so the brown/cyan
        // identity follows the star, not the hardware sprite slot.
        // Also toggle $D01B so the star group in front of the text
        // alternates — treats the title text like a physical plane
        // that stars orbit in front of or behind.
        bne !cyan_front+
        // Star 1 (brown) → sprites 0-3, star 2 (cyan) → sprites 4-7
        // All sprites behind text ($D01B = $FF) — slow pass behind.
        lda #$09
        sta $d027
        sta $d028
        sta $d029
        sta $d02a
        lda #$0e
        sta $d02b
        sta $d02c
        sta $d02d
        sta $d02e
        lda #$ff
        sta $d01b
        jmp !safe_done+
!cyan_front:
        // Star 2 (cyan) → sprites 0-3, star 1 (brown) → sprites 4-7
        // All sprites in front of text ($D01B = $00) — emerge forward.
        lda #$0e
        sta $d027
        sta $d028
        sta $d029
        sta $d02a
        lda #$09
        sta $d02b
        sta $d02c
        sta $d02d
        sta $d02e
        lda #$00
        sta $d01b
        jmp !safe_done+
!safe_same:
        // No transition — just store current bit for next frame.
        lda $f9
        sta last_safe_bit
!safe_done:

        // ---- Exchange orbital centres if swap_flag active ----
        // When swapped, star 1's computed centre gets written to the
        // sprites-4-7 registers and vice versa — the VIC priority rule
        // (higher number = in front) now shows the other star on top.
        lda swap_flag
        beq !no_exchange+
        lda star1_cx
        ldx star2_cx
        sta star2_cx
        stx star1_cx
        lda star1_cy
        ldx star2_cy
        sta star2_cy
        stx star1_cy
!no_exchange:

        // ---- Write star 1 sprite positions (50 Hz) ----
        // X = star1_cx ± KLOOT_DX, Y = star1_cy ± KLOOT_DY
        lda star1_cx
        clc
        adc #KLOOT_DX
        sta $d000                       // spr 0 TR X
        sta $d006                       // spr 3 BR X
        lda star1_cx
        sec
        sbc #KLOOT_DX
        sta $d002                       // spr 1 TL X
        sta $d004                       // spr 2 BL X

        lda star1_cy
        sec
        sbc #KLOOT_DY
        sta $d001                       // spr 0 TR Y
        sta $d003                       // spr 1 TL Y
        lda star1_cy
        clc
        adc #KLOOT_DY
        sta $d005                       // spr 2 BL Y
        sta $d007                       // spr 3 BR Y

        // ---- Write star 2 sprite positions (50 Hz) ----
        lda star2_cx
        clc
        adc #KLOOT_DX
        sta $d008                       // spr 4 TR X
        sta $d00e                       // spr 7 BR X
        lda star2_cx
        sec
        sbc #KLOOT_DX
        sta $d00a                       // spr 5 TL X
        sta $d00c                       // spr 6 BL X

        lda star2_cy
        sec
        sbc #KLOOT_DY
        sta $d009                       // spr 4 TR Y
        sta $d00b                       // spr 5 TL Y
        lda star2_cy
        clc
        adc #KLOOT_DY
        sta $d00d                       // spr 6 BL Y
        sta $d00f                       // spr 7 BR Y

        // transition check after all sprite maths
        lda zp_frame
        cmp #N_FRAMES
        bcc !run+
        lda #$30
        sta zp_timer
        lda #$00
        sta VIC_BORDER                  // settle to black before transition
        sta $d015                       // turn both star sprites off
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


// Kloot star shape counters (0..23) — independent per star so lobe
// angles drift apart. Lives in code RAM, not zp.
kloot_shape_1:
        .byte 0
kloot_shape_2:
        .byte 0

// Shape advance dividers — decremented each half-rate tick; when 0
// the corresponding shape counter advances and the divider reloads.
shape_div1:     .byte 0
shape_div2:     .byte 0

// Orbital phase (0..255) — advances at ORBIT_SPEED per frame.
star1_orbit_phase:  .byte 0
star2_orbit_phase:  .byte 0

// Orbital centre (X, Y) — computed every frame from sin_tab lookup.
star1_cx:  .byte 0
star1_cy:  .byte 0
star2_cx:  .byte 0
star2_cy:  .byte 0

// Priority swap — toggled when phase-difference bit 6 transitions
// (stars at max separation). Which sprite group gets "front" = brown
// vs "back" = cyan alternates so each crossing shows a different star
// in front.
swap_flag:     .byte 0          // 0=star1 on sprites 0-3, 1=star2 on sprites 0-3
last_safe_bit: .byte $ff        // previous bit 6 of phase diff ($ff = uninitialized)


// (Stage E pre-rendered zoom: all the animate-in interpolation tables,
// figure-8 motion tables, and per-quadrant base bytes that lived here
// for Stages C/D are gone. Sprite positions are fixed in setup; the
// "growth" is rendered into the shape data, not driven by per-IRQ
// X/Y math. Single kloot_shape counter + 4 sprite-pointer writes is
// the entire animation now.)


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

        // 8-bank twinkle: active bank cycles 0,4,8,12,16,20,24,28
        lda zp_frame
        and #$1c                // bits 2-4 = active bank ×4
        sta $f9                 // $f9 safe after my_music_play

        ldx #31
!loop:  txa
        and #$1c                // this star's bank
        cmp $f9
        bne !dim+
        lda #$01                // bright white
        jmp !wcol+
!dim:   lda #$0e                // dark grey
!wcol:  sta $fa                 // save colour ($fa scratch after music_play)
        // Self-modifying STA — patch COL_RAM address for this star
        txa
        asl                     // *2 for .word offset
        tay
        lda star_pos,y          // low byte
        sta star_patch_col
        lda star_pos + 1,y      // high byte
        sta star_patch_col + 1
        lda $fa                 // restore colour
star_patch_col:
        sta $d800               // operand patched per star
        dex
        bpl !loop-
!skip:  rts


//==================================================================
// Star position table — 32 full-screen COL_RAM addresses ($D800..$DBD8).
// Grouped as 8 banks of 4 for the active-bank twinkle scheme.
// Avoids title rows 11-13 and the kloot quad centre area.
//==================================================================
star_pos:
        .word $D805, $D811, $D819, $D841
        .word $D851, $D855, $D86B, $D87F
        .word $D896, $D8B2, $D8CB, $D8CE
        .word $D8D0, $D913, $DA00, $DA01
        .word $DA36, $DA5A, $DA8B, $DAE1
        .word $DB14, $DB2F, $DB41, $DB43
        .word $DB58, $DB73, $DB7B, $DB87
        .word $DB8D, $DB9E, $DBCA, $DBD8


//==================================================================
// title text — uppercase chargen at $1000, screencodes $01..$1A
// for A..Z, $20 for space.
//
// "KLOTEN MET DE BROODTROMMEL"  (26 chars)
//   K=0B L=0C O=0F T=14 E=05 N=0E _=20
//   M=0D E=05 T=14 _=20
//   D=04 E=05 _=20
//   B=02 R=12 O=0F O=0F D=04 T=14 R=12 O=0F M=0D M=0D E=05 L=0C
//==================================================================
title_main:
        .byte $0B, $0C, $0F, $14, $05, $0E, $20    // KLOTEN_
        .byte $0D, $05, $14, $20                    // MET_
        .byte $04, $05, $20                         // DE_
        .byte $02, $12, $0F, $0F, $04, $14, $12, $0F, $0D, $0D, $05, $0C  // BROODTROMMEL

// "A DIGITAL LUNCH EXPERIENCE"  (26 chars)
//   A=01 _=20  D=04 I=09 G=07 I=09 T=14 A=01 L=0C _=20
//   L=0C U=15 N=0E C=03 H=08 _=20
//   E=05 X=18 P=10 E=05 R=12 I=09 E=05 N=0E C=03 E=05
title_sub:
        .byte $01, $20                                          // A_
        .byte $04, $09, $07, $09, $14, $01, $0C, $20            // DIGITAL_
        .byte $0C, $15, $0E, $03, $08, $20                     // LUNCH_
        .byte $05, $18, $10, $05, $12, $09, $05, $0E, $03, $05  // EXPERIENCE


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
// Sine table for twin-star orbital motion — 256 entries covering a
// full cycle, each entry = floor(ORBIT_RADIUS * sin(angle)). Page-
// aligned at $0B00 so indexed reads never cross a page boundary.
//==================================================================
.align 256
sin_tab:
.for (var i = 0; i < 256; i++) {
        .byte floor(ORBIT_RADIUS * sin(i * 2 * PI / 256))
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
