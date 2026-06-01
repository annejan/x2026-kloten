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
//   row 11   KLOTEN MET DE COMMODORE        (chargen ROM uppercase)
//   row 13   LEREN ONTDEKKEN KLOOIEN
//   border  slow sine colour cycle through col_tab
//   bg      stays black
//   parallax PETSCII starfield: 32 stars across 4 speed tiers, each
//   tier with its own char + colour, drifting left (col 0 wraps to 39).
//   Reads as depth via differential motion alone — no priority swap.
//
// Music: TRIUMPHANT. setup sets $F6 = $01 so the K-S-K-S drum kit
// from intro's resident my_music_play fires through the whole part
// (kick + snare alternating on V3, V1 bass-bleed sub-thump on every
// hit). Chord pad + lead drift on V1/V2 keep cycling Am-Em-F-G
// underneath. The trophy moment is full mix; end credits then
// strip everything back to chord/lead for the closing minor flow.
//
// Transition: after N_FRAMES ticks (~32 s) the IRQ writes $F6 = $30
// and pefchain advances to end. ($30 is also recognized by intro's
// drum gate as "drums still on" — both values keep drums going,
// the transition just happens to use a higher one.)
//
// Memory:
//   $0800-$0Dxx  code + parallax starfield state + tier tables
//   $0E00-$0EFF  col_tab (border colour cycle)
//   $0F00-$0FFF  sin_tab (twin-star orbital motion)
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
// (V3 SID-register constants pulled with the coda_kick removal —
// nothing in the current coda touches V3 directly; intro's resident
// my_music_play owns V3 for the arp + K-S-K-S drum kit.)

.const N_FRAMES   = 400               // ~16 s at the half-rate divider (was 800/32s)
                                      // (800 ticks @ 25 Hz). Iteration
                                      // history: 250 (~10 s) → 400
                                      // (~16 s) → 600 (~24 s) → 800.
                                      // At 1:1.5 chase ratio + 256-frame
                                      // relative cycle, this fits a
                                      // generous ~3 full chases per
                                      // part.

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
// the title text "KLOTEN MET DE COMMODORE" (which spans cols 56-264)
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
// Stage F — PING-PONG ("breath"). Stage E played the 8 zoom frames
// once and then wrapped to the rotation segment forever, so the
// zoom-in only happened at the very start of the part and the purple
// star (which started at frame 8) never showed the zoom at all.
//
// Now each star's `kloot_shape_N` counter walks 0..23..0 in a true
// ping-pong, using a per-star direction byte (`kloot_dir_N`). The
// breath cycle is:
//
//   frames  0 → 7    zoom in   (small dot → full burst)
//   frames  7 → 23   rotate    (full size, lobes turning)
//   frames 23 → 7    rotate    (reverse direction)
//   frames  7 → 0    zoom out  (full burst → small dot)
//   ...repeats forever
//
// Star 1 (brown) starts at shape=0 dir=forward → opens with the
// zoom-in. Star 2 (purple) starts at shape=KLOOT_FRAMES_TOTAL-1
// dir=backward → opens with a zoom-OUT, so the two stars naturally
// run out of phase: one is shrinking while the other is growing.
//
// Reversing the rotation segment is visually invisible because the
// star has 12-fold symmetry and the rotation step is continuous —
// playing those 16 frames forward or backward looks like rotation
// either way.
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
.const KLOOT_FRAMES_ZOOM   = 8        // (no longer used post Stage F —
                                      //  see ping-pong comment above)
.const KLOOT_FRAME_LAST    = KLOOT_FRAMES_TOTAL - 1   // 23 — ping-pong top

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

// (A "Coda V3 kick" state machine used to live here, with its own
// KICK_PERIOD / KICK_LEN / KICK_FREQ_HI / KICK_FLOOR / KICK_SWEEP
// constants — a dedicated sparse V3 thump at ~60 BPM. Removed when
// coda switched to the resident K-S-K-S kit; constants pulled too
// when the routine + state bytes were deleted. Recover from git
// history if you ever want a separate thump back.)

