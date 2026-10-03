// Kloten met de broodtrommel — site mix
//
// A standalone SID tune (PSID, load $1000, init $1000, play $1003) for
// annejan.com. It plays the demo's own material — the note table, the
// Am-Em-F-G chords, arp_notes, bass_pattern, lead_pattern and the K-S-K-S
// kit, copied unchanged from parts/intro/intro.asm — and walks the sound
// arc from docs/sound-arc.md as sections: intro build, intro outro with
// drums, interlude pad + slam, hush filter close, greets wah climax,
// triumphant coda, slow end reprise. On top of that it adds what the
// resident player had no room for: PWM on every voice, delayed lead
// vibrato, hard restart, hi-hats, fills, snare rolls and a pad echo.
//
// 125 BPM: 6 frames per step, 4 steps per beat, 0.48 s per beat. The
// whole song is 320 beats (153.6 s), five 64-beat loops of the site's
// demo, so the demo's visuals stay on the beat when the audio loops.
//
// Build: java -jar ../kickass/KickAss.jar sitemix.asm -o out/sitemix.prg
//        python3 make_psid.py out/sitemix.prg out/sitemix.sid

.const NOTE_REST = $ff
.const VIB_DELAY = 10           // frames before the lead vibrato starts
.const N_C1 = 12                // ~33 Hz sub-bass layer under every beat drum

// Section flags
.const FL_HATS = $01            // closed hi-hat on the off-beat 8ths
.const FL_FILL = $02            // snare fill at the end of every chord cycle
.const FL_ROLL = $04            // snare roll on the last two beats of the section
.const FL_ECHO = $08            // V3 echoes the lead while the arp is off

// Cutoff modes
.const CUT_OFF  = 0
.const CUT_RAMP = 1             // linear from cutA to cutB over the section
.const CUT_LFO  = 2             // cutA + (sine >> cutShift), sine speed frame >> lfoShift

// Volume modes
.const VOL_FULL    = 0
.const VOL_FADEIN  = 1          // 0 -> 15 over the first 240 frames
.const VOL_FADEOUT = 2          // 15 -> 0 over the last 60 frames
.const VOL_SLOWOUT = 3          // 15 -> 0 over the last 120 frames

.function Section(beats, speed, leadStart, transpose, enBass, enArp, enDrum, flags,
                  route, cutMode, cutA, cutB, cutShift, lfoShift, volMode,
                  wave1, wave2, wave3, ad1, sr1, ad2, sr2, ad3, sr3, arpAd, arpSr) {
    .var s = Hashtable()
    .eval s.put("beats", beats)
    .eval s.put("speed", speed)
    .eval s.put("spb", speed == 6 ? 4 : 1)          // steps per beat
    .eval s.put("leadStart", leadStart)
    .eval s.put("transpose", transpose)
    .eval s.put("enBass", enBass)
    .eval s.put("enArp", enArp)
    .eval s.put("enDrum", enDrum)
    .eval s.put("flags", flags)
    .eval s.put("route", route)
    .eval s.put("mode", route == 0 ? $00 : $10)     // LP filter mode when anything is routed
    .eval s.put("cutMode", cutMode)
    .eval s.put("cutA", cutA)
    .eval s.put("cutShift", cutShift)
    .eval s.put("lfoShift", lfoShift)
    .eval s.put("volMode", volMode)
    .eval s.put("wave1", wave1)
    .eval s.put("wave2", wave2)
    .eval s.put("wave3", wave3)
    .eval s.put("ad1", ad1)
    .eval s.put("sr1", sr1)
    .eval s.put("ad2", ad2)
    .eval s.put("sr2", sr2)
    .eval s.put("ad3", ad3)
    .eval s.put("sr3", sr3)
    .eval s.put("arpAd", arpAd)
    .eval s.put("arpSr", arpSr)
    .var frames = beats * 4 * 6                      // every section lasts beats * 24 frames
    .eval s.put("frames", frames)
    .var delta = cutMode == CUT_RAMP ? floor((cutB - cutA) * 256 / frames) : 0
    .eval s.put("delta", delta & $ffff)
    .return s
}

