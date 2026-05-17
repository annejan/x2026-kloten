//==================================================================
// outline-64 — Part 2.5: interlude
//
// Between intro and end. Continues intro's chord progression and lead
// melody (calls intro's my_music_play at $119e — its tables stay
// resident at $1000-$125D and pefchain won't touch them because we
// declare 'I',$10,$12 in the EFO header).
//
// On top of the music we add:
//   - "unz unz" kick on V3 every KICK_PERIOD frames: noise burst with
//     short decay. Arp drops out for the kick frame, restored after.
//   - Filter cutoff pump synced to the kick — drops to 0 on each beat
//     and ramps back up, giving the pad a sidechained "breathing" feel.
//   - Border flashes white on each kick for visual feedback (the rest
//     of the screen is black — visuals to be filled in later).
//
// Lives at $8000 — a free area that doesn't conflict with intro
// ($0400-$5bbc), end's load region ($3000-$444c), or the spindle
// resident loader at $0200-$03ff.
//
// Spindle 3.1 lifecycle: setup / interrupt / fadeout (sec/rts, the
// script transitions on space).
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

// Kick parameters
.const KICK_PERIOD     = 24       // 24 frames @ 50Hz ≈ 125 BPM
.const FILTER_RAMP     = $14      // cutoff added per frame after a kick

// Zero-page
.const zp_kick_phase = $f4        // counts 0..KICK_PERIOD-1
.const zp_filter_cut = $f5        // current filter cutoff (climbing)
.const zp_beat_count = $f6        // total beats since setup — pefchain
                                  //   script transitions on f6 = $20 (32 beats
                                  //   × 24 frames ≈ 15 sec @ ~125 BPM).

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

        // Restore SID master volume — intro's fadeout silenced it
        // (lda #0 / sta $d418). LP filter stays on.
        lda #$1f
        sta $d418

        // Init kick + filter state
        lda #0
        sta zp_kick_phase
        sta zp_beat_count
        lda #$80                  // mid filter cutoff to start
        sta zp_filter_cut

        // Raster IRQ at top of frame
        lda #$00
        sta VIC_RASTER
        rts


//==================================================================
// interrupt — per-frame. Continues intro's music, layers kick + filter.
//==================================================================
interrupt:
        pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta VIC_IRQ

        // Continue intro's chord progression + lead. V1 bass + V2
        // lead are written every step boundary; V3 arp gets written
        // every 4 frames within a step — we'll override V3 on kick
        // frames and let the music re-arm it on its next arp tick.
        jsr INTRO_MUSIC_PLAY

        // ---- kick + filter pump ----
        inc zp_kick_phase
        lda zp_kick_phase
        cmp #KICK_PERIOD
        bcc !no_kick+

        // BEAT — reset phase, count it, fire kick, slam filter shut.
        lda #0
        sta zp_kick_phase
        inc zp_beat_count         // pefchain transitions when this hits $20

        // V3 kick: noise + percussive ADSR + low pitch.
        lda #$00                  // freq lo
        sta $d40e
        lda #$04                  // freq hi (pitch doesn't matter for noise)
        sta $d40f
        lda #$08                  // AD: attack=0, decay=8 (~80ms)
        sta $d413
        lda #$00                  // SR: sustain=0, release=0 → percussive
        sta $d414
        lda #$81                  // noise wave + gate
        sta $d412

        // Slam filter cutoff to 0 (closed) — pad mutes momentarily.
        lda #$00
        sta zp_filter_cut
        sta $d416

        // Border flash for visual feedback (white on beat)
        lda #$01
        sta VIC_BORDER
        jmp !done+

!no_kick:
        // Restore V3 ADSR so the arp tone has a sustain again. Intro's
        // my_music_init used $00/$f0 (a=0,d=0,s=15,r=0). On non-kick
        // frames the music's next V3 write picks this up.
        lda #$00
        sta $d413
        lda #$f0
        sta $d414

        // Ramp filter cutoff back up (sidechain pump)
        lda zp_filter_cut
        clc
        adc #FILTER_RAMP
        bcs !cut_max+             // saturate at $ff
        cmp #$ff
        bcc !cut_ok+
!cut_max:
        lda #$ff
!cut_ok:
        sta zp_filter_cut
        sta $d416

        lda #$00
        sta VIC_BORDER
!done:
        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// fadeout — script transitions on space. Just returns carry set so
// pefchain moves on to end. (We could silence SID here too, but end's
// setup re-inits everything via end_music_init anyway.)
//==================================================================
fadeout:
        sec
        rts