.const INTRO_MUSIC_PLAY = $119e
// Intro music tables (resident at $1000-$125D, see intro.sym). Coda
// inherits these via 'I',$10,$12 in the EFO header.
.const MAIN_SID_FREQ_LO = $1000
.const MAIN_SID_FREQ_HI = $103c
.const MAIN_BASS_PATTERN = $10a8
.const MAIN_MU_STEP = $1148

// Twin-star orbital motion parameters.
.const ORBIT_RADIUS  = 56               // pixel radius (±56 px) — was 40,
                                        //   wider swing reads more as
                                        //   "dance" than "tight circle".
                                        //   Geometry checked: max Y
                                        //   excursion 185 + Y-expanded
                                        //   bottom quad (42 px) = 248,
                                        //   still inside visible raster.
// Speeds tuned so (SPEED_2 - SPEED_1) stays at +1/frame, which is
// what the priority-swap logic at the bottom of the IRQ assumes —
// it triggers on bit-6 transitions of (star2_phase - star1_phase)
// and the assumption that those transitions happen at MAX
// SEPARATION (not overlap) only holds when the diff increments by
// exactly 1 per frame. Bumping diff to +2/frame caused a one-frame
// flicker because the swap then fired AT the moment of overlap
// instead of 180°-apart.
.const ORBIT_SPEED_1 = 2                // star 1: ~2.5 s per cycle (was 1 / 5 s)
.const ORBIT_SPEED_2 = 3                // star 2: ~1.7 s per cycle (was 2 / 2.5 s)
                                        //   Both stars move faster than the
                                        //   original; relative chase ratio
                                        //   is 1.5× (slightly less than the
                                        //   broken 1:3 attempt at 3×, but
                                        //   without the flicker).

// Shape advance dividers — each star's shape counter advances every
// N half-rate ticks so they rotate at fundamentally different speeds.
// Star 1: /3 ≈ 8.3 Hz, star 2: /2 = 12.5 Hz. Try /1 + /3 for 25+8 Hz.
.const SHAPE_DIV_1 = 3                  // star 1: advance every 3rd half-rate tick
.const SHAPE_DIV_2 = 2                  // star 2: advance every 2nd tick

.const zp_timer       = $f6           // transition: set to $30 to trigger pefchain
// $F9/$FA are off-limits — `zp_tmp`/`zp_msb` get clobbered inside
// my_music_play, so any state living there would be trashed every
// frame. $F8 is also off-limits as `zp_intro` (my_music_play reads
// it for master volume).
.const zp_subtick     = $fb           // half-rate divider toggle
.const zp_frame       = $fc           // animation tick (0..N_FRAMES-1, low byte
                                      // of 16-bit half-rate frame counter;
                                      // high byte is `frame_hi` in code RAM)


* = $0800 "Coda"