.var songs = List()
//                    beats spd lead tr  bass arp drum flags                      route cut       A    B    cs ls  vol           w1   w2   w3   ad1  sr1  ad2  sr2  ad3  sr3  arpAd arpSr
.eval songs.add(Section(32,  6,  0,  0,  10,  20, 255, 0,                          $00, CUT_OFF,  $ff, $ff, 0, 0, VOL_FADEIN,  $40, $40, $40, $04, $61, $02, $81, $00, $f0, $00, $f0))  // intro
.eval songs.add(Section(32,  6,  0,  0,   0,   0,   0, FL_HATS|FL_FILL,            $00, CUT_OFF,  $ff, $ff, 0, 0, VOL_FULL,    $40, $40, $40, $04, $61, $02, $81, $00, $f0, $00, $f0))  // intro outro
.eval songs.add(Section(32,  6, 32,  0,   8,   8,   8, FL_HATS|FL_ROLL|FL_ECHO,    $23, CUT_RAMP, $70, $ff, 0, 0, VOL_FULL,    $40, $40, $10, $04, $61, $02, $81, $09, $00, $00, $f0))  // interlude
.eval songs.add(Section(32,  6, 64,  0,   0,   0,   0, FL_FILL,                    $23, CUT_RAMP, $70, $08, 0, 0, VOL_FADEOUT, $40, $40, $40, $04, $61, $02, $81, $00, $f0, $00, $f0))  // hush
.eval songs.add(Section(64,  6, 64,  0,   0,   0,   0, FL_HATS|FL_FILL,            $42, CUT_LFO,  $40, $00, 0, 0, VOL_FULL,    $40, $40, $10, $04, $61, $02, $81, $00, $f0, $00, $f0))  // greets
.eval songs.add(Section(64,  6, 32,  0,   0,   0,   0, FL_HATS|FL_FILL|FL_ROLL,    $26, CUT_LFO,  $60, $00, 1, 1, VOL_FULL,    $40, $40, $10, $04, $61, $02, $81, $00, $f0, $00, $f0))  // coda
.eval songs.add(Section(64, 24,  0,  0,   0,   0, 255, 0,                          $07, CUT_LFO,  $20, $00, 2, 0, VOL_SLOWOUT, $10, $10, $40, $2a, $a8, $2a, $a8, $00, $98, $00, $98))  // end
.const SECTIONS = songs.size()

// ---------------------------------------------------------------------------
* = $1000 "Player"
        jmp init
        jmp play

// Note-period table for the SID PAL clock: the demo's 60 entries (C-0..B-4)
// unchanged, plus C-5..B-6 for transposed leads.
.var demoLo = List().add($17, $27, $39, $4b, $5f, $74, $8a, $a1, $ba, $d4, $ef, $0c,
                         $2d, $4f, $73, $97, $be, $e8, $14, $42, $74, $a9, $df, $19,
                         $5a, $9e, $e7, $35, $7e, $d0, $28, $85, $e8, $52, $bd, $33,
                         $b4, $3d, $cf, $6a, $fc, $a0, $50, $0a, $d0, $a3, $7d, $66,
                         $68, $7a, $9e, $d4, $f8, $40, $a0, $14, $a0, $46, $fa, $cc)
.var demoHi = List().add($01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $02,
                         $02, $02, $02, $02, $02, $02, $03, $03, $03, $03, $03, $04,
                         $04, $04, $04, $05, $05, $05, $06, $06, $06, $07, $07, $08,
                         $08, $09, $09, $0a, $0a, $0b, $0c, $0d, $0d, $0e, $0f, $10,
                         $11, $12, $13, $14, $15, $17, $18, $1a, $1b, $1d, $1e, $20)
.function noteReg(n) {
    .if (n < 60) .return demoHi.get(n) * 256 + demoLo.get(n)
    .return round(7494 * pow(2, (n - 57) / 12))     // anchored on the demo's A-4
}
sid_freq_lo: .fill 84, <noteReg(i)
sid_freq_hi: .fill 84, >noteReg(i)

