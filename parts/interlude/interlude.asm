//==================================================================
// outline-64 — Part 2.5: interlude
//
// Between intro and end. Continues intro's chord progression and lead
// melody (calls intro's my_music_play at $119e — its tables stay
// resident at $1000-$125D and pefchain won't touch them because we
// declare 'I',$10,$12 in the EFO header).
//
// Sound arc:
//   beats  0..23  → pad-only breather (V1 bass muted, lead + arp drift)
//   beats 24..31  → V1 bass returns + cutoff ramps from $80 → $FF, building
//                   tension into greets ("groove into next part")
//
// V1's intro-set ADSR (AD=$04, SR=$61 — punchy bass) is preserved so
// the bass sounds correct the moment we unmute it. We just write
// $D404 = 0 (control = no wave + gate off) every frame in the muted
// window, then stop doing that once the build-up beat hits.
//
// Lives at $8000 — a free area that doesn't conflict with intro
// ($0400-$5bbc), end's load region ($3000-$444c), or the spindle
// resident loader at $0200-$03ff.
//
// Spindle 3.1 lifecycle: setup / interrupt / fadeout (sec/rts, the
// script transitions on f6 = $20).
//==================================================================

.const VIC_CTRL1  = $d011
.const VIC_RASTER = $d012
.const SPR_EN     = $d015
.const VIC_CTRL2  = $d016
.const VIC_MEM    = $d018
.const VIC_IRQ    = $d019
.const VIC_BORDER = $d020
.const VIC_BG     = $d021

// Intro's resident music routine address (from intro.sym).
.const INTRO_MUSIC_PLAY = $119e

// Beat pacing — 24 frames per beat × 32 beats ≈ 15 s.
.const BEAT_PERIOD     = 24
.const BUILDUP_BEAT    = 24      // bass returns + sweep starts at this beat
.const N_BUILDUP_BEATS = 8       // 32 - 24 — beats of build-up before transition

// Filter sweep starting + final cutoff (only active during build-up).
.const FILT_CUT_LO     = $40     // muffled-ish opening of the sweep
.const FILT_CUT_STEP   = $18     // per-beat ramp ($40 + 8*$18 = $100 → $FF clamp)

// Zero-page
.const zp_beat_phase = $f4        // counts 0..BEAT_PERIOD-1
.const zp_filt_cut   = $f5        // current filter cutoff during build-up
.const zp_beat_count = $f6        // total beats — script transitions on f6 = $20

* = $8000 "Interlude"

setup:
        // VIC bank 0, default text mode setup. Black bg + border, no
        // sprites — visuals to be added in a later iteration.
        lda #$3c
        sta $dd02
        lda #%00010100            // screen $0400, chargen $1000
        sta VIC_MEM
        lda #$1b                  // text mode, DEN, RSEL, yscroll=3
        sta VIC_CTRL1
        lda #$08                  // CSEL, mono
        sta VIC_CTRL2
        lda #$00
        sta SPR_EN
        sta VIC_BORDER
        sta VIC_BG

        // SID master volume — intro's fadeout no longer silences it,
        // but reassert in case it drifted.
        lda #$1f
        sta $d418

        // Mute V1 (bass) by writing control = 0 (no wave + gate off).
        // CRITICAL: do NOT touch $D405/$D406 — we want intro's punchy
        // bass ADSR (AD=$04, SR=$61) preserved so the bass sounds right
        // the moment we unmute it at BUILDUP_BEAT.
        lda #$00
        sta $d404

        // Filter starts off (cutoff 0, no routing) — when the build-up
        // hits we route V2 through LP, set initial cutoff, and ramp.
        sta $d416                 // cutoff hi
        sta $d417                 // resonance + voice routing
        sta zp_filt_cut

        // Init beat state
        sta zp_beat_phase
        sta zp_beat_count

        // Raster IRQ at top of frame
        lda #$00
        sta VIC_RASTER
        rts


//==================================================================
// interrupt — per-frame. Continues intro's music, gates V1 mute /
// filter sweep on the beat count, ticks the beat counter for the
// script transition.
//==================================================================
interrupt:
        pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta VIC_IRQ

        // Continue intro's chord progression + lead.
        jsr INTRO_MUSIC_PLAY

        // my_music_play writes $D418 = vol_in each frame (which is
        // $0f once zp_intro saturated). Re-assert $1F to put SID back
        // into LP filter mode (bit 4) with full vol — we need the LP
        // mode for the build-up's cutoff sweep.
        lda #$1f
        sta $d418

        // V1 mute logic: while beat_count < BUILDUP_BEAT, force V1
        // control to 0 (silent). Once we're in the build-up window
        // we stop overwriting — music_play's next bass-note write
        // wakes V1 back up with intro's AD/SR envelope intact.
        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcs !buildup+

        // Still in pad-only phase — kill V1.
        lda #$00
        sta $d404
        jmp !beat+

!buildup:
        // Build-up phase — V1 plays naturally (no mute). Sweep the
        // LP filter cutoff every frame so the closing tension is
        // smooth, not stepped per beat. Route V1 (bass) through LP
        // so its return swells in.
        lda #$01                  // V1 routed to filter (bit 0 = V1 → filter)
        sta $d417                 // resonance=0 (clean), routing=V1
        lda zp_filt_cut
        sta $d416                 // cutoff hi (8-bit, lo nibble of $D415 left 0)

!beat:
        // ---- beat counter (script transition + filter sweep step) ----
        inc zp_beat_phase
        lda zp_beat_phase
        cmp #BEAT_PERIOD
        bcc !no_beat+
        lda #0
        sta zp_beat_phase
        inc zp_beat_count         // pefchain transitions when this hits $20

        // On each beat in build-up, ramp the filter cutoff up.
        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcc !no_beat+
        cmp #BUILDUP_BEAT         // first build-up beat: init cutoff
        bne !ramp+
        lda #FILT_CUT_LO
        sta zp_filt_cut
        jmp !no_beat+
!ramp:
        lda zp_filt_cut
        clc
        adc #FILT_CUT_STEP
        bcs !sat+                 // overflow → saturate at $FF
        sta zp_filt_cut
        jmp !no_beat+
!sat:
        lda #$ff
        sta zp_filt_cut
!no_beat:

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// fadeout — script transitions on f6 = $20. Just returns carry set so
// pefchain moves on. Leave SID state alone so the build-up's filter
// sweep + bass momentum carries straight into greets.
//==================================================================
fadeout:
        sec
        rts
