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
// Transition out: pefchain script triggers on f6 = $82, but normally
// reached via the scroll-driven path (IRQ forces f6 = SETTLE_BEAT
// the moment scroll_pos hits the punchline). Settle phase holds the
// screen on " KLOTEN " for ~1.9 s — sprites stop bobbing, scroll
// freezes, colour cycle keeps shimmering as the calm landing into
// the coda's "KLOTEN MET DE BROODTROMMEL" title.
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
// Sprite shape area moved from $2000 to $0800 (2 KB) to free up
// $2000-$3FFF for the koala bitmap. With shapes at $0800, sprite
// pointer values are $20-$3F (= $0800 / 64) instead of $80-$9F.
.const SPRITE_SHAPE = $0800

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
// Scroll-DRIVEN transition (2026-05-21): the IRQ forces beat_count to
// SETTLE_BEAT the moment scroll_pos reaches the start of settle_text
// (= the visible window is about to show " KLOTEN "). That couples
// the part length to message length — add or remove names in the
// .text below and the part shortens/lengthens automatically.
//
// These three constants are therefore SAFETY FALLBACKS for the case
// where scroll never reaches the end (data corruption, infinite scroll
// speed = 0, etc.) — picked high enough that they don't fire during a
// normal play but bounded so the part can't hang forever:
.const FADE_BEAT_START = $70   // 112 beats × 24 ≈ 53.8 s (safety)
.const SETTLE_BEAT     = $7E   // 126 beats × 24 ≈ 60.5 s
.const TRANSITION_BEAT = $82   // 130 beats × 24 ≈ 62.4 s — must match
                               //   pefchain_script's `f6 = 82`. After
                               //   scroll-driven settle fires, this is
                               //   reached 4 beats later = ~1.9 s of
                               //   centred " KLOTEN " before the transition.

.const zp_beat_phase     = $f4
.const zp_wobble_pos     = $f5
.const zp_beat_count     = $f6
.const zp_scroll_pos     = $f7  // 16-bit lo (was 8-bit only)
.const zp_beat_kick      = $f3  // beat-sync Y kick (decays 0→0)

// (State bytes scroll_x_offset / scroll_pos_hi / damp_shift live
// AFTER the `* = $8000` directive below — declared before it, they
// land at KickAssembler's default segment-start address of $2000
// which is EXACTLY where the first sprite-shape glyph (letter A)
// lives. Writing to scroll_x_offset every frame then animates stray
// pixels at the top of every 'A' on screen. See block right after
// `* = $8000` for the actual declarations.)


* = $8000 "Greets"

// State bytes — MUST sit inside the $8000 code segment so they don't
// trample the sprite shape area at $2000-$27FF. Placed at the very
// top of the segment so the rest of the code can reference them via
// short absolute addresses (and so the .sym names cluster nicely).
//
// scroll_x_offset (0..39) is the SMOOTH-SCROLL pixel offset: every
// frame the whole sprite row shifts left by SCROLL_SPEED_TABLE[damp]
// pixels via this byte. When it crosses 40 (= one sprite-stride), we
// subtract 40, advance zp_scroll_pos by one char, and refresh sprite
// pointers — the visual "pop" is invisible because each character
// ends up at the same screen pixel (sprite jumps right by 40 while
// content shifts left by one slot). Replaces the older `scroll_tick`
// byte-counter which gave a chunky 40-px-every-8-frames step.
//
// scroll_pos_hi is the hi byte of the 16-bit scroll position so the
// full ~700 B message is reachable past the 8-bit-Y indexing limit.
//
// damp_shift (0..5) ramps during the fade-to-settle phase, ASR'ing
// the DYCP/DXCP sine samples toward 0 and slowing the scroll.
scroll_x_offset: .byte 0
scroll_pos_hi:   .byte 0
damp_shift:      .byte 0