// Chords and patterns, unchanged from intro.asm.
.const N_E2 = 28
.const N_F2 = 29
.const N_G2 = 31
.const N_A2 = 33
.const N_B2 = 35
.const N_C3 = 36
.const N_D3 = 38
.const N_E3 = 40
.const N_F3 = 41
.const N_G3 = 43
.const N_A3 = 45
.const N_B3 = 47
.const N_C4 = 48
.const N_D4 = 50
.const N_E4 = 52
.const N_F4 = 53
.const N_G4 = 55
.const N_A4 = 57
.const N_B4 = 59

chord_per_step:
        .byte 0,0,0,0,0,0,0,0    // Am
        .byte 3,3,3,3,3,3,3,3    // Em
        .byte 1,1,1,1,1,1,1,1    // F
        .byte 2,2,2,2,2,2,2,2    // G
arp_notes:
        .byte N_A2, N_C3, N_E3, N_A3    // Am
        .byte N_F2, N_A2, N_C3, N_F3    // F
        .byte N_G2, N_B2, N_D3, N_G3    // G
        .byte N_E2, N_G2, N_B2, N_E3    // Em
bass_pattern:
        .byte N_A2, N_A2, N_A3, N_A2, N_A2, N_E3, N_A3, N_A2
        .byte N_E2, N_E2, N_E3, N_E2, N_E2, N_B2, N_E3, N_E2
        .byte N_F2, N_F2, N_F3, N_F2, N_F2, N_C3, N_F3, N_F2
        .byte N_G2, N_G2, N_G3, N_G2, N_G2, N_D3, N_G3, N_G2
lead_pattern:
        .byte N_A3,NOTE_REST,N_E3,NOTE_REST, N_A3,N_C4,N_E3,NOTE_REST
        .byte N_G3,NOTE_REST,N_B3,NOTE_REST, N_E4,N_G3,N_E3,NOTE_REST
        .byte N_F3,NOTE_REST,N_A3,NOTE_REST, N_F4,N_A3,N_C4,NOTE_REST
        .byte N_G3,NOTE_REST,N_B3,NOTE_REST, N_D4,N_G4,N_F4,N_E4
        .byte N_A4,N_C4,N_E4,N_A4, N_C4,N_E4,N_C4,N_A3
        .byte N_B3,N_D4,N_G3,N_B3, N_E4,N_G3,N_E3,N_B3
        .byte N_C4,N_A3,N_F3,N_A3, N_F4,N_C4,N_A3,N_F3
        .byte N_D4,N_B3,N_G3,N_B3, N_G4,N_D4,N_B3,N_G3
        .byte N_E4,N_A4,N_E4,N_C4, N_A4,N_E4,N_A4,N_E4
        .byte N_B3,N_E4,N_G4,N_B4, N_E4,N_B3,N_E4,N_G4
        .byte N_C4,N_F4,N_A4,NOTE_REST, N_F4,N_C4,N_A3,N_F3
        .byte N_G4,N_B4,N_D4,NOTE_REST, N_B4,N_G4,N_D4,N_B3
        .byte N_E4,NOTE_REST,N_C4,NOTE_REST, N_A3,NOTE_REST,NOTE_REST,NOTE_REST
        .byte N_E4,NOTE_REST,N_B3,NOTE_REST, N_G3,NOTE_REST,NOTE_REST,NOTE_REST
        .byte N_F3,NOTE_REST,N_C4,NOTE_REST, N_F3,NOTE_REST,NOTE_REST,NOTE_REST
        .byte N_G3,NOTE_REST,N_D4,NOTE_REST, N_G3,NOTE_REST,NOTE_REST,NOTE_REST

// V3 drum rows { ctrl, freq-hi }. Kick and snare are the demo's kit; the
// hi-hat and the roll snare are new.
drum_table:
        .byte $11, $10,  $11, $04,  $11, $02,  $11, $02     // 0  kick: triangle pitch slam
        .byte $00, $00,  $81, $20,  $11, $10,  $11, $05     // 8  snare: flam, noise, triangle body
        .byte $81, $d0,  $00, $00,  $00, $00,  $00, $00     // 16 closed hi-hat: one frame of high noise
        .byte $81, $30,  $11, $0e,  $11, $06,  $00, $00     // 24 roll snare: short and tight