//==================================================================
// setup
//==================================================================
setup:
        // ---- Set zp_intro ($F8) for triumphant-coda music behaviour ----
        // Intro's resident my_music_play gates voices on three thresholds:
        //   zp_intro >= T_BALLS (40)     → V2 lead writes
        //   zp_intro >= T_BARS (120)     → V1 bass writes
        //   zp_intro >= T_SCROLLER (240) → V3 ctrl re-written to pulse+gate
        //                                  every frame
        //
        // Interlude reuses $F8 as zp_plasma_tgl (zeroes it on setup),
        // so by the time we reach coda $F8 holds a low value. Without
        // restoration, V1 + V2 freq writes are skipped → "stuck note".
        //
        // Setting $F8 to $80 (= 128, between T_BARS and T_SCROLLER):
        //   - V1 and V2 freq writes fire (bass + lead walk the patterns)
        //   - V3 gate write SKIPS, so V3 stays at whatever waveform the
        //     drum_tick last wrote (= $11 triangle). Triangle arp is
        //     mellow and matches greets' V3 timbre — that's what makes
        //     the user describe greets as "flowing nicely". Slamming
        //     $FF instead made V3 re-gate to pulse every frame, giving
        //     the arp a sharp pulse timbre the user heard as "different
        //     notes / different key" against the lead.
        lda #$80
        sta $f8

        lda #0
        sta zp_subtick
        sta zp_frame
        sta frame_hi                  // high byte of 16-bit frame counter
        sta space_state               // 0=normal, 1=paused (space held timer)

        // ---- CODA IS THE TRIUMPHANT MOMENT ----
        // Triumph = the full K-S-K-S kit from intro's resident music_play
        // comes back for the held title. We INHERIT intro's V3 arp +
        // drum-trigger machinery instead of running coda's own V3 kick.
        // Drum gate (zp_outro / zp_timer = $F6) must be non-zero for
        // music_play to fire percussion; setting it to 1 here keeps
        // drums on for the whole part. The IRQ later overwrites $F6
        // with $30 to trigger pefchain when the part ends.
        // (End credits then take us back into the sparse minor flow —
        // that contrast is the design intent.)
        lda #1
        sta zp_timer                  // drum gate ON (non-$30, won't trigger pefchain yet)

        // V3 ADSR + ctrl are left to intro's my_music_init defaults
        // (AD=$00, SR=$F0 — sustain pinned at peak, what the K-S-K-S
        // kit + arp both rely on). Earlier coda overrode them for its
        // own kick state machine; we no longer use that.
        //
        // Ensure V3 oscillates: gate + triangle at a mid frequency so
        // the sync source (V3 zero-crossings) is always active, even
        // between drum hits. The next drum tick overwrites these bytes.
        lda #$11                        // triangle + gate
        sta $d412                       // V3 ctrl
        lda #$10                        // ~250 Hz
        sta $d40f                       // V3 freq hi

        // V1 + V2 ADSRs left at intro's defaults ($04/$61 punchy bass,
        // $02/$81 sharp lead) — coda IS the triumphant full intro mix
        // held under the title, not a separate pad timbre. Earlier
        // attempts to pad-ify V2 collided with V1's punchy attacks
        // and read as "different key" to the listener. Matching intro's
        // exact ADSRs keeps the whole demo on the same musical voice.

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

        // Star 2 colours: purple ($04) vs star 1's brown ($09).
        lda #$04
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

        // Star 1: starts at frame 0, ping-pong direction = forward →
        // the part opens with star 1 zooming IN from a small dot.
        lda #$00
        sta kloot_shape_1
        sta kloot_dir_1                 // 0 = forward, $ff = backward
        // Star 2: starts at the LAST frame (23) with direction =
        // backward → opens with a zoom-OUT, so the two stars are
        // immediately out of phase. By the time star 1 finishes its
        // first zoom-in and starts rotating, star 2 has zoomed out
        // and is heading back the other way.
        lda #KLOOT_FRAME_LAST
        sta kloot_shape_2
        lda #$ff
        sta kloot_dir_2
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

        // ---- init parallax starfield ----
        // Seed (row, col, tier) state per star and paint the initial
        // char + colour into screen / colour RAM. Tier = i AND 3
        // (8 stars per tier). $f9/$fa are safe scratch here (setup
        // runs once, no music_play interference). They're re-used as
        // a (zp),y indirect pointer to avoid 32 separate self-mod
        // STAs and keep the loop compact.
        ldx #31
!sf_init:
        lda star_init_row,x
        sta star_row,x
        lda star_init_col,x
        sta star_col,x
        txa
        and #$03
        sta star_tier,x
        tay
        lda tier_speed,y
        sta star_tick,x
        // Set screen ptr = $0400 + row*40
        ldy star_row,x
        lda row_start_lo,y
        sta $f9
        lda row_start_hi,y
        sta $fa
        // Write tier_char at col
        ldy star_tier,x
        lda tier_char,y
        ldy star_col,x
        sta ($f9),y
        // Switch ptr to COL_RAM (hi += $D4)
        clc
        lda $fa
        adc #$d4
        sta $fa
        ldy star_tier,x
        lda tier_color,y
        ldy star_col,x
        sta ($f9),y
        dex
        bpl !sf_init-

        // ---- paint the title text ----
        // Row 11 starts at $0400 + 11*40 = $05B8.
        // " KLOTEN MET DE COMMODORE  " = 26 chars, center at col 7.
        // Row 13 ($0608): "  LEREN ONTDEKKEN KLOOIEN " = 26 chars, col 7.
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

        // Row 15: party-release tag in dark grey under the title.
        // Used to be "ESPECIALLY KLOOT" — pulled because three on-screen
        // mentions of the AI character read as ego-stroking. (Since
        // then the greets settle text was renamed to KLOTEN too, so
        // there's no on-screen AI character namecheck during the demo
        // itself — only the end-credits "kloot finally got me here"
        // thought remains.) The release tag keeps the gradient
        // (white / lt grey / dk grey) and gives the title card three
        // lines of weight without name-dropping the helper.
        // " RELEASED AT X2026  " — 20 chars; col 10..29.
        ldx #0