//==================================================================
// setup
//==================================================================
setup:
        // VIC bank 0 ($DD02 = $3C → $0000-$3FFF visible to VIC)
        lda #$3c
        sta $dd02
        // VIC_MEM = $18 → screen RAM $0400 (bits 7-4 = 1), bitmap
        // base $2000 (bits 3-1 = 4). Bitmap occupies 8 KB at
        // $2000-$3F3F (only first 8000 bytes are visible).
        lda #$18
        sta VIC_MEM
        // VIC_CTRL1 = $3B → DEN=1, BMM=1 (bitmap mode), RSEL=1,
        // YSCROLL=3. Without BMM the koala bytes render as garbage.
        lda #$3b
        sta VIC_CTRL1
        // VIC_CTRL2 = $18 → CSEL=1 (40-col), MCM=1 (multi-colour).
        // Koala uses multi-colour mode with 4 colours per cell.
        lda #$18
        sta VIC_CTRL2

        lda #$00
        sta VIC_BORDER
        // Background colour ($D021) comes from the koala (last byte
        // of the .kla payload — see koala_bg below).
        lda koala_bg
        sta VIC_BG

        // ---- Copy koala screen + colour RAM data into VIC ----
        // pefchain loaded the bitmap directly into $2000-$3F3F. The
        // per-cell screen attributes (c1/c2) and colour RAM (c3) live
        // in code-segment buffers (koala_screen / koala_color) and
        // get CPU-copied at boot:
        //   - $0400-$07E7 = per-cell c1 hi nibble, c2 lo nibble
        //   - $D800-$DBE7 = per-cell c3 lo nibble (VIC's colour RAM)
        // pefchain can't write to $D800 directly (it's IO, not RAM),
        // and we keep $04-$07 out of greets' EFO claim so blank-filler
        // effects can paint $0400 during the background load.
        ldx #0
!ks:    lda koala_screen+$000,x
        sta $0400,x
        lda koala_screen+$100,x
        sta $0500,x
        lda koala_screen+$200,x
        sta $0600,x
        lda koala_screen+$2e8,x       // last partial page → $06e8..$07e7
        sta $06e8,x
        lda koala_color+$000,x
        sta $d800,x
        lda koala_color+$100,x
        sta $d900,x
        lda koala_color+$200,x
        sta $da00,x
        lda koala_color+$2e8,x        // last partial page → $dae8..$dbe7
        sta $dae8,x
        inx
        bne !ks-

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
        sta scroll_pos_hi
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
        sta scroll_x_offset
        sta zp_beat_kick
        sta damp_shift

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

musichook:
        .byte $2c, $00, $00       // bit $0000 — pefchain rewrites to
                                   // jsr $119e. See interlude.asm's
                                   // musichook comment for the design.

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

        // ----- Scroll-driven transition -----
        // When scroll_pos reaches the start of settle_text (the
        // " KLOTEN " punchline at the tail of the message), force
        // beat_count to SETTLE_BEAT so the scroll snaps to centred
        // KLOTEN. Triggering at exactly settle_text-message (vs
        // earlier with `-8`) lets the last name (currently "ABYSS
        // CONNECTION") fully scroll through the visible window
        // before the snap — at trigger time KLOTEN is naturally
        // about to scroll into view, so the snap is a tiny align
        // rather than a jarring jump.
        //
        // This couples the part length to message length: add or
        // remove names and the part shortens/lengthens automatically.
        // Use bcs/bcc to also handle the case where beat_count was
        // ALREADY past SETTLE_BEAT (= safety timing got there first).
        lda scroll_pos_hi
        cmp #>(settle_text - message)
        bcc !scroll_continuing+
        bne !scroll_at_end+
        lda zp_scroll_pos
        cmp #<(settle_text - message)
        bcc !scroll_continuing+
!scroll_at_end:
        lda zp_beat_count
        cmp #SETTLE_BEAT
        bcs !scroll_continuing+
        lda #SETTLE_BEAT
        sta zp_beat_count