drum_len:
        .byte 4, 4, 1, 3                                    // per drum type (offset / 8)

// Vibrato shape over 8 frames (6.25 Hz): multiplier and sign.
vib_mul: .byte 0, 1, 2, 1, 0, 1, 2, 1
vib_neg: .byte 0, 0, 0, 0, 0, 1, 1, 1

// One sine period, 0..255.
sine: .fill 256, round(127.5 + 127.5 * sin(toRadians(i * 360 / 256)))

// Section tables, one byte (or word) per section.
sec_beats:     .fill SECTIONS, songs.get(i).get("beats")
sec_speed:     .fill SECTIONS, songs.get(i).get("speed")
sec_spb:       .fill SECTIONS, songs.get(i).get("spb")
sec_lead:      .fill SECTIONS, songs.get(i).get("leadStart")
sec_tr:        .fill SECTIONS, songs.get(i).get("transpose")
sec_enbass:    .fill SECTIONS, songs.get(i).get("enBass")
sec_enarp:     .fill SECTIONS, songs.get(i).get("enArp")
sec_endrum:    .fill SECTIONS, songs.get(i).get("enDrum")
sec_flags:     .fill SECTIONS, songs.get(i).get("flags")
sec_route:     .fill SECTIONS, songs.get(i).get("route")
sec_mode:      .fill SECTIONS, songs.get(i).get("mode")
sec_cutmode:   .fill SECTIONS, songs.get(i).get("cutMode")
sec_cuta:      .fill SECTIONS, songs.get(i).get("cutA")
sec_cutshift:  .fill SECTIONS, songs.get(i).get("cutShift")
sec_lfoshift:  .fill SECTIONS, songs.get(i).get("lfoShift")
sec_volmode:   .fill SECTIONS, songs.get(i).get("volMode")
sec_wave1:     .fill SECTIONS, songs.get(i).get("wave1")
sec_wave2:     .fill SECTIONS, songs.get(i).get("wave2")
sec_wave3:     .fill SECTIONS, songs.get(i).get("wave3")
sec_ad1:       .fill SECTIONS, songs.get(i).get("ad1")
sec_sr1:       .fill SECTIONS, songs.get(i).get("sr1")
sec_ad2:       .fill SECTIONS, songs.get(i).get("ad2")
sec_sr2:       .fill SECTIONS, songs.get(i).get("sr2")
sec_ad3:       .fill SECTIONS, songs.get(i).get("ad3")
sec_sr3:       .fill SECTIONS, songs.get(i).get("sr3")
sec_arpad:     .fill SECTIONS, songs.get(i).get("arpAd")
sec_arpsr:     .fill SECTIONS, songs.get(i).get("arpSr")
sec_frames_lo: .fill SECTIONS, <songs.get(i).get("frames")
sec_frames_hi: .fill SECTIONS, >songs.get(i).get("frames")
sec_delta_lo:  .fill SECTIONS, <songs.get(i).get("delta")
sec_delta_hi:  .fill SECTIONS, >songs.get(i).get("delta")

// ---------------------------------------------------------------------------
// State

frame_lo:     .byte 0
frame_hi:     .byte 0
tick:         .byte 0       // frame within the step, 0..speed-1
speed:        .byte 6
sec:          .byte 0       // current section
beat:         .byte 0       // beat within the section
sub:          .byte 0       // step within the beat
step:         .byte 0       // next lead_pattern index, 0..127
cur_step:     .byte 0       // the step that is sounding now
elapsed_lo:   .byte 0       // frames since the section started
elapsed_hi:   .byte 0
left_lo:      .byte 0       // frames until the section ends
left_hi:      .byte 0
cut_lo:       .byte 0       // cutoff accumulator, high byte goes to $d416
cut_hi:       .byte 0
bass_on:      .byte 0
arp_on:       .byte 0
arp_was:      .byte 0
arp_hold:     .byte 0       // 1 = keep the gate off for one frame (retrigger)
drums_on:     .byte 0
drum_state:   .byte 0       // frames left in the current drum hit
drum_offset:  .byte 0       // row offset into drum_table
lead_on:      .byte 0
lead_age:     .byte 0
lead_flo:     .byte 0       // lead base frequency
lead_fhi:     .byte 0
lead_depth:   .byte 0       // vibrato depth (freq-lo units)
echo_ring:    .byte NOTE_REST, NOTE_REST, NOTE_REST, NOTE_REST
echo_idx:     .byte 0
pw_lo:        .byte $00, $00, $00
pw_hi:        .byte $08, $06, $04
pw_dir:       .byte 0, 0, 0
tmp:          .byte 0