!t3:    lda title_release,x
        sta $0658 + 10,x
        inx
        cpx #20
        bne !t3-

        ldx #0
        lda #$0b                        // dark grey — readable but subtle
!c3:    sta $DA58 + 10,x
        inx
        cpx #20
        bne !c3-

        // Settle SID: drums OFF (zp_timer = $00 gates the percussion
        // in intro's my_music_play). Vol restored to max.
        lda #$1f
        sta SID_VOL

        // Raster IRQ in the top border — fires early enough that the
        // orbital math + sprite-position writes at the top of `interrupt`
        // complete BEFORE VIC re-reads sprite Y registers at the lowest
        // possible top-quad Y (= 52). From raster 20 → 52 we have
        // ~32 rasters ≈ 2000 cy of headroom for orbit + position writes
        // (the actual work is ~300-400 cy, so plenty of buffer).
        lda #$14                        // line 20 (was $32 = 50; moved up to
                                        //   front-load position writes before
                                        //   VIC's per-raster sprite-Y check)
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
        // ---- Orbital motion + sprite-cluster positions FIRST ----
        // VIC re-checks every sprite's Y register at every raster
        // line, so the position writes MUST finish before VIC reads
        // the lowest possible top-quad Y (= KLOOT_Y_CENTRE - ORBIT_RADIUS
        // - KLOOT_DY = 73-21 = 52). The IRQ fires at raster $14
        // (= 20), so we have ~32 rasters of headroom before raster 52
        // — plenty of time to compute orbits, swap colours, and
        // write 16 sprite-position registers.
        //
        // Without this reorder, the previous structure had position
        // writes near the END of the IRQ (after music_play / star_field
        // / half-rate logic, back when a dedicated coda_kick also ran
        // here), which put them around raster 80-100. Top quad Y
        // values < 80 then RACED VIC's sprite-Y
        // check — the top quad displayed at LAST frame's Y while the
        // bottom quad (Y ≥ 94) saw the new Y. When stars moved
        // downward, the result was a one-raster gap between top and
        // bottom halves at "20 % from top" of the screen — visible
        // as a thin black horizontal line through the dance.

        // Star 1: advance phase, read X/Y offsets from sin_tab.
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
        // Triggers when bit 6 of (star2_phase - star1_phase) transitions,
        // which happens at ~max separation given the +1/frame phase
        // diff (speeds 2 and 3, diff = 1). See orbit-speed comment block
        // up top for why the diff MUST stay at +1/frame for this to fire
        // at safe (well-separated) moments rather than overlap moments.
        lda star2_orbit_phase
        sec
        sbc star1_orbit_phase
        and #$40                       // isolate bit 6
        sta $f9                        // stash current bit ($f9 safe here — music_play hasn't run yet)
        eor last_safe_bit
        beq !safe_same+
        lda $f9
        sta last_safe_bit
        lda swap_flag
        eor #1
        sta swap_flag
        bne !cyan_front+
        // Star 1 (brown) → sprites 0-3, star 2 (purple) → sprites 4-7
        lda #$09
        sta $d027
        sta $d028
        sta $d029
        sta $d02a
        lda #$04
        sta $d02b
        sta $d02c
        sta $d02d
        sta $d02e
        lda #$ff
        sta $d01b
        jmp !safe_done+
!cyan_front:
        // Star 2 (purple) → sprites 0-3, star 1 (brown) → sprites 4-7
        lda #$04
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
        lda $f9
        sta last_safe_bit