!scroll_continuing:

        // ----- Fade-phase damp_shift -----
        // From FADE_BEAT_START up to SETTLE_BEAT, ramp `damp_shift`
        // from 0 → 5 in steps of 1 every 4 beats. The DYCP/DXCP code
        // below applies that many arithmetic-shift-rights to each
        // sine sample, so the wobble amplitude shrinks 2 → 1 → 0 px.
        // The scroll tick reads its delay from `SCROLL_DELAY_TABLE`
        // indexed by the same shift, so the scroller also slows
        // progressively. By SETTLE_BEAT the world is already standing
        // still — the actual settle freeze is then invisible.
        lda zp_beat_count
        cmp #FADE_BEAT_START
        bcs !in_fade+
        lda #0
        sta damp_shift
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
        sta damp_shift
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

        // ----- Smooth pixel-scroll tick (BEFORE update_sprite_ptrs) -----
        // Advance scroll_x_offset by SCROLL_SPEED_TABLE[damp_shift]
        // pixels each frame. When it crosses 40 (one sprite stride),
        // subtract 40 and advance zp_scroll_pos by one char so the
        // sprite ptrs shift one slot. Must happen BEFORE the ptr
        // refresh so the X-pop and the content-pop land on the same
        // frame — otherwise sprites snap right 40 px while still
        // showing the OLD chars for one frame (visible glitch).
        ldy damp_shift
        lda SCROLL_SPEED_TABLE,y
        clc
        adc scroll_x_offset
        cmp #40
        bcc !no_char_step+
        sec
        sbc #40
        pha
        inc zp_scroll_pos
        bne !no_step_carry+
        inc scroll_pos_hi
!no_step_carry:
        pla
!no_char_step:
        sta scroll_x_offset

        // Always re-write sprite pointers every frame. The Spindle NMI
        // loader can clobber $07F8-$07FF during background loads, and
        // we only advance scroll_pos when scroll_x_offset wraps past 40,
        // so we'd lose the pointers between char-steps. Wasting 8 stores
        // beats having space invaders on screen.
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
        lda sine_table,y           // signed -2..+2
        // Sign-preserving arithmetic shift right, damp_shift times.
        // shift 0 = full amplitude; shift 5 = effectively 0.
        ldy damp_shift
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
        // X = sprite_x_table[N] + sine_table_x[phase + 64]   (amplitude ±1)
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
        lda sine_table_x,y         // signed -1..+1
        // Same damp ramp as DYCP — ASR sign-preserving.
        ldy damp_shift
        beq !x_no_damp+
!x_damp:
        cmp #$80
        ror
        dey
        bne !x_damp-
!x_no_damp:
        clc
        adc sprite_x_table,x      // base X + ±1 bob
        sec
        sbc scroll_x_offset        // smooth-scroll: subtract pixel offset
        pha
        // X reg offset = N*2 (preserves carry but we don't need it)
        txa
        asl
        tay
        pla
        sta $d000,y                // → $D000 / $D002 / ... / $D00E
        dex
        bpl !dxcp-

        // ----- Sprite-7 carousel override -----
        // For offsets 0..12 the DXCP loop above already placed sprite 7
        // correctly at screen X = 12..0 (exiting LEFT, sprite 7 hi-bit
        // clear). For offsets 13..39 we re-purpose sprite 7 as the
        // entering buffer on the RIGHT: it shows chars[scroll_pos+8]
        // (which the ptr override in update_sprite_ptrs has already put
        // into $07FF) and sits at screen X = 332..293 (= sprite 0's
        // position + 40, sliding LEFT in lockstep). Without this,
        // chars would pop into existence at sprite 0's X=292 on each
        // char-wrap instead of sliding smoothly in from off-right.
        lda scroll_x_offset
        cmp #13
        bcc !no_s7_carousel+
        lda #76                    // = 332 - 256 → reg byte for screen X=332
        sec
        sbc scroll_x_offset
        sta $d00e                  // sprite 7 X register
!no_s7_carousel:

        // ----- $D010 (sprite X hi-bits) for sprite 0 + sprite 7 -----
        // Smooth-scroll math: sprite_x_table[N] is the byte-low part of
        // sprite N's screen X. As scroll_x_offset grows from 0 to 40, the
        // 8-bit subtraction wraps for sprite 0 (logical X crosses 256→255
        // at offset=37) and for sprite 7 (logical role flips at offset=13).
        //
        //   Sprite 0 (rightmost visible, screen X = 292..253):
        //     offset 0..36  → screen X 292..256 → hi-bit SET, reg 36..0
        //     offset 37..39 → screen X 255..253 → hi-bit CLEAR, reg 255..253
        //
        //   Sprite 7 (carousel: leftmost OR rightmost-entering):
        //     offset 0..12  → screen X 12..0   → hi-bit CLEAR, reg 12..0
        //     offset 13..39 → screen X 319..293→ hi-bit SET, reg 63..37
        //                                          (entering buffer, ptr swapped
        //                                           to chars[scroll_pos+8])
        lda #0
        ldx scroll_x_offset
        cpx #37
        bcs !d010_skip_s0+
        ora #$01                   // sprite 0 hi-bit