// ---------------------------------------------------------------------------

init:
        ldx #$18
        lda #0
!:      sta $d400,x
        dex
        bpl !-
        lda #0
        sta sec
        sta frame_lo
        sta frame_hi
        jsr start_section
        rts

// Set up section `sec`: voices, filter, counters.
start_section:
        ldx sec
        lda sec_speed,x
        sta speed
        lda sec_lead,x
        sta step
        lda #0
        sta beat
        sta sub
        sta tick
        sta elapsed_lo
        sta elapsed_hi
        sta arp_was
        sta arp_hold
        sta drum_state
        lda sec_frames_lo,x
        sta left_lo
        lda sec_frames_hi,x
        sta left_hi
        lda sec_ad1,x
        sta $d405
        lda sec_sr1,x
        sta $d406
        lda sec_ad2,x
        sta $d40c
        lda sec_sr2,x
        sta $d40d
        lda sec_ad3,x
        sta $d413
        lda sec_sr3,x
        sta $d414
        lda sec_route,x
        sta $d417
        lda #0
        sta $d415
        sta cut_lo
        lda sec_cuta,x
        sta cut_hi
        sta $d416
        rts

play:
        // Frame counters
        inc frame_lo
        bne !+
        inc frame_hi
!:      inc elapsed_lo
        bne !+
        inc elapsed_hi
!:      lda left_lo
        bne !+
        dec left_hi
!:      dec left_lo

        lda tick
        bne !+
        jsr step_boundary
!:
        jsr voice3_frame
        jsr lead_vibrato
        jsr pwm_all
        jsr filter_frame
        jsr volume_frame

        // Hard restart: gate V1 and V2 off on the last frame of every step,
        // so the next note starts from a released envelope.
        ldx sec
        ldy tick
        iny
        cpy speed
        bne !+
        lda sec_wave1,x
        sta $d404
        lda sec_wave2,x
        sta $d40b
        lda sec_flags,x                 // the echo voice too, while it plays
        and #FL_ECHO
        beq !+
        lda arp_on
        bne !+
        lda sec_wave3,x
        sta $d412
!:      inc tick
        lda tick
        cmp speed
        bne !+
        lda #0
        sta tick
!:      rts

// ---------------------------------------------------------------------------
// Once per step: notes, drums, section changes.

step_boundary:
        // End of the section?
        ldx sec
        lda beat
        cmp sec_beats,x
        bne !+
        inx
        cpx #SECTIONS
        bne !next+
        ldx #0
!next:  stx sec
        jsr start_section
        ldx sec
!:
        // Which voices play from this beat on
        lda #0
        sta bass_on
        sta arp_on
        sta drums_on
        lda beat
        cmp sec_enbass,x
        bcc !+
        inc bass_on
!:      lda beat
        cmp sec_enarp,x
        bcc !+
        inc arp_on
!:      lda beat
        cmp sec_endrum,x
        bcc !+
        inc drums_on
!:
        lda step
        sta cur_step

        // Arp switching on: its own envelope, and one frame of gate off.
        lda arp_on
        beq !+
        lda arp_was
        bne !+
        lda #1
        sta arp_was
        sta arp_hold
        lda sec_arpad,x
        sta $d413
        lda sec_arpsr,x
        sta $d414
        lda sec_wave3,x
        sta $d412
!:
        // --- V1 bass
        lda bass_on
        beq !+
        lda step
        and #$1f
        tay
        lda bass_pattern,y
        tay
        lda sid_freq_lo,y
        sta $d400
        lda sid_freq_hi,y
        sta $d401
        lda sec_wave1,x
        ora #$01
        sta $d404