!safe_done:

        // ---- Exchange orbital centres if swap_flag active ----
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

        // ---- Write star 1 sprite positions ----
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

        // ---- Write star 2 sprite positions ----
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

        // ---- NOW the rest of the per-frame work ----
musichook:
        .byte $2c, $00, $00       // bit $0000 — pefchain rewrites to
                                   // jsr $119e via intro's 'M' tag.
                                   // See interlude.asm's musichook
                                   // comment for the design.
        // Re-assert master vol: my_music_play computes $D418 from
        // $F8 (zp_intro) every frame, which would only matter if
        // something accidentally wrote to $F8 — but it's cheap
        // belt-and-braces given coda's near-silence regression came
        // from exactly this path. Same idiom interlude / hush /
        // greets use.
        lda #$1f
        sta SID_VOL

        // V1 sync from V3: my_music_play writes $D404 with $41
        // (pulse+gate, sync=0) on each V1 note, clearing the sync
        // bit. Re-assert it here so V1's pulse wave restarts on V3's
        // zero-crossings — a harder, buzz-saw edge for the triumphant
        // title. Safe to OR every frame: $D404 always has gate set
        // between notes (sustain holds) so adding sync never
        // accidentally re-gates a released voice.
        lda $d404
        ora #$02
        sta $d404

        // ---- Filter routing: V2+V3 through LP, V1 bass clean ----
        // Greets ends with $D417 = $42 (V2 only). Coda adds V3 (triangle
        // arp) into the filtered space but keeps V1's bass-bleed sub-thump
        // clean — LP + resonance on the heavy low-end kick causes audible
        // crunch / filter-clap per beat. Cutoff breathes via sin_tab.
        // Resonance reduced to $2 (was $4) so the breath is gentle, not
        // a zipper-effect tear.
        lda #$26
        sta $d417
        ldy zp_frame
        lda sin_tab,y
        clc
        adc #$60
        sta $d416

        jsr star_field
        // (coda_kick used to fire here as a dedicated sparse V3 thump.
        // Removed for the TRIUMPHANT coda revision — intro's resident
        // K-S-K-S kit (kick + snare alternating) + V1 bass-bleed
        // sub-thump play through the whole part because setup sets
        // zp_timer = $01 = drum gate ON. The kit's V3 triangle
        // pitch-slam IS the kick and V1's N_C1 bleed IS the sub. The
        // subroutine itself was deleted on 2026-05-21; recover from
        // git history if you ever want a dedicated thump back.)

        // half-rate divider — drives shape advance
        lda zp_subtick
        eor #1
        sta zp_subtick
        bne !over+
        jmp !half_rate+
!over:  jmp !skip_inc+
!half_rate:
        // 16-bit frame counter: low byte (zp_frame) walks 0..255 so it
        // can also index the 256-byte col_tab; high byte carries the
        // overflow so the transition check can compare N_FRAMES values
        // that exceed 255 (the original 8-bit-only zp_frame + plain
        // `cmp #N_FRAMES` silently truncated, so 400 / 600 / 800
        // transitioned at 144 / 88 / 32 ticks respectively).
        inc zp_frame
        bne !no_frame_carry+
        inc frame_hi
!no_frame_carry:
        // Advance shape counters via independent dividers so each star
        // rotates at a fundamentally different speed (/3 vs /2). Each
        // counter ping-pongs 0 → 23 → 0 (see Stage F comment up top);
        // the actual step lives in `kloot_advance` called with X=star
        // index (0 or 1). Subroutine call costs cycles but saves
        // ~30 B vs duplicating the ping-pong logic per star, which
        // was bumping the .align 256'd col_tab/sin_tab into the
        // inherited intro music page $10.
        dec shape_div1
        bne !skip1+
        ldx #0
        jsr kloot_advance
        lda #SHAPE_DIV_1
        sta shape_div1
!skip1:
        dec shape_div2
        bne !skip2+
        ldx #1
        jsr kloot_advance
        lda #SHAPE_DIV_2
        sta shape_div2