!d010_skip_s0:
        cpx #13
        bcc !d010_skip_s7+
        ora #$80                   // sprite 7 hi-bit (carousel buffer at right)
!d010_skip_s7:
        sta $d010

        jmp !irq_exit+

!settled:
        // ----- Settle phase — held punchline -----
        // Snap scroll position to the settle_text label every frame
        // (idempotent — costs ~10 cy to overwrite the same bytes).
        lda #<(settle_text - message)
        sta zp_scroll_pos
        lda #>(settle_text - message)
        sta scroll_pos_hi
        // Reset smooth-scroll state so the flat-X writes below put each
        // sprite exactly on its sprite_x_table[N] position. Without this,
        // the per-IRQ subtraction would leave the row shifted left by the
        // last non-settle scroll_x_offset value.
        lda #0
        sta scroll_x_offset
        lda #$01                       // sprite 0 hi-bit set, sprite 7 hi-bit clear
        sta $d010
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
        sta msg_lookup_s7 + 1      // carousel reads from same base + Y=8
        lda #>message
        adc scroll_pos_hi
        sta msg_lookup + 2
        sta msg_lookup_s7 + 2

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

        // ----- Sprite-7 carousel ptr override -----
        // When scroll_x_offset >= 13, sprite 7 acts as the entering
        // buffer on the right side, showing chars[scroll_pos+8] instead
        // of the leftmost-exit char. Pairs with the X-register override
        // in the IRQ that puts sprite 7 at screen X=332..293 in that
        // offset range.
        lda scroll_x_offset
        cmp #13
        bcc !no_s7_ptr+
        ldy #8
msg_lookup_s7:
        lda $0000,y                  // patched to (message+scroll_pos)+8
        tay
        lda ptr_lookup,y
        sta SPR_PTR_BASE+7