!:
        // --- V2 lead
        ldy step
        lda lead_pattern,y
        ldy echo_idx                    // remember it for the echo
        sta echo_ring,y
        iny
        tya
        and #$03
        sta echo_idx
        lda echo_ring-1,y               // (y = old idx + 1, so this is the note just stored)
        cmp #NOTE_REST
        bne !note+
        lda #0
        sta lead_on
        lda sec_wave2,x
        sta $d40b
        jmp !lead_done+
!note:  clc
        adc sec_tr,x
        tay
        lda sid_freq_lo,y
        sta lead_flo
        sta $d407
        lda sid_freq_hi,y
        sta lead_fhi
        sta $d408
        asl                             // depth = freq-hi * 2
        sta lead_depth
        lda #0
        sta lead_age
        lda #1
        sta lead_on
        lda sec_wave2,x
        ora #$01
        sta $d40b
!lead_done:

        // --- V3 echo of the lead (pad sections, while the arp is off)
        lda arp_on
        bne !+
        lda sec_flags,x
        and #FL_ECHO
        beq !+
        lda echo_idx                    // two steps back
        sec
        sbc #3
        and #$03
        tay
        lda echo_ring,y
        cmp #NOTE_REST
        beq !+
        clc
        adc #12                         // an octave up: music-box sparkle
        tay
        lda sid_freq_lo,y
        sta $d40e
        lda sid_freq_hi,y
        sta $d40f
        lda sec_wave3,x
        ora #$01
        sta $d412
!:
        // --- Drums
        lda drums_on
        bne !+
        jmp !drums_done+
!:      lda sub
        bne !offbeat+
        // On the beat: kick on even beats, snare on odd, plus the sub layer on V1.
        lda beat
        and #$01
        asl
        asl
        asl                             // 0 = kick, 8 = snare
        jsr hit
        ldy #N_C1
        lda sid_freq_lo,y
        sta $d400
        lda sid_freq_hi,y
        sta $d401
        lda sec_wave1,x                 // gate on: the hard restart already released it
        ora #$01
        sta $d404
        jmp !drums_done+
!offbeat:
        // Roll on the last two beats of a section
        lda sec_flags,x
        and #FL_ROLL
        beq !+
        lda sec_beats,x
        sec
        sbc beat
        cmp #3
        bcs !+
        lda #24
        jsr hit
        jmp !drums_done+
!:      // Fills: the last beat of every chord cycle, the last two of every phrase
        lda sec_flags,x
        and #FL_FILL
        beq !+
        lda step
        and #$7f
        cmp #120
        bcs !roll+
        and #$1f
        cmp #28
        bcc !+
        lda sub
        cmp #2
        bcc !+
!roll:  lda #24
        jsr hit
        jmp !drums_done+
!:      // Hi-hats on the off-beat 8ths
        lda sec_flags,x
        and #FL_HATS
        beq !drums_done+
        lda sub
        cmp #2
        bne !drums_done+
        lda #16
        jsr hit
!drums_done:

        // --- Advance
        inc step
        lda step
        and #$7f
        sta step
        inc sub
        lda sub
        cmp sec_spb,x
        bne !+
        lda #0
        sta sub
        inc beat
!:      rts

// Start drum `A` (row offset 0/8/16/24).
hit:
        sta drum_offset
        lsr
        lsr
        lsr
        tay
        lda drum_len,y
        sta drum_state
        rts

// ---------------------------------------------------------------------------
// Every frame

voice3_frame:
        lda drum_state
        beq !arp+
        // Drum row: phase = len - state
        dec drum_state
        lda drum_offset
        lsr
        lsr
        lsr
        tay
        lda drum_len,y
        clc                             // len - state - 1 = phase 0..len-1
        sbc drum_state
        asl
        clc
        adc drum_offset
        tay
        lda drum_table,y
        sta $d412
        lda drum_table+1,y
        sta $d40f
        lda #0
        sta $d40e
        rts