!skip2:
!skip_inc:

        // ---- Write sprite pointers (50 Hz) — NMI-safe every frame ----
        // Spindle's background loader fires NMIs that clobber $07F8-$07FF.
        // Writing every frame (not just half-rate) prevents 1-frame shape
        // glitches that read as jitter (same fix as greets' update_sprite_ptrs).
        // swap_flag=0: star 1 → sprites 0-3, star 2 → sprites 4-7
        // swap_flag=1: star 2 → sprites 0-3, star 1 → sprites 4-7
        lda swap_flag
        beq !normal_ptr+
        ldy #3
!sp_sw: clc
        lda kloot_shape_2
        adc sprite_bases,y
        sta $07f8,y
        clc
        lda kloot_shape_1
        adc sprite_bases,y
        sta $07fc,y
        dey
        bpl !sp_sw-
        jmp !done_ptr+
!normal_ptr:
        ldy #3
!sp_no: clc
        lda kloot_shape_1
        adc sprite_bases,y
        sta $07f8,y
        clc
        lda kloot_shape_2
        adc sprite_bases,y
        sta $07fc,y
        dey
        bpl !sp_no-
!done_ptr:

        // (Orbital math + sprite-position writes are now at the TOP of
        // the IRQ, before music_play, so they finish before VIC's
        // sprite-Y check at the lowest possible top-quad Y. See the
        // comment block at the start of `interrupt:`. Race fixed.)

        // ---- Spacebar: first press pauses auto-timer, second advances ----
        lda #$7f
        sta $dc00
        lda $dc01
        and #$10
        bne !no_space+
        // Space is down
        lda space_state
        cmp #1
        beq !space_advance+            // already paused → advance
        lda #1
        sta space_state                // first press → pause
        jmp !run+
!space_advance:
        jmp !trigger_transition+
!no_space:

        // Skip auto-timer if paused by spacebar
        lda space_state
        bne !run+

        // transition check: 16-bit compare frame_hi:zp_frame vs N_FRAMES.
        // Fire when (frame_hi:zp_frame) >= N_FRAMES.
        lda frame_hi
        cmp #>N_FRAMES
        bcc !run+
        bne !trigger_transition+
        lda zp_frame
        cmp #<N_FRAMES
        bcc !run+
!trigger_transition:
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


// (coda_kick subroutine + kick_freq / kick_state byte vars used to
// live here — a dedicated V3 pitch-slam thump at ~60 BPM, run after
// my_music_play. Pulled when coda switched to the K-S-K-S kit because
// the kit's kick already IS a V3 triangle pitch-slam and the V1
// bass-bleed already IS the sub body — separate machine became
// redundant. Removed entirely on 2026-05-21 to recover ~80 bytes so
// the coda V1/V2 pad ADSR overrides + cutoff LFO fit before sin_tab
// hits the .errorif guard at $1000. Re-add from git history if you
// ever want the dedicated thump back.)

// High byte of the 16-bit half-rate frame counter. Low byte lives at
// zp_frame ($fc) so it also indexes the 256-byte col_tab; this byte
// carries the overflow so the transition check can compare against
// N_FRAMES values > 255. Reset to 0 in setup.
frame_hi:
        .byte 0
space_state:
        .byte 0                        // 0=auto-timer, 1=paused by spacebar


// Kloot star shape state — 2-byte arrays so kloot_advance can index
// either star via X = 0 or 1. Separate `_1` / `_2` labels alias the
// individual bytes so the IRQ-body sprite-pointer code reads them
// directly without reloading X each time.
kloot_shape:
kloot_shape_1:  .byte 0
kloot_shape_2:  .byte 0

// Ping-pong direction per star: 0 = forward (counter is being
// incremented), $FF = backward (decremented). Flipped at the
// boundaries 0 and KLOOT_FRAME_LAST. See Stage F comment block.
kloot_dir:
kloot_dir_1:    .byte 0
kloot_dir_2:    .byte $ff

// Shape advance dividers — decremented each half-rate tick; when 0
// the corresponding shape counter advances and the divider reloads.
shape_div1:     .byte 0
shape_div2:     .byte 0

