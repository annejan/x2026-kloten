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
//   row 13  BY DEFEEST   FOR X 2026
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
        // First kick fires after a short lead-in so the title is up
        // before the first thump lands.
        lda #25                         // ~0.5 s lead-in
        sta zp_kick_count

        // Sprites off (greets had 8 enabled)
        lda #$00
        sta $d015

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

        // ---- paint the title text ----
        // Row 11 starts at $0400 + 11*40 = $05B8.
        // "KLOOT AND THE BREADBIN" = 22 chars, center at col 9.
        // Row 13 ($0608): "BY DEFEEST   FOR X 2026" = 23 chars, col 8.
        ldx #0
!t1:    lda title_main,x
        sta $05B8 + 9,x
        inx
        cpx #22
        bne !t1-

        ldx #0
!t2:    lda title_sub,x
        sta $0608 + 8,x
        inx
        cpx #23
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
!c2:    sta $DA08 + 8,x
        inx
        cpx #23
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
//   - half-rate tick: zp_frame only advances every 2nd IRQ
//   - star_field: twinkle 16 stars in top rows (4 banks of 4)
//   - if zp_frame >= N_FRAMES, set $F6 = $30 (transition)
//   - else border = col_tab[zp_frame] for slow sine colour cycle
//==================================================================
interrupt:
        jsr INTRO_MUSIC_PLAY

        jsr star_field
        jsr coda_kick

        // half-rate divider
        lda zp_subtick
        eor #1
        sta zp_subtick
        bne !skip_inc+
        inc zp_frame
!skip_inc:

        lda zp_frame
        cmp #N_FRAMES
        bcc !run+
        lda #$30
        sta zp_timer
        lda #$00
        sta VIC_BORDER                  // settle to black before transition
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

// "BY DEFEEST   FOR X 2026"  (23 chars)
//   B=02 Y=19 _=20  D=04 E=05 F=06 E=05 E=05 S=13 T=14 _=20 _=20 _=20
//   F=06 O=0F R=12 _=20  X=18 _=20  2=32 0=30 2=32 6=36
title_sub:
        .byte $02, $19, $20                                 // BY_
        .byte $04, $05, $06, $05, $05, $13, $14, $20        // DEFEEST_
        .byte $20, $20                                       // __
        .byte $06, $0F, $12, $20                            // FOR_
        .byte $18, $20                                       // X_
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