!arp:   lda arp_on
        beq !done+
        lda arp_hold                    // the retrigger frame: gate stays off
        beq !+
        lda #0
        sta arp_hold
        rts
!:      lda cur_step
        and #$1f
        tay
        lda chord_per_step,y
        asl
        asl
        sta tmp
        ldx sec
        lda frame_lo
        ldy sec_spb,x                   // slow sections step the arp every 4 frames
        cpy #1
        bne !+
        lsr
        lsr
!:      and #$03
        clc
        adc tmp
        tay
        lda arp_notes,y
        tay
        lda sid_freq_lo,y
        sta $d40e
        lda sid_freq_hi,y
        sta $d40f
        lda sec_wave3,x
        ora #$01
        sta $d412
!done:  rts

// Delayed vibrato on the lead: +-2 * depth over 8 frames.
lead_vibrato:
        lda lead_on
        beq !done+
        lda lead_age
        cmp #VIB_DELAY
        bcs !+
        inc lead_age
!done:  rts
!:      lda frame_lo
        and #$07
        tax
        lda lead_depth
        ldy vib_mul,x
        bne !+
        lda #0
        jmp !add+
!:      cpy #2
        bne !add+
        asl
!add:   sta tmp
        lda vib_neg,x
        bne !sub+
        clc
        lda lead_flo
        adc tmp
        sta $d407
        lda lead_fhi
        adc #0
        sta $d408
        rts
!sub:   sec
        lda lead_flo
        sbc tmp
        sta $d407
        lda lead_fhi
        sbc #0
        sta $d408
        rts

// Pulse-width sweeps: bass slow and thin, lead wide, arp shimmer.
.macro Pwm(v, speed, minHi, maxHi) {
        lda pw_dir+v
        bne down
        clc
        lda pw_lo+v
        adc #speed
        sta pw_lo+v
        lda pw_hi+v
        adc #0
        sta pw_hi+v
        cmp #maxHi
        bcc out
        lda #1
        sta pw_dir+v
        jmp out
down:   sec
        lda pw_lo+v
        sbc #speed
        sta pw_lo+v
        lda pw_hi+v
        sbc #0
        sta pw_hi+v
        cmp #minHi
        bcs out
        lda #0
        sta pw_dir+v
out:    lda pw_lo+v
        sta $d402 + v * 7
        lda pw_hi+v
        sta $d403 + v * 7
}
pwm_all:
        Pwm(0, $0c, $02, $07)
        Pwm(1, $20, $03, $0b)
        Pwm(2, $18, $04, $0b)
        rts

filter_frame:
        ldx sec
        lda sec_cutmode,x
        beq !done+
        cmp #CUT_RAMP
        bne !lfo+
        clc
        lda cut_lo
        adc sec_delta_lo,x
        sta cut_lo
        lda cut_hi
        adc sec_delta_hi,x
        sta cut_hi
        sta $d416
!done:  rts
!lfo:   lda frame_lo                    // sine index = frame >> lfoShift (16-bit)
        sta tmp
        lda frame_hi
        ldy sec_lfoshift,x
        beq !idx+
!:      lsr
        ror tmp
        dey
        bne !-
!idx:   ldy tmp
        lda sine,y
        ldy sec_cutshift,x
        beq !add+
!:      lsr
        dey
        bne !-
!add:   clc
        adc sec_cuta,x
        bcc !+
        lda #$ff
!:      sta $d416
        rts

volume_frame:
        ldx sec
        lda sec_volmode,x
        bne !+
        lda #$0f
        jmp !set+
!:      cmp #VOL_FADEIN
        bne !out+
        lda elapsed_hi
        bne !full+
        lda elapsed_lo
        lsr
        lsr
        lsr
        lsr
        jmp !set+
!out:   ldy #2                          // VOL_FADEOUT: left >> 2
        cmp #VOL_FADEOUT
        beq !+
        ldy #3                          // VOL_SLOWOUT: left >> 3
!:      lda left_hi
        bne !full+
        lda left_lo
!:      lsr
        dey
        bne !-
        cmp #$10
        bcc !set+
!full:  lda #$0f
!set:   ora sec_mode,x
        sta $d418
        rts