// Sprite-pointer base per quadrant (Y indexes TR/TL/BL/BR in the
// order $07F8..$07FB and $07FC..$07FF). Pointer = shape + base.
sprite_bases:
        .byte KLOOT_SHAPE_BASE_TR       // Y=0 → spr 0 / spr 4 (TR)
        .byte KLOOT_SHAPE_BASE_TL       // Y=1 → spr 1 / spr 5 (TL)
        .byte KLOOT_SHAPE_BASE_BL       // Y=2 → spr 2 / spr 6 (BL)
        .byte KLOOT_SHAPE_BASE_BR       // Y=3 → spr 3 / spr 7 (BR)


//==================================================================
// kloot_advance — single step of the ping-pong shape counter for
// star X (0 or 1). Forward: inc; clamp at KLOOT_FRAME_LAST and
// reverse. Backward: dec; clamp at 0 and reverse.
//==================================================================
kloot_advance:
        lda kloot_dir,x
        bne !back+
        // forward step
        inc kloot_shape,x
        lda kloot_shape,x
        cmp #KLOOT_FRAMES_TOTAL
        bcc !done+
        dec kloot_shape,x               // clamp 24 → 23
        lda #$ff
        sta kloot_dir,x                 // flip to backward
        rts
!back:
        // backward step
        dec kloot_shape,x
        bpl !done+
        inc kloot_shape,x               // clamp $FF → 0
        lda #0
        sta kloot_dir,x                 // flip to forward
!done:
        rts

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
// star_field — 4-tier horizontal parallax PETSCII starfield.
//
// 32 stars distributed across 4 speed tiers (tier = i AND 3, so 8
// stars per tier). Each tier has its own:
//   tier_speed[] — half-rate ticks between moves (3 / 5 / 8 / 14)
//   tier_char[]  — '+' '*' '.' ',' (foreground → background)
//   tier_color[] — white / lt grey / dk grey / blue
//
// Per half-rate tick (25 Hz): each star's tick counts down; when it
// hits 0 the star erases its old char, advances col left (wrap 0→39),
// draws the tier's char + colour at the new col, and reloads tick
// from tier_speed.
//
// Title rows 11/13 are never assigned to any star, so the slow drift
// passes above + below the centred title without overwriting it.
//
// $f9/$fa are used as a (zp),y indirect pointer — safe scratch here
// because star_field always runs immediately after my_music_play
// (which has already finished clobbering $f9/$fa) and before any
// other consumer.
//==================================================================
star_field:
        lda zp_subtick
        beq !sf_run+
        rts
!sf_run:
        ldx #31
!sf_loop:
        dec star_tick,x
        beq !sf_move+
        jmp !sf_next+
!sf_move:
        // Reload tick from tier_speed for next cycle
        lda star_tier,x
        tay
        lda tier_speed,y
        sta star_tick,x

        // Set screen ptr = $0400 + row*40
        ldy star_row,x
        lda row_start_lo,y
        sta $f9
        lda row_start_hi,y
        sta $fa

        // Erase old char at current col
        ldy star_col,x
        lda #$20
        sta ($f9),y

        // Advance col left; wrap $FF → 39
        dec star_col,x
        bpl !sf_no_wrap+
        lda #$27
        sta star_col,x
!sf_no_wrap:

        // Draw new char at new col
        ldy star_tier,x
        lda tier_char,y
        ldy star_col,x
        sta ($f9),y

        // Switch ptr to COL_RAM (hi += $D4)
        clc
        lda $fa
        adc #$d4
        sta $fa

        // Write tier colour at new col
        ldy star_tier,x
        lda tier_color,y
        ldy star_col,x
        sta ($f9),y
!sf_next:
        dex
        bpl !sf_loop-
        rts


//==================================================================
// Parallax starfield tables + per-star state.
//
// State arrays (4 × 32 = 128 B) hold the live row / col / tier / tick
// per star. Tier tables (3 × 4 B) are parallel-indexed by tier. Row
// lookup tables (2 × 25 B) give screen-address lo/hi for each text
// row to skip a per-frame multiply by 40. Init tables (2 × 32 B) seed
// the starting (row, col) — rows chosen to avoid 11/13 (title rows).
//==================================================================
star_row:  .fill 32, 0
star_col:  .fill 32, 0
star_tier: .fill 32, 0
star_tick: .fill 32, 0