!no_s7_ptr:
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
// Sprite pointer values for each input char. Font slots live at
// $0800-$0FFF (32 slots × 64 B), so ptr = $20 + slot. A-Z → slots
// 0..25, blank → slot 26, hyphen → slot 27.
.for (var i = 0; i < 256; i++) {
        .if (i >= $41 && i <= $5A) { .byte $20 + i - $41 }    // A-Z   → $20..$39
        .if (i == $2D)             { .byte $3B }              // '-'   → hyphen
        .if (i != $2D && (i < $41 || i > $5A)) { .byte $3A }  // other → blank
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

// Scroll SPEED per damp_shift step, in pixels per frame. At 40 px per
// sprite-stride and 50 fps, 9 px/frame ≈ 11.3 chars/sec — readable
// pace where the names blur a little but the eye can still lock on.
// Iteration: started at 5 (= 6.25 chars/sec, too slow), bumped to 12
// (~15 chars/sec, too fast), settled at 9. Fade ramps down so the
// smooth scroll decelerates into the settle freeze; damp 5 = 0 px/
// frame (settle phase overrides anyway).
SCROLL_SPEED_TABLE:
.byte 9, 6, 4, 2, 1, 0

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
// Amplitude 3 — bumped from 2 for more "wave alive" demoscene feel
// (user request 2026-05-21). The trade-off is the row swims more
// while you're trying to read names; with the faster scroll above,
// each name is on screen for less time anyway so the eye reads
// the silhouette rather than locking onto static letters.
.for (var i = 0; i < 256; i++) {
        .byte floor(3 * sin(i * 2 * PI / 256) + 0.5)
}

sine_table_x:
// Amplitude 2 — bumped from 1 to match the Y wobble bump. With 90°
// phase offset vs DYCP, each sprite traces a tiny ellipse instead
// of a vertical sine, adding more wobble character to the row.
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
* = $8700
message:
// 8-space intro pad so the screen starts blank before the first
// name slides in. Names are separated by three spaces — one inside
// multi-word names ("SILICON LTD"), three between groups reads as
// a clear gap to the eye.
.text "        "
.text "XENON   SILICON LTD   SCS TRC   "
.text "FOCUS   FAIRLIGHT   REFLEX   "
.text "BONZAI   GENESIS PROJECT   EXTEND   "
.text "TRSI   OXYRON   BYTERAPERS   "
.text "CENSOR DESIGN   CHANNEL FOUR   "
.text "PADUA   ATLANTIS   ELYSIUM   "
.text "EXCESS   TRIAD   NEOPLASIA   "
.text "THE DREAMS   RADWAR   PERFORMERS   "
.text "VANDALISM NEWS   NAH-KOLOR   LOTEK   "
.text "CHOCOTROPHY   PHOBOS TEAM   "
.text "SIDMASTERS   THE WEEKENDERS   "
.text "LETHARGY   ONSLAUGHT   SLACKERS   WGI2015   "
.text "SUCCESS   ARTLINE   RESOURCE   "
.text "PLUSH   FINNISH GOLD   NURDS   "
.text "OFFENCE   POO-BRAIN   RABENAUGE   "
.text "HOKUTO FORCE   ABYSS CONNECTION   "
// label fill the on-screen 8-sprite window once settle kicks in;
// pad with trailing spaces so even if the scroller drifts past it
// for any reason, the visible window stays clean. " KLOTEN " is
// centred symmetrically in the 8-sprite row (1 leading + 6-char
// name + 1 trailing) and ties this punchline to the demo's coda
// title "KLOTEN MET DE BROODTROMMEL".
settle_text:
.text " KLOTEN                                    "
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

// Hyphen glyph for ptr_lookup's $9B slot — chargen ROM `-` at code
// $2D, scaled to 24×21 the same way A-Z are. Lets NAH-KOLOR and
// POO-BRAIN render correctly instead of becoming NAH KOLOR / POO BRAIN.
.var g_hyphen = glyph_data_21x24($2D)
.for (var i = 0; i < g_hyphen.size(); i++) {
        .byte g_hyphen.get(i)
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


//==================================================================
// Koala backdrop — multicolour 320×200 bitmap loaded from a .kla file.
//
// Layout in memory (placed by pefchain at boot via the EFO P-claims):
//   $0400-$07E7  per-cell screen attributes (1000 bytes; c1 hi nibble,
//                c2 lo nibble). Sprite ptrs at $07F8-$07FF still work
//                because they're past the visible 1000-cell area.
//   $2000-$3F3F  raw bitmap (8000 bytes; 8 bytes per cell × 1000 cells).
//   $D800-$DBE7  per-cell c3 colour (copied from koala_color at setup).
//   $D021        global background colour c0 (loaded from koala_bg).
//
// To swap the backdrop: just edit parts/greets/backdrop.kla directly
// with a C64-native paint tool — MultiPaint is the recommended one:
//   http://multipaint.kameli.net/
// It shows the per-cell colour-budget constraints live as you paint,
// so you can't accidentally exceed MCM's 4-colours-per-cell limit.
// Save → overwrites backdrop.kla → ./build.sh and you're done.
//
// If you'd rather work in a general PNG editor, the round-trip is:
//   1. edit parts/greets/backdrop.png (320×200 indexed PNG)
//   2. python3 tools/png_to_koala.py parts/greets/backdrop.png \
//          parts/greets/backdrop.kla
//   3. ./build.sh
// See tools/make_greets_backdrop.py for the placeholder generator
// that produced the initial peephole image.
//==================================================================
.var backdrop = LoadBinary("backdrop.kla", BF_KOALA)

.pc = $2000 "BackdropBitmap"
.fill 8000, backdrop.getBitmap(i)

// koala_screen, koala_color, koala_bg all live above font_data (which
// ends ~$902c) inside the expanded $80-$9F EFO claim. setup CPU-copies
// koala_screen to $0400 and koala_color to $D800 at boot.
//
// Why $0400 isn't loaded directly by pefchain: claiming $04-$07 in
// the EFO blocks pefchain from using those pages for blank-filler
// effects during background load — which it must do to mask greets'
// large data load (~10 KB of bitmap + buffers). The blanks paint a
// flat screen at $0400, so $04-$07 needs to be unowned.
.pc = $9800 "BackdropScreenBuffer"
koala_screen:
.fill 1000, backdrop.getScreenRam(i)

.pc = $9c00 "BackdropColorBuffer"
koala_color:
.fill 1000, backdrop.getColorRam(i)
koala_bg:
.byte backdrop.getBackgroundColor()
