//==================================================================
// outline-64 — Part 2.5: interlude
//
// Between intro and end. Continues intro's chord progression and lead
// melody (calls intro's my_music_play at $119e — its tables stay
// resident at $1000-$125D and pefchain won't touch them because we
// declare 'I',$10,$12 in the EFO header).
//
// Currently a quieter pad-only breather: bass (V1) is muted to give
// the lead room to breathe. No drum / no filter pump — just the chord
// progression + lead drifting alone. Beat counter at $f6 still ticks
// every 24 frames so the script transition (f6 = $20) fires at ~15s.
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

// Beat pacing — keep this even though we don't drum, so the script
// transition condition stays time-aligned with the prior interlude
// design (~125 BPM, 24 frames per beat, 32 beats ≈ 15 s).
.const BEAT_PERIOD = 24

// Zero-page
.const zp_beat_phase = $f4        // counts 0..BEAT_PERIOD-1
.const zp_unused     = $f5        // (reserved by EFO 'Z' range)
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
        // but reassert in case it drifted. LP filter stays on.
        lda #$1f
        sta $d418

        // Mute V1 (bass) for this interlude — silence its gate and
        // freeze freq so the music engine's next write keeps it quiet.
        // V1 control = 0 (gate off, no waveform). The chord engine
        // writes freq each step but only re-gates on note changes, so
        // killing the gate now means V1 stays silent for the whole part.
        lda #$00
        sta $d404                 // V1 control (gate off, no wave)
        sta $d405                 // V1 AD = 0
        sta $d406                 // V1 SR = 0

        // Init beat state
        lda #0
        sta zp_beat_phase
        sta zp_beat_count

        // Raster IRQ at top of frame
        lda #$00
        sta VIC_RASTER
        rts


//==================================================================
// interrupt — per-frame. Continues intro's music, mutes V1 each frame,
// ticks the beat counter for the script transition.
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

        // Re-mute V1 every frame — intro's music engine will gate V1
        // on each new bass note, so we squash it again right after.
        lda #$00
        sta $d404

        // ---- beat counter (script transition only) ----
        inc zp_beat_phase
        lda zp_beat_phase
        cmp #BEAT_PERIOD
        bcc !no_beat+
        lda #0
        sta zp_beat_phase
        inc zp_beat_count         // pefchain transitions when this hits $20
!no_beat:

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// fadeout — script transitions on f6 = $20. Just returns carry set so
// pefchain moves on to end. We don't silence SID — end's setup
// re-inits everything via end_music_init anyway, and keeping voices
// alive avoids an audible click across the transition.
//==================================================================
fadeout:
        sec
        rts