tier_speed: .byte 3, 5, 8, 14
tier_char:  .byte $2B, $2A, $2E, $2C    // + * . ,
tier_color: .byte $01, $0F, $0B, $06    // white, lt grey, dk grey, blue

row_start_lo: .fill 25, <($0400 + i * 40)
row_start_hi: .fill 25, >($0400 + i * 40)

star_init_row:
        .byte  0,  0,  0,  1,  2,  2,  2,  3
        .byte  3,  4,  5,  5,  5,  6, 12, 12
        .byte 14, 10, 16, 18, 19, 20, 20, 20     // index 17 moved from 15→10 for dedication
        .byte 21, 22, 22, 22, 22, 23, 24, 24
star_init_col:
        .byte  5, 17, 25, 25,  1,  5, 27,  7
        .byte 30, 18,  3,  6,  8, 35, 32, 33
        .byte  6,  2, 11, 17, 28, 15, 33, 35
        .byte 16,  3, 11, 23, 29,  6, 10, 24


//==================================================================
// title text — uppercase chargen at $1000, screencodes $01..$1A
// for A..Z, $20 for space, digits $30-$39.
//
// " KLOTEN MET DE COMMODORE  "  (23 chars + lead/trail pad = 26)
//   _=20
//   K=0B L=0C O=0F T=14 E=05 N=0E _=20
//   M=0D E=05 T=14 _=20
//   D=04 E=05 _=20
//   C=03 O=0F M=0D M=0D O=0F D=04 O=0F R=12 E=05
//   _=20 _=20
//==================================================================
title_main:
        .byte $20                                                  // _
        .byte $0B, $0C, $0F, $14, $05, $0E, $20                    // KLOTEN_
        .byte $0D, $05, $14, $20                                    // MET_
        .byte $04, $05, $20                                         // DE_
        .byte $03, $0F, $0D, $0D, $0F, $04, $0F, $12, $05           // COMMODORE
        .byte $20, $20                                              // __

// "  LEREN ONTDEKKEN KLOOIEN "  (23 chars + 2 lead / 1 trail pad = 26)
//   _=20 _=20
//   L=0C E=05 R=12 E=05 N=0E _=20
//   O=0F N=0E T=14 D=04 E=05 K=0B K=0B E=05 N=0E _=20
//   K=0B L=0C O=0F O=0F I=09 E=05 N=0E
//   _=20
title_sub:
        .byte $20, $20                                              // __
        .byte $0C, $05, $12, $05, $0E, $20                          // LEREN_
        .byte $0F, $0E, $14, $04, $05, $0B, $0B, $05, $0E, $20      // ONTDEKKEN_
        .byte $0B, $0C, $0F, $0F, $09, $05, $0E                     // KLOOIEN
        .byte $20                                                  // _

// " RELEASED AT X2026  "  (20 chars; col 10..29 of row 15)
//   _=20
//   R=12 E=05 L=0C E=05 A=01 S=13 E=05 D=04 _=20
//   A=01 T=14 _=20
//   X=18 2=32 0=30 2=32 6=36
//   _=20 _=20
title_release:
        .byte $20                                                                   // _
        .byte $12, $05, $0C, $05, $01, $13, $05, $04, $20                          // RELEASED_
        .byte $01, $14, $20                                                         // AT_
        .byte $18                                                                   // X
        .byte $32, $30, $32, $36                                                    // 2026
        .byte $20, $20                                                              // __

//==================================================================
// Border colour table — 256-entry slow sine through a calm palette
// (mostly blues / cyans, no harsh contrasts — this is the breather).
// Page-aligned so `lda col_tab,y` never crosses a page (1 cycle
// saved on the 50 Hz border-cycle read).
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
// aligned so `lda sin_tab,y` is single-cycle. MUST end before $1000
// or it stomps coda's inherited intro music tables at $1000-$125D.
//==================================================================
.align 256
sin_tab:
.for (var i = 0; i < 256; i++) {
        .byte floor(ORBIT_RADIUS * sin(i * 2 * PI / 256))
}
.errorif (sin_tab + 256) > $1000, "sin_tab overflows into intro music tables at $1000"

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
