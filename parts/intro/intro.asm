//==================================================================
// outline-64 — Outline 2026 demo, part 2 (main)
//
// Layout (top to bottom):
//   open top border       lines $00..$32  (HCL trick)
//   bitmap row 0 scroller lines $33..$3A  (cycles left / right / zig-zag
//                                          via $fe sentinels in scroll_text)
//   FLD stretch zone      lines $3B..$3B+K  (K = bounce_total[frame])
//   logo wipe-reveal      rows 8..16, sliding down by K px
//   rainbow rasterbars    lines $80..$EB  (behind logo, with sides)
//   open bottom border    lines $EC..$FF  (HCL trick)
//
// IRQ chain: irq_close@$F9 → irq_open@$01 → irq_fld@$3B
//          → irq_bars@$80 → irq_close@$F9.
//
// Sprite blink fix: balls 0..2 disabled in irq_close (line $F9) so
// their Y+256 wrap duplicates between $F9 and next-frame $01 don't
// re-fire. Re-enabled in irq_open via the per-frame calc_active_count
// mask (3..7 take the same cascade gating).
//
// Intro cascade: zp_intro ticks at 25 Hz and gates each element on at
// its T_* threshold; balls spawn one-at-a-time at T_BALLS + N*8 ticks.
// Outro cascade: zp_outro arms when scroll_text hits $ff and unwinds
// the same elements in reverse, ending with `jsr $200 / jmp $3800` to
// transition to part 3 (the credit roll).
//==================================================================

.const SPR_X        = $d000
.const SPR_Y        = $d001
.const SPR_MSB      = $d010
.const VIC_CTRL1    = $d011
.const VIC_RASTER   = $d012
.const SPR_EN       = $d015
.const SPR_FORE     = $d01b     // sprite-foreground priority; set bit = sprite BEHIND foreground pixels
.const SPR_YEXP     = $d017
.const VIC_CTRL2    = $d016
.const SPR_MC       = $d01c
.const SPR_XEXP     = $d01d
.const VIC_BORDER   = $d020
.const VIC_BG       = $d021
.const SPR_COL      = $d027

.const SCREEN       = $0400        // text-mode screen (unused in bitmap mode)
.const BMP_SCREEN   = $0400        // bitmap-mode colour-info screen RAM.
                                   // Spindle 3.1's resident loader lives at
                                   // $0200-$02FF + buffer page $0300-$03FF, so
                                   // anywhere from $0400 up is fair game.
.const BITMAP       = $2000        // 8000-byte bitmap data (VIC sees in bank 0)
.const COLOUR_RAM   = $d800
.const SPR_PTRS     = BMP_SCREEN + $3f8   // last 8 bytes of bitmap-mode screen ($07f8)
.const SPR_DATA     = $0b00        // sprite shape block $2c. Free area above
                                   // screen RAM ($07e8) and below the chargen
                                   // ROM mirror ($1000-$1FFF in VIC view!)
.const SPR_BLOCK    = SPR_DATA / 64
.const FONT_BASE    = $4c00        // chargen ROM copy
.const SCROLL_ROW_BMP = BITMAP + 0 * 40 * 8    // bitmap row 0: $2000..$213F
                                                // Row 0 displays at $33..$3A — before FLD trigger ($3B) → no bounce.


.const BAR_TOP      = $80       // first line of bar zone (after FLD + music)
.const BAR_BOT      = $ec       // first line PAST bar zone (in open bot border)

// Zero-page
.const zp_text_ptr  = $fb
.const zp_smooth    = $fd
.const zp_frame     = $fe
.const zp_tmp       = $f9
.const zp_msb       = $fa
.const zp_intro     = $f8       // intro tick counter (ticks every 2 frames), saturates at $ff
.const zp_scroll_mode = $f7     // 0=left scroll, 1=right scroll, 2=zig-zag (alternating rows)
.const zp_outro     = $f6       // outro tick counter; 0 = inactive, otherwise ticks every 2 frames once $ff in scroll_text triggers the ending
.const zp_active_count = $f5    // cached number of active ball sprites (0..8); computed once per frame in irq_open, read by irq_close

// Intro phase thresholds (in zp_intro ticks; 2 frames per tick @ 50 Hz so 1 tick = 40 ms)
// New order: balls → bars → logo → scroller.
.const T_BALLS     = 40          // balls enable    (~1.6 sec)
.const T_BARS      = 120         // bars enable     (~4.8 sec)
.const T_LOGO      = 200         // logo wipe begins (~8 sec) — reveal_column uses (zp_intro - T_LOGO)
.const T_SCROLLER  = 240         // scroller enable (~9.6 sec)
// Drums fire only once zp_outro is non-zero (intro's outro animation
// has armed, ~20 s into intro). Continues through interlude + greets
// via my_music_play residency. End uses its own music_play, no drums.
// V3 drums are table-driven (Geir Tjelta / Jeroen Tel "Macro Player"
// pattern + Prince-of-Persia SFX routine). Per-frame command rows
// write ctrl ($d412) + freq-hi ($d40f) — ADSR stays at the arp's
// $00/$F0 (peak sustain, no decay) so the kick rides at full volume
// and the post-kick arp pulse just swaps waveform without retrigger.
//
// TWO drums in one table: kick (rows 0..3) and snare (rows 4..7),
// 2 bytes per row, picked via drum_offset (0 or 8) set at trigger.
// Pattern: kick on every 8th step, snare on every 8th+4 step → K-S-K-S
// on the quarter-note grid (125 BPM).
//
//   KICK  — pure triangle pitch-slam from $10 → $02 (250 → 30 Hz).
//           No noise transient — the kick lives entirely in the sub
//           and low-bass bands. V1's bass-bleed at N_C1 reinforces.
//   SNARE — low-noise transient ($20 ≈ 500 Hz) + triangle body in
//           the 50–250 Hz range. The rattly noise gives the snap
//           that distinguishes it from the kick.
//
// Both share the same DRUM_LEN window, same gate-on-throughout, same
// V1 bass-bleed retrigger. The character difference is the V3 voicing.
.const DRUM_LEN = 4

// Outro phase thresholds (in zp_outro ticks; mirror intro pacing).
// Outro starts when scroll_text hits $ff. Scroller stops immediately (gate
// on zp_outro != 0); subsequent thresholds remove the other elements in the
// REVERSE order they appeared in the intro.
.const T_OUTRO_LOGO  = 40        // logo un-wipe begins (~1.6 sec after $ff)
.const T_OUTRO_BARS  = 120       // bars switch off     (~4.8 sec)
.const T_OUTRO_BALLS = 176       // sprite 7 despawns first; one ball every 8 ticks → sprite 0 off at 176+56=232
.const T_OUTRO_DONE  = 240       // outro complete, main chains to end part (~9.6 sec)

.var logo  = LoadBinary("defeest.kla", BF_KOALA)

// === Spindle 3.1 effect lifecycle ===
// setup:     called once by pefchain with interrupts disabled. Inits
//            VIC + sprites + scroll + music. Returns; pefchain enables
//            IRQ which then fires `interrupt` (= irq_close, first in
//            our raster chain).
// interrupt: irq_close, which chains to irq_open / irq_fld / irq_bars
//            via the standard $fffe write-and-rti pattern.
// (no main, fadeout, cleanup — script transition condition watches
// zp_outro for T_OUTRO_DONE = $f0 to know main has wrapped its outro.)
.pc = $0810 "Main"
setup:
        // pefchain disables CIA1 interrupts in early-setup, leaves $01
        // at $35, and uses CIA2 NMI for the loader. We MUST NOT touch
        // $dc0d/$dd0d here or we'll either re-enable interrupts we
        // don't want or break pefchain's loader.

        jsr copy_chargen
        jsr clear_screen
        jsr init_slide_hide
        jsr clear_bitmap                // zero-fill $2000-$3FFF
        jsr copy_logo                  // copy logo rows to rows 8-16
        jsr init_sprites
        jsr init_bmp_scroll

        jsr my_music_init

        // Intro starts at frame 0; outro inactive until scroll hits $ff.
        lda #0
        sta zp_intro
        sta zp_outro
        sta zp_active_count

        // clear the VIC garbage byte
        sta $3fff

        lda #$00
        sta VIC_BORDER          // black border
        sta VIC_BG              // bitmap-mode bg STARTS BLACK — fade-in at irq_open uses zp_intro

        // Multicolour bitmap mode: D011=$3B (BMM+DEN+RSEL+yscroll=3),
        // D016=$D8 (MCM+CSEL+xscroll=0), D018=$18 (screen at $0400,
        // bitmap at $2000 within VIC bank 0).
        lda #$3b
        sta VIC_CTRL1
        lda #$d8
        sta VIC_CTRL2
        lda #$18
        sta $d018

        // Raster IRQ at line $f9 — pefchain installs $fffe from EFO
        // header to point at `interrupt:` (= irq_close), and enables
        // the raster IRQ during early-setup. We just set the line.
        lda #$f9
        sta VIC_RASTER
        rts


//==================================================================
// fadeout — pefchain calls this after the script transition condition
// fires (we use "f6 = f0", i.e. zp_outro == T_OUTRO_DONE). Music tables
// stay resident ($10-$12) and interlude calls my_music_play, so we do
// NOT silence SID here — we want audio to carry across the transition.
//==================================================================
fadeout:
        sec
        rts


//==================================================================
clear_screen:
        // Bitmap-mode screen RAM at $0C00 holds 2 colour nibbles per
        // cell: hi=%01 slot, lo=%10 slot. Our logo encoding uses the
        // same 4-colour set everywhere — fill with $67 (blue + yellow).
        ldx #0
        lda #$67
!loop:  sta BMP_SCREEN+$000,x
        sta BMP_SCREEN+$100,x
        sta BMP_SCREEN+$200,x
        sta BMP_SCREEN+$300,x
        inx
        bne !loop-
        // Colour RAM ($D800) provides the %11 slot — uniform white.
        lda #$01
!loop:  sta COLOUR_RAM+$000,x
        sta COLOUR_RAM+$100,x
        sta COLOUR_RAM+$200,x
        sta COLOUR_RAM+$300,x
        inx
        bne !loop-
        rts


//==================================================================
init_sprites:
        ldx #63
!loop:  lda sprite_shape,x
        sta SPR_DATA,x
        dex
        bpl !loop-

        // All 8 sprite pointers → same shape block
        ldx #7
        lda #SPR_BLOCK
!ptrs:  sta SPR_PTRS,x
        dex
        bpl !ptrs-

        lda #%11111111          // all 8 sprites enabled
        sta SPR_EN
        sta SPR_XEXP            // X-expanded
        sta SPR_YEXP            // Y-expanded → round balls
        lda #0
        sta SPR_MC
        // Top sprites 0,1,2 pass behind the scroller letters: their
        // foreground-priority bit set means the bitmap %01/%10/%11
        // pixels (letter strokes) overdraw the sprite where they meet.
        lda #%00000111
        sta SPR_FORE

        // 8 distinct colours
        lda #$01                // white
        sta SPR_COL+0
        lda #$03                // cyan
        sta SPR_COL+1
        lda #$07                // yellow
        sta SPR_COL+2
        lda #$05                // green
        sta SPR_COL+3
        lda #$0e                // light blue
        sta SPR_COL+4
        lda #$0a                // light red
        sta SPR_COL+5
        lda #$08                // orange
        sta SPR_COL+6
        lda #$04                // purple
        sta SPR_COL+7
        rts


//==================================================================
// irq_close — line $f9. Toggle 24-row mode (border opens),
// DISABLE sprites 0+1 (their Y-wraparound duplicates fire between
// here and line $01 of next frame — keep them off).
//==================================================================
irq_close:
        pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta $d019
        lda #$33                // 24-row, DEN, BMM (open border in bitmap mode)
        sta VIC_CTRL1
        // Sequential ball mask, AND'd with %11111000 to keep sprites
        // 0-2 OFF in the vblank wrap window (Y-wrap fix). Reads
        // zp_active_count cached by the previous irq_open in this frame.
        ldx zp_active_count
        lda spr_count_mask,x
        and #%11111000
        sta SPR_EN
        lda #<irq_open
        sta $fffe
        lda #>irq_open
        sta $ffff
        lda #$01
        sta VIC_RASTER
        // Intro gate: scroller off until T_SCROLLER.
        // jsr update_bmp_scroll is ~2400 cy; in $f9..$01 ~4000-cy window.
        lda zp_intro
        cmp #T_SCROLLER
        bcc !scrolloff+
        jsr update_bmp_scroll
        jsr update_scroll_colors
!scrolloff:
        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// irq_open — line $01. Restore 25-row, RE-ENABLE all sprites,
// do scroll & sprite motion.
//==================================================================
irq_open:
        pha
        txa
        pha
        tya
        pha

        lda #$ff
        sta $d019
        // 25-row + DEN + BMM, yscroll=3 (default). irq_fld will
        // modify yscroll per-line for FLD effect.
        lda #$3b
        sta VIC_CTRL1
        // Sequential ball spawn/despawn: calc_active_count populates
        // zp_active_count based on zp_intro/zp_outro, then we mask.
        jsr calc_active_count
        ldx zp_active_count
        lda spr_count_mask,x
        sta SPR_EN

        inc zp_frame            // global animation tick

        // Intro counter ticks every 2 frames (bit 0 of zp_frame = 0).
        // Saturates at $ff = ~10 sec total intro window.
        lda zp_frame
        and #$01
        bne !intromax+
        lda zp_intro
        cmp #$ff
        beq !intromax+
        inc zp_intro
!intromax:
        // Outro counter — ticks at same 25 Hz once update_bmp_scroll has
        // armed it (zp_outro != 0). Saturates at $ff like zp_intro.
        lda zp_outro
        beq !outromax+
        lda zp_frame
        and #$01
        bne !outromax+
        lda zp_outro
        cmp #$ff
        beq !outromax+
        inc zp_outro
!outromax:
        // Visual fade-in: bg ramps from $00 to logo_bg over first 16 intro ticks.
        // zp_intro ticks at 25 Hz (every 2 frames), so fade takes ~0.64s —
        // completes well before sprites activate at T_BALLS=40.
        lda zp_intro
        cmp #16
        bcs !fade_done+
        tax
        lda fade_bg,x
        sta VIC_BG
!fade_done:
        jsr reveal_column        // expose one more bitmap column from the left

        // Update sprite positions FIRST while raster is at line 1..~8.
        // Top sprites start at Y=14, bottom sprites finished previous
        // frame at raster ~282. This window is safe → no tearing.
        jsr move_sprites

        // Chain to irq_fld at line $3B. Scroller letters get their
        // rainbow colours from per-cell color RAM (updated each frame
        // in irq_close), not from per-scanline $D021 writes.
        lda #<irq_fld
        sta $fffe
        lda #>irq_fld
        sta $ffff
        lda #$3b
        sta VIC_RASTER

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// irq_fld — fires at line $3B (row 1's natural badline). Row 0 has
// already displayed at $33..$3A and the scroller in row 0 is locked
// in place. Canonical HCL FLD pattern: write yscroll=5 before $3C
// cycle 14, then loop "increment yscroll and write" once per line.
// Late-write trick: each iteration's $D011 update lands at cy ~24
// (AFTER VIC's cy-14 check), so the change is seen by the NEXT
// line's cy-14 check, where yscroll now matches line%8 → VIC fires
// a SPURIOUS badline that restarts row 1 with VCBASE pinned. After
// K writes, row 1 has been stretched K times and row 2+ slide down
// by K pixels. Bitmap shifts from $73 (K=0) to $73+K (K=28).
//==================================================================
irq_fld:
        pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta $d019

        ldx zp_frame
        lda bounce_total,x      // K = FLD writes (0..28)
        tax
        beq !skip+

        // Wait for raster to leave $3B (= we're now at $3C).
        lda #$3b
!w1:    cmp VIC_RASTER
        beq !w1-

        // First write at $3C cycle ~11 (BEFORE cycle 14): yscroll=5.
        // $3C%8=4, ys=5 → diff=1 → no badline at $3C.
        lda #$3d                // BMM + DEN + RSEL + yscroll=5
        sta VIC_CTRL1

        dex
        beq !skip+

!fld_loop:
        lda VIC_RASTER
!w2:    cmp VIC_RASTER
        beq !w2-
        // Per-line write at cy ~24 (AFTER cy 14). The PREVIOUS line's
        // yscroll therefore matches THIS line's line%8 at cy 14 → a
        // spurious badline fires, restarting row 2 with VCBASE pinned.
        clc
        lda VIC_CTRL1
        adc #$01
        and #$07
        ora #$38
        sta VIC_CTRL1
        dex
        bne !fld_loop-

!skip:
        jsr my_music_play

        lda #<irq_bars
        sta $fffe
        lda #>irq_bars
        sta $ffff
        lda #BAR_TOP
        sta VIC_RASTER

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// irq_bars — fires at line BAR_TOP. Polls $d012 per line and writes
// $d021 from bar_palette[(line + frame/2) & $1f]. Palette is a smooth
// 32-entry gradient so per-line seams blend visually. The CPU is
// tied up in this loop until line BAR_BOT — no other work scheduled
// during this window. Chains to irq_close at $f9.
//==================================================================
irq_bars:
        pha
        tya
        pha

        lda #$ff
        sta $d019

        // Intro gate: bars off until zp_intro >= T_BARS.
        // Outro gate: bars off again once zp_outro >= T_OUTRO_BARS.
        lda zp_intro
        cmp #T_BARS
        bcc !barsoff+
        lda zp_outro
        cmp #T_OUTRO_BARS
        bcs !barsoff+

        // Self-modify the bar_palette lo bytes so the palette shifts
        // per frame. bar_palette is page-aligned and 512 bytes long
        // (16 reps of the 32-entry palette), so any low-byte offset
        // 0..$ff plus y of $40..$cf always lands within the table.
        // Two `ldx bar_palette,y` instructions in this loop — initial
        // preload + per-iteration preload-next — both need the patch.
        lda zp_frame
        lsr                     // /2 for slower colour drift
        sta bar_lda+1
        sta bar_lda2+1

        // RASTER-LOCKED bar loop. Each line of the bars zone:
        //   1. wait `cpy VIC_RASTER` until raster == Y
        //   2. immediately stx $d021 / stx $d020 (X holds preloaded
        //      palette[Y], so the store happens 4-8 cy after polling
        //      exit, before sprite-DMA cy 0-15 windows are fully done)
        //   3. iny; preload palette[Y+1] into X for next iter
        //
        // Init Y to (current raster + 1) so we wait for the NEXT line
        // transition before the first write — avoids the "we're already
        // past Y, polling hangs a whole frame" trap that broke the
        // first attempt. Cost: one bar line at the top skipped (no
        // bg/border colour written for line Y_init, stays the
        // last-frame's value — basically black since bars zone starts
        // clean). 1 line out of 108 = invisible.
        ldy VIC_RASTER
        iny                     // start at next line transition
bar_lda:
        ldx bar_palette,y       // preload palette for that line
!loop:
!w:     cpy VIC_RASTER          // 4 — wait for raster == y
        bne !w-                 // 3 → poll exit ~cy 5-10 of line y
        stx VIC_BG              // 4 → bg write at cy ~9-14 of line y
        stx VIC_BORDER          // 4 → border at cy ~13-18
        iny                     // 2
bar_lda2:
        ldx bar_palette,y       // 4 (5 page-cross) — preload next
        cpy #BAR_BOT            // 2
        bcc !loop-              // 3 — until past BAR_BOT

        lda #$00
        sta VIC_BG              // restore bg to black
        sta VIC_BORDER          // restore border to black
!barsoff:
        // bg/border are already $00 from previous frame; nothing to do
        // when bars are off besides chaining to irq_close.

        lda #<irq_close
        sta $fffe
        lda #>irq_close
        sta $ffff
        lda #$f9
        sta VIC_RASTER

        pla
        tay
        pla
        rti


// Hand-written 3-voice SID player + pattern data. Hard 8-bit bassline.
.pc = $1000 "Music"

// Note-period table for SID PAL clock. 5 octaves: C-0..B-4 (indices 0..59).
sid_freq_lo:
        .byte $17, $27, $39, $4b, $5f, $74, $8a, $a1, $ba, $d4, $ef, $0c   // C-0..B-0
        .byte $2d, $4f, $73, $97, $be, $e8, $14, $42, $74, $a9, $df, $19   // C-1..B-1
        .byte $5a, $9e, $e7, $35, $7e, $d0, $28, $85, $e8, $52, $bd, $33   // C-2..B-2
        .byte $b4, $3d, $cf, $6a, $fc, $a0, $50, $0a, $d0, $a3, $7d, $66   // C-3..B-3
        .byte $68, $7a, $9e, $d4, $f8, $40, $a0, $14, $a0, $46, $fa, $cc   // C-4..B-4
sid_freq_hi:
        .byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $02   // C-0..B-0
        .byte $02, $02, $02, $02, $02, $02, $03, $03, $03, $03, $03, $04   // C-1..B-1
        .byte $04, $04, $04, $05, $05, $05, $06, $06, $06, $07, $07, $08   // C-2..B-2
        .byte $08, $09, $09, $0a, $0a, $0b, $0c, $0d, $0d, $0e, $0f, $10   // C-3..B-3
        .byte $11, $12, $13, $14, $15, $17, $18, $1a, $1b, $1d, $1e, $20   // C-4..B-4

// Note-number shortcuts (octave * 12 + semitone, with octave 4 included)
.const N_C1 = 12       // ~33 Hz — sub-bass kick layer (V1 bass-bleed)
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


// 32-step pattern at 4 frames/step = ~187 BPM 16ths.
.const NOTE_REST = $ff
.const STEP_FRAMES = 6           // slower pace (was 4) so the mix breathes

// Chord progression (Am - Em - F - G), 8 steps each
//   chord index 0..3 → arp_notes table offset (chord*4)
chord_per_step:
        .byte 0,0,0,0,0,0,0,0    // Am (steps 0..7)
        .byte 3,3,3,3,3,3,3,3    // Em (steps 8..15)
        .byte 1,1,1,1,1,1,1,1    // F  (steps 16..23)
        .byte 2,2,2,2,2,2,2,2    // G  (steps 24..31)

// 4 chords × 4 arp notes (root, 3rd, 5th, octave). Voice 3 cycles every frame.
arp_notes:
        .byte N_A2, N_C3, N_E3, N_A3    // Am: A C E A↑
        .byte N_F2, N_A2, N_C3, N_F3    // F:  F A C F↑
        .byte N_G2, N_B2, N_D3, N_G3    // G:  G B D G↑
        .byte N_E2, N_G2, N_B2, N_E3    // Em: E G B E↑

// Bass: 16th-note pattern with octave jumps every 3rd step. Tracks chord roots.
bass_pattern:
        // Am
        .byte N_A2, N_A2, N_A3, N_A2, N_A2, N_E3, N_A3, N_A2
        // Em
        .byte N_E2, N_E2, N_E3, N_E2, N_E2, N_B2, N_E3, N_E2
        // F
        .byte N_F2, N_F2, N_F3, N_F2, N_F2, N_C3, N_F3, N_F2
        // G
        .byte N_G2, N_G2, N_G3, N_G2, N_G2, N_D3, N_G3, N_G2

// Lead melody — 128 steps = 4 chord cycles = ~10 sec at 4 frames/step.
// Each chord cycle gets a different phrase, so the melody winds without
// looping for ~10 seconds.
lead_pattern:
        // ---- Phrase 1: sparse opening (Am Em F G) ----
        .byte N_A3,NOTE_REST,N_E3,NOTE_REST, N_A3,N_C4,N_E3,NOTE_REST
        .byte N_G3,NOTE_REST,N_B3,NOTE_REST, N_E4,N_G3,N_E3,NOTE_REST
        .byte N_F3,NOTE_REST,N_A3,NOTE_REST, N_F4,N_A3,N_C4,NOTE_REST
        .byte N_G3,NOTE_REST,N_B3,NOTE_REST, N_D4,N_G4,N_F4,N_E4
        // ---- Phrase 2: active 8ths, rising energy ----
        .byte N_A4,N_C4,N_E4,N_A4, N_C4,N_E4,N_C4,N_A3
        .byte N_B3,N_D4,N_G3,N_B3, N_E4,N_G3,N_E3,N_B3
        .byte N_C4,N_A3,N_F3,N_A3, N_F4,N_C4,N_A3,N_F3
        .byte N_D4,N_B3,N_G3,N_B3, N_G4,N_D4,N_B3,N_G3
        // ---- Phrase 3: high climb, arps in the lead too ----
        .byte N_E4,N_A4,N_E4,N_C4, N_A4,N_E4,N_A4,N_E4
        .byte N_B3,N_E4,N_G4,N_B4, N_E4,N_B3,N_E4,N_G4
        .byte N_C4,N_F4,N_A4,NOTE_REST, N_F4,N_C4,N_A3,N_F3
        .byte N_G4,N_B4,N_D4,NOTE_REST, N_B4,N_G4,N_D4,N_B3
        // ---- Phrase 4: descending resolution ----
        .byte N_E4,NOTE_REST,N_C4,NOTE_REST, N_A3,NOTE_REST,NOTE_REST,NOTE_REST
        .byte N_E4,NOTE_REST,N_B3,NOTE_REST, N_G3,NOTE_REST,NOTE_REST,NOTE_REST
        .byte N_F3,NOTE_REST,N_C4,NOTE_REST, N_F3,NOTE_REST,NOTE_REST,NOTE_REST
        .byte N_G3,NOTE_REST,N_D4,NOTE_REST, N_G3,NOTE_REST,NOTE_REST,NOTE_REST


// Per-tune state in RAM (initialized at boot)
mu_step:        .byte 0
mu_frame:       .byte 0


my_music_init:
        // Clear SID
        ldx #$1c
        lda #0
!loop:  sta $d400,x
        dex
        bpl !loop-

        // Voice 1 (bass): pulse wave, kick-like ADSR
        lda #$04           // attack=0, decay=4 (fast)
        sta $d405
        lda #$61           // sustain=6, release=1 (punchy)
        sta $d406
        lda #$00
        sta $d402
        lda #$08           // 12.5% duty
        sta $d403

        // Voice 2 (lead): pulse wave, sharper
        lda #$02           // attack=0, decay=2
        sta $d40c
        lda #$81           // sustain=8, release=1
        sta $d40d
        lda #$00
        sta $d409
        lda #$06           // ~37% duty (rich harmonic)
        sta $d40a

        // Voice 3 (arpeggio): sustained pulse, max volume — pitch cycles per frame
        lda #$00
        sta $d413          // attack=0, decay=0
        lda #$f0           // sustain=F, release=0
        sta $d414
        lda #$00
        sta $d410
        lda #$04
        sta $d411          // 25% duty
        // V3 starts ungated; gate triggered at T_SCROLLER in my_music_play.

        // Master volume
        lda #$0f
        sta $d418

        lda #0
        sta mu_step
        sta mu_frame
        rts


my_music_play:
        // --- Master volume: fade IN over intro tick window only ---
        // vol = min(zp_intro >> 3, $0f) — reaches $0f at intro=120 (~4.8s).
        // We intentionally DO NOT subtract a vol_out fade here: the music
        // needs to carry continuously through intro outro → interlude →
        // greets (interlude / greets call this routine too via my_music_play
        // residency). The "transitioning out" feel during intro's outro
        // is carried by the visual cascade (sprites, bars, logo) and by
        // V1 muting in interlude — not by silencing the SID.
        lda zp_intro
        lsr
        lsr
        lsr
        cmp #$10
        bcc !vin_ok+
        lda #$0f
!vin_ok:
        sta $d418

        // --- V3 arpeggio: change freq every frame ---
        // chord_per_step uses (mu_step & 31)
        lda mu_step
        and #$1f
        tax
        lda chord_per_step,x
        asl
        asl                       // chord_idx * 4
        sta zp_tmp
        lda zp_frame
        and #$03                  // arp index 0..3
        clc
        adc zp_tmp
        tax
        lda arp_notes,x
        tay
        lda sid_freq_lo,y
        sta $d40e
        lda sid_freq_hi,y
        sta $d40f

        // V3 gate: triggered once at T_SCROLLER, idempotently re-written
        // each frame after (write of $41 with gate already on is a no-op).
        lda zp_intro
        cmp #T_SCROLLER
        bcc !v3_skipgate+
        lda #$41                  // pulse + gate on
        sta $d412
!v3_skipgate:

        // --- Step boundary work ---
        inc mu_frame
        lda mu_frame
        cmp #STEP_FRAMES
        beq !is_step+
        jmp !done+                // bne range exceeded since drum block added
!is_step:

        lda #0
        sta mu_frame
        inc mu_step
        lda mu_step
        and #$7f                  // wrap at 128 (lead loops every 128 steps)
        sta mu_step

        // V1 bass — uses (mu_step & 31). Gated by T_BARS.
        and #$1f                  // (preserves mu_step's low 5 bits in A)
        pha
        lda zp_intro
        cmp #T_BARS
        bcc !v1_skip+
        pla
        tax
        lda bass_pattern,x
        cmp #NOTE_REST
        beq !v1_rest+
        tay
        lda sid_freq_lo,y
        sta $d400
        lda sid_freq_hi,y
        sta $d401
        lda #$40
        sta $d404
        lda #$41
        sta $d404
        jmp !v1_done+
!v1_rest:
        lda #$40
        sta $d404
        jmp !v1_done+
!v1_skip:
        pla                       // discard preserved value
!v1_done:

        // V2 lead — uses full mu_step (0..127). Gated by T_BALLS.
        lda zp_intro
        cmp #T_BALLS
        bcc !v2_skip+
        ldx mu_step
        lda lead_pattern,x
        cmp #NOTE_REST
        beq !v2_rest+
        tay
        lda sid_freq_lo,y
        sta $d407
        lda sid_freq_hi,y
        sta $d408
        lda #$40
        sta $d40b
        lda #$41
        sta $d40b
        jmp !v2_done+
!v2_rest:
        lda #$40
        sta $d40b
        jmp !v2_done+
!v2_skip:
!v2_done:
        // --- V3 DRUM trigger (step boundary, every 4th step = ~125 BPM)
        // Only after zp_outro != 0, i.e. once the intro's outro
        // animation has armed (~20 s into intro). Drums then continue
        // through interlude + greets via my_music_play residency. End
        // uses its own music routine — no drums there.
        lda zp_outro
        beq !drum_done+
        lda mu_step
        and #$03
        bne !drum_done+
        // BEAT — arm a new drum window. Pick kick (drum_offset=0) on
        // even quarters and snare (drum_offset=8) on odd quarters →
        // K-S-K-S backbeat. mu_step is at a kick step (& $03 == 0),
        // so bit 2 of mu_step splits even/odd quarters; ASL maps it
        // to a byte-offset into the 16-byte drum_table.
        lda mu_step
        and #$04
        asl                       // 0 or 8
        sta drum_offset
        lda #DRUM_LEN
        sta drum_state
        // V1 BASS-BLEED LAYER — fires on BOTH kick and snare. V1 just
        // wrote its bass note above; we overwrite it with N_C1 (~33 Hz
        // sub-bass) and gate-pulse V1 to retrigger. V1's existing
        // punchy ADSR ($04/$61 = instant attack, fast decay, sustain $6,
        // fast release) shapes the thump naturally. The bass-pattern
        // note at this drum step is sacrificed; bass resumes at the
        // next non-drum step (3 of every 4 steps). Without this layer
        // the kick/snare have no low-end weight — V3 alone competes
        // with the arp + lead voices for ear and reads as thin.
        ldx #N_C1
        lda sid_freq_lo,x
        sta $d400
        lda sid_freq_hi,x
        sta $d401
        lda #$40
        sta $d404                // gate off → triggers release of prior bass note
        lda #$41
        sta $d404                // gate on → fresh attack of sub-bass thump
!drum_done:
!done:
        // --- V3 DRUM tick (table-driven).
        // Each row in drum_table is { ctrl ($d412), freq-hi ($d40f) }.
        // drum_offset (set at trigger) selects which 4-row block to walk:
        //   offset 0 → kick rows (0..3)
        //   offset 8 → snare rows (4..7)
        // ADSR is left at arp's $00/$F0 (set once at init) so V3 stays
        // at peak volume for the whole hit — punch comes from waveform
        // contrast and pitch sweep, not envelope dynamics.
        lda drum_state
        beq !drum_skip+
        dec drum_state

        // phase = (DRUM_LEN-1) - drum_state  →  forward index
        lda #DRUM_LEN-1
        sec
        sbc drum_state
        asl                       // × 2 bytes/row
        clc
        adc drum_offset           // + kick/snare offset
        tay

        lda drum_table,y
        sta $d412                 // ctrl (waveform + gate; gate stays on)
        lda drum_table+1,y
        sta $d40f                 // V3 freq hi
        lda #$00
        sta $d40e                 // V3 freq lo
!drum_skip:
        // Colocate hook: indirect JMP through a 2-byte vector that each
        // part can point at its own lyric/text handler. Default = RTS stub.
        // Because this fires INSIDE my_music_play, the lyric trigger is
        // synchronous with mu_step — zero drift by construction.
        jmp (lyric_vec)

lyric_vec:
        .word lyric_stub
lyric_stub:
        rts


// V3 drum state. drum_state = countdown (0=idle, 1..DRUM_LEN=active).
// drum_offset = 0 for kick rows, 8 for snare rows of drum_table.
// Live in intro's music segment so every part that inherits the
// music ('I', $10, $12) can drive them.
drum_state:
        .byte 0
drum_offset:
        .byte 0

// V3 drum table — kick rows 0..3 (offset 0), snare rows 4..7 (offset 8).
//
//   ctrl:     $81 = noise + gate, $11 = triangle + gate. Gate stays
//             on through the whole hit (and stays on for the post-hit
//             arp $41 write too) — no envelope retrigger.
//   freq-hi:  high byte of V3 freq ($d40f); freq-lo is forced to $00 each
//             frame, so this drives the pitch directly. SID hi-bytes:
//             $80 ≈ 2 kHz, $40 ≈ 1 kHz, $20 ≈ 500 Hz, $10 ≈ 250 Hz,
//             $08 ≈ 125 Hz, $04 ≈ 62 Hz, $02 ≈ 31 Hz (sub-bass).
drum_table:
        // KICK — pure triangle pitch-slam, no noise. Belly only.
        // ctrl  fhi        phase  notes
        .byte $11, $10   //  0 — triangle, ~250 Hz — fast attack
        .byte $11, $04   //  1 — slam down to ~60 Hz
        .byte $11, $02   //  2 — sub-bass body (~30 Hz)
        .byte $11, $02   //  3 — hold sub (V1 layer reinforces ~33 Hz)
        // SNARE — flam: silent frame 0 so the kick hits alone for 20 ms,
        // then noise attack on frame 1 for a wider, more human backbeat.
        // ctrl  fhi        phase  notes
        .byte $00, $00   //  0 — SILENT — kick hits alone (flam offset)
        .byte $81, $20   //  1 — low noise (~500 Hz) — rattle attack
        .byte $11, $10   //  2 — triangle body (~250 Hz)
        .byte $11, $05   //  3 — drop (~80 Hz)

// Compact logo bitmap rows 8-16 — extracted from defeest.kla at build
// time. Stored at $1300 to avoid the runtime-cleared $2000-$3FFF bitmap
// area. Copied into rows 8-16 ($2A00) by copy_logo in setup.
.pc = $1300 "LogoRows"
.import source "logo_rows.asm"

// Page-aligned tables segment.
.pc = $4000 "Tables"

// Page-aligned 512-byte palette = 16 reps of the 32-entry rainbow.
// Self-modified lda base + y(<$d0) always stays inside the table.
bar_palette:
.for (var rep = 0; rep < 16; rep++) {
        // 4 cylinder-shaded bands, 8 lines each. Each band:
        // dark → mid → bright → mid → dark + 2 black gap → next.
        // Blue cylinder
        .byte $00, $06, $0e, $01, $0e, $06, $00, $00
        // Red cylinder
        .byte $00, $02, $0a, $01, $0a, $02, $00, $00
        // Green cylinder
        .byte $00, $05, $0d, $01, $0d, $05, $00, $00
        // Yellow/orange cylinder
        .byte $00, $08, $07, $01, $07, $08, $00, $00
}

// 256-byte rainbow palette for the scroller bg. Cycles through 16
// colours, repeated 16 times so a self-modified low-byte offset
// (zp_frame >> 1) plus y in $33..$3a always lands inside.
.align 256
rainbow_pal:
.for (var rep = 0; rep < 16; rep++) {
        // Smooth gradient: blue → cyan → green → yellow → orange →
        // pink → purple → dark blue, then back. 16 entries.
        .byte $06, $0e, $03, $0d, $05, $07, $08, $0a
        .byte $02, $0a, $04, $0e, $03, $0d, $05, $07
}

// 17-entry fade from $00 to logo's background colour. Indexed by
// zp_intro (0..16) in irq_open — ramp takes ~0.64 s to complete.
fade_bg:
.for (var i = 0; i < 17; i++) {
        .byte floor(logo.getBackgroundColor() * i / 16)
}


//==================================================================
// clear_bitmap — zero-fill $2000-$3FFF (8000 bytes). The full bitmap
// area is no longer pre-loaded from the PRG — cleared at runtime and
// logo rows copied in from the compact logo_rows block.
//==================================================================
clear_bitmap:
        lda #0
        ldx #0
!lp:    sta $2000,x
        sta $2100,x
        sta $2200,x
        sta $2300,x
        sta $2400,x
        sta $2500,x
        sta $2600,x
        sta $2700,x
        sta $2800,x
        sta $2900,x
        sta $2a00,x
        sta $2b00,x
        sta $2c00,x
        sta $2d00,x
        sta $2e00,x
        sta $2f00,x
        sta $3000,x
        sta $3100,x
        sta $3200,x
        sta $3300,x
        sta $3400,x
        sta $3500,x
        sta $3600,x
        sta $3700,x
        sta $3800,x
        sta $3900,x
        sta $3a00,x
        sta $3b00,x
        sta $3c00,x
        sta $3d00,x
        sta $3e00,x
        sta $3f00,x
        inx
        bne !lp-
        rts


//==================================================================
// copy_logo — copy 2880 bytes of pre-extracted logo bitmap rows
// (rows 8-16) into the bitmap at $2A00.
//==================================================================
copy_logo:
        lda #<logo_rows
        sta src+1
        lda #>logo_rows
        sta src+2
        lda #>$2A00
        sta dst+2

        ldx #11                // 11 full pages = 2816 bytes
        ldy #0
!copy:  src: lda $ffff,y
        dst: sta $2A00,y
        iny
        bne !copy-
        inc src+2
        inc dst+2
        dex
        bne !copy-

        // remaining 64 bytes
        ldy #0
!last:  lda logo_rows + 11 * 256,y
        sta $2A00 + 11 * 256,y
        iny
        cpy #64
        bne !last-
        rts


//==================================================================
// move_sprites — 8 balls roaming.
//   sprites 0,1,2: TOP border (sine_top, Y 14..30) — disabled
//                  during VBL to hide Y+256 duplicates
//   sprites 3,4,5: DISPLAY area (sine_mid, Y 60..200) — no wrap
//   sprites 6,7:   BOTTOM border (sine_bot, Y 226..240) — no wrap
// Each sprite gets a different X phase and Y phase via sprite_phase.
//==================================================================
move_sprites:
        lda #0
        sta zp_msb
        ldx #7
!loop:
        // X position low byte
        lda zp_frame
        clc
        adc sprite_xphase,x
        tay
        lda sine_x_lo,y
        sta zp_tmp
        // X MSB bit — OR sprite-specific bit into accumulator if hi=1
        lda sine_x_hi,y
        beq !nomsb+
        lda zp_msb
        ora bit_table,x
        sta zp_msb
!nomsb:
        txa
        asl                     // sprite index × 2 = SPR_X offset
        tay
        lda zp_tmp
        sta SPR_X,y

        // Y position — choose sine table by sprite index
        lda zp_frame
        clc
        adc sprite_yphase,x
        tay
        cpx #3
        bcs !mid_or_bot+
        // sprites 0,1,2 → top
        lda sine_top,y
        jmp !writey+
!mid_or_bot:
        cpx #6
        bcs !bot+
        // sprites 3,4,5 → mid (display)
        lda sine_mid,y
        jmp !writey+
!bot:
        // sprites 6,7 → bot
        lda sine_bot,y
!writey:
        sta zp_tmp
        txa
        asl
        tay
        iny                     // SPR_Y is SPR_X+1
        lda zp_tmp
        sta SPR_X,y             // SPR_X[2N+1] = SPR_Y[N]
        dex
        bpl !loop-

        lda zp_msb
        sta SPR_MSB
        rts

bit_table: .byte 1, 2, 4, 8, 16, 32, 64, 128


//==================================================================
// calc_active_count — compute how many ball sprites should currently be
// visible based on intro/outro tick counters, store in zp_active_count.
// Ball N spawns at zp_intro = T_BALLS + N*8 (intro spawn cascade) and
// despawns at zp_outro = T_OUTRO_BALLS + (7-N)*8 (outro cascade in
// reverse order). Result is a count in 0..8; the caller maps it to a
// bitmask via spr_count_mask.
//==================================================================
calc_active_count:
        // intro_count: how many sprites have been spawned in
        lda zp_intro
        cmp #T_BALLS
        bcs !ic_active+
        lda #0
        beq !ic_done+
!ic_active:
        sec
        sbc #T_BALLS
        lsr
        lsr
        lsr                       // (zp_intro - T_BALLS) >> 3
        clc
        adc #1
        cmp #9
        bcc !ic_ok+
        lda #8                    // saturate at 8
!ic_ok:
!ic_done:
        sta zp_tmp                // intro_count in 0..8

        // outro_count: how many sprites have despawned
        lda zp_outro
        beq !oc_zero+
        cmp #T_OUTRO_BALLS
        bcs !oc_active+
        lda #0
        beq !oc_done+
!oc_active:
        sec
        sbc #T_OUTRO_BALLS
        lsr
        lsr
        lsr
        clc
        adc #1
        cmp #9
        bcc !oc_ok+
        lda #8
!oc_ok:
        jmp !oc_done+
!oc_zero:
        lda #0
!oc_done:
        sta zp_msb                // outro_count in 0..8

        // active = max(0, intro_count - outro_count)
        lda zp_tmp
        sec
        sbc zp_msb
        bcs !ac_ok+
        lda #0
!ac_ok:
        sta zp_active_count
        rts

// active count → SPR_EN mask (sprites 0..active-1 enabled).
spr_count_mask:
        .byte $00, $01, $03, $07, $0f, $1f, $3f, $7f, $ff


//==================================================================
// Data
//==================================================================

// Sprite X sine — 9-bit values 24..344 (full content width!).
// We need MSB so use TWO tables: low byte + MSB flag.
.align 256
sine_x_lo:
        .fill 256, (32 + round(124 * (1 + sin(toRadians(i * 360 / 256))))) & $ff

.align 256
sine_x_hi:
        .fill 256, ((32 + round(124 * (1 + sin(toRadians(i * 360 / 256))))) >> 8) & 1

// 8 X-phase offsets so sprites swing at different positions
sprite_xphase: .byte 0, 32, 64, 96, 128, 160, 192, 224
// 8 Y-phase offsets — also distinct
sprite_yphase: .byte 0, 80, 160, 40, 120, 200, 56, 184

// Anchor HCL FLD bounce: K = number of yscroll writes per frame.
// With the late-write per-line loop, each write causes the NEXT
// line's cy-14 check to fire a spurious badline that restarts row 2.
// Empirical shift function: 0 for K=0, K+1 for K=1..28. Smooth.
// 3× sine frequency → ~1.7s per cycle.
.align 256
bounce_total:
        .fill 256, round(14 + 14 * sin(toRadians(i * 1080 / 256)))


//==================================================================
// Scroll-in-bitmap segment — at $5400 (past Tables + font copy).
// Renders scroll text into bitmap row 23 ($3CC0..$3DDF). Per frame,
// shift row 23 pixels left by 1 bit; every 8 frames advance text and
// reload pending byte from font.
//==================================================================
.pc = $5400 "BmpScroll"

// 8 pending bytes (one per pixel row of upcoming char).
pending_row:
        .fill 8, 0

// Block-3 reverse-load (mode 2 zig-zag): a second pending buffer for
// the odd-row scroll plus a backward-walking source pointer. zp is
// full so text_ptr_odd lives in code RAM and is swapped into
// zp_text_ptr (via the stack) only during the per-char load.
pending_odd:
        .fill 8, 0
text_ptr_odd:
        .word 0

// Mode-2 (zig-zag split) mid-scroll pause: freezes the scroll for
// ~0.6 s when the on-screen content of even and odd rows aligns to
// the SAME source chars — that's the "lines up" moment where the
// zig-zag visually resolves into the same message on both halves.
//
// Pointer math: at char-step K, even shows source[K-40..K-1] in
// cells 0..39; odd shows source[L-K..L-K+39]. Identical iff K-40 =
// L-K → K = (L+40)/2 (= 54 for block 3's L=68). At that K the
// pointer diff (zp_text_ptr - text_ptr_odd) = 2K + 2 - L. For K=54
// and L=68 → diff = 42. SPLIT_MEET_OFFSET ENCODES THE TUNING:
//   42 → both halves perfectly aligned (cell-by-cell same char)
//   0  → pointers just crossed (no overlap yet, looks scrambled)
//   80 → too late, alignment broken by further scrolling
// Tune ±2 (= ±1 char-step) per visual taste.
//
// Armed once per run. State:
//   split_pause_ctr   = remaining freeze frames (0 = scroll active)
//   split_pause_armed = 0 until alignment detected once,
//                       prevents re-triggering if scan wobbles.
.const SPLIT_PAUSE_FRAMES = 120  // ~2.4 s at 50 Hz (tripled from 40 — let the
                                 // "anyone still vibeing the Commodore 64" beat land)
.const SPLIT_MEET_OFFSET  = 40   // pointer-diff threshold (K=54 of 68);
                                 // each ±2 here = ±1 char-step earlier/later
split_pause_ctr:    .byte 0
split_pause_armed:  .byte 0


//==================================================================
// copy_chargen — bank CHARGEN ROM in, copy MIXED-case set ($D800-$DFFF)
// to RAM at FONT_BASE, restore. SEI is on from start.
// Mixed set: a-z at screen codes $01-$1A, A-Z at $41-$5A — matches
// .encoding "screencode_mixed" so "deFEEST" prints correctly.
//==================================================================
copy_chargen:
        lda #$33
        sta $01
        ldx #0
!loop:  lda $d800,x
        sta FONT_BASE+$000,x
        lda $d900,x
        sta FONT_BASE+$100,x
        lda $da00,x
        sta FONT_BASE+$200,x
        lda $db00,x
        sta FONT_BASE+$300,x
        lda $dc00,x
        sta FONT_BASE+$400,x
        lda $dd00,x
        sta FONT_BASE+$500,x
        lda $de00,x
        sta FONT_BASE+$600,x
        lda $df00,x
        sta FONT_BASE+$700,x
        inx
        bne !loop-
        lda #$35
        sta $01
        rts


//==================================================================
// init_slide_hide — zero screen-RAM hi/lo nibbles AND colour RAM for
// bitmap rows 8-16. With $D021 also $00, every pixel slot in those
// rows is black: the logo is bitmap-data-resident but visually gone.
// reveal_column flips cells back to $67/$01 to expose the logo column
// by column from the left.
//==================================================================
init_slide_hide:
        // Rows 8-16 of screen RAM: $0400+8*40=$0540 .. $0687 (360 bytes)
        // Rows 8-16 of colour RAM: $D800+8*40=$D940 .. $DA87 (360 bytes)
        lda #0
        ldx #0
!c1:    sta $0540,x
        sta $d940,x
        inx
        bne !c1-
        ldx #0
!c2:    sta $0640,x
        sta $da40,x
        inx
        cpx #104          // 360 - 256
        bne !c2-
        rts


//==================================================================
// reveal_column — expose one cell column of bitmap rows 8-16.
// Called every frame; idempotent. zp_intro=K reveals cells 0..K-1.
// When outro is active, branches to wipe_out_column which hides
// cells right-to-left, undoing the intro reveal.
//==================================================================
reveal_column:
        lda zp_outro
        bne wipe_out_column

        // Logo wipe starts at zp_intro = T_LOGO and covers 40 columns.
        lda zp_intro
        cmp #T_LOGO
        bcc !done+                // before T_LOGO → no reveal yet
        sec
        sbc #T_LOGO               // 0..N since T_LOGO
        cmp #40
        bcs !done+                // wipe complete after 40 ticks
        tax                       // X = column index 0..39

        lda #$67                  // screen RAM nibbles: blue/yellow
        sta $0540,x               // row 8
        sta $0568,x               // row 9
        sta $0590,x               // row 10
        sta $05b8,x               // row 11
        sta $05e0,x               // row 12
        sta $0608,x               // row 13
        sta $0630,x               // row 14
        sta $0658,x               // row 15
        sta $0680,x               // row 16

        lda #$01                  // colour RAM: white
        sta $d940,x
        sta $d968,x
        sta $d990,x
        sta $d9b8,x
        sta $d9e0,x
        sta $da08,x
        sta $da30,x
        sta $da58,x
        sta $da80,x
!done:
        rts

// wipe_out_column — outro mirror of reveal_column. Walks columns from
// 39 down to 0 (right→left) starting at zp_outro = T_OUTRO_LOGO, clearing
// each cell's screen-RAM nibbles and colour RAM to $00 so the logo
// disappears into the black bg.
wipe_out_column:
        lda zp_outro
        cmp #T_OUTRO_LOGO
        bcc !done+                // before T_OUTRO_LOGO → no hide yet
        sec
        sbc #T_OUTRO_LOGO         // 0..N since T_OUTRO_LOGO
        cmp #40
        bcs !done+                // wipe-out complete after 40 ticks
        sta zp_tmp
        lda #39
        sec
        sbc zp_tmp                // X = 39 - offset (column 39 → 0)
        tax

        lda #$00
        sta $0540,x               // row 8
        sta $0568,x
        sta $0590,x
        sta $05b8,x
        sta $05e0,x
        sta $0608,x
        sta $0630,x
        sta $0658,x
        sta $0680,x               // row 16

        sta $d940,x               // A still $00 from previous sta
        sta $d968,x
        sta $d990,x
        sta $d9b8,x
        sta $d9e0,x
        sta $da08,x
        sta $da30,x
        sta $da58,x
        sta $da80,x
!done:
        rts


// Initialize: clear bitmap row 23, load pending from first char's font.
init_bmp_scroll:
        lda #<(scroll_text + 40)
        sta zp_text_ptr
        lda #>(scroll_text + 40)
        sta zp_text_ptr+1
        lda #0
        sta zp_smooth
        sta zp_scroll_mode      // start in mode 0 (left scroll)
        sta split_pause_ctr     // mode-2 mid-meet pause: idle on entry
        sta split_pause_armed   // and unfired so the cross can trigger

        // Clear 320 bytes of bitmap row 23
        ldx #0
        lda #0
!c1:    sta SCROLL_ROW_BMP+$000,x
        inx
        cpx #$40
        bne !c1-
        ldx #0
!c2:    sta SCROLL_ROW_BMP+$040,x
        inx
        bne !c2-

        // Load pending bytes from first char's font
        ldy #0
        lda (zp_text_ptr),y
        sta zp_tmp
        asl
        asl
        asl
        sta $02
        lda zp_tmp
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc #>FONT_BASE
        sta $03
        ldy #7
!fill:  lda ($02),y
        sta pending_row,y
        dey
        bpl !fill-
        rts


//==================================================================
// update_scroll_colors — write 40 bytes of rainbow into colour RAM
// $D800..$D827 (bitmap row 0). In multicolour bitmap mode the "%11"
// pixel pair takes its colour from colour RAM, so the letter strokes
// in the scroll row pick up a per-cell rainbow gradient. zp_frame
// shifts the gradient horizontally so the rainbow flows under the
// scrolling text.
//   ~12 cy/iter × 40 = ~480 cy. Runs in irq_close window only after
//   T_SCROLLER, alongside update_bmp_scroll.
//==================================================================
update_scroll_colors:
        ldx zp_frame
        ldy #0
!loop:  lda rainbow_pal,x
        and #$0f                // colour RAM uses only low nibble
        sta COLOUR_RAM+0,y      // bitmap row 0 = colour RAM cells 0..39
        inx
        iny
        cpy #40
        bne !loop-
        rts


// Per-frame: shift each pixel row of scroll bitmap by 1 bit.
// zp_scroll_mode picks the per-row direction:
//   0 = LEFT scroll  (all rows ROL) — text scrolls right-to-left, reads
//       forward in source order.
//   1 = RIGHT scroll (all rows ROR) — text scrolls left-to-right. The
//       source still reads forward because advance walks zp_text_ptr
//       BACKWARDS from block2_end-1 down to block2_start, so the last
//       source char is loaded first and ends up leftmost on screen.
//   2 = ZIG-ZAG     (even rows ROL forward via zp_text_ptr, odd rows
//       ROR backward via text_ptr_odd). Both halves read forward —
//       even half streams in from the right, odd half from the left.
//       Source pointers walk independently from the two ends of block 3
//       toward each other.
// Mode advances at $fe sentinel bytes in scroll_text and wraps after mode 2.
// While split_pause_ctr is non-zero, skip the entire frame — both the
// pixel-level ROL/ROR chains AND the char-step advance — so the screen
// freezes mid-zig-zag for SPLIT_PAUSE_FRAMES frames after the pointers
// cross in block 3 (the moment both halves of the line are on screen).
update_bmp_scroll:
        lda split_pause_ctr
        beq !run_scroll+
        dec split_pause_ctr
        rts
!run_scroll:
        ldx #0
!rowloop:
        // Dispatch on scroll mode → ROL/ROR per row.
        lda zp_scroll_mode
        beq !row_left+          // mode 0 → all left
        cmp #1
        bne !row_zigzag+        // not 0 or 1 → zig-zag (mode 2)
        jmp !row_odd+           // mode 1 → all right (jmp: out of branch range)
!row_zigzag:
        txa
        and #$01
        bne !row_odd+           // odd row in zig-zag → ROR
!row_left:
        // ROL chain shifts content LEFT, new bit enters cell 39 bit 0.
        asl pending_row,x
        rol SCROLL_ROW_BMP + 39*8, x
        rol SCROLL_ROW_BMP + 38*8, x
        rol SCROLL_ROW_BMP + 37*8, x
        rol SCROLL_ROW_BMP + 36*8, x
        rol SCROLL_ROW_BMP + 35*8, x
        rol SCROLL_ROW_BMP + 34*8, x
        rol SCROLL_ROW_BMP + 33*8, x
        rol SCROLL_ROW_BMP + 32*8, x
        rol SCROLL_ROW_BMP + 31*8, x
        rol SCROLL_ROW_BMP + 30*8, x
        rol SCROLL_ROW_BMP + 29*8, x
        rol SCROLL_ROW_BMP + 28*8, x
        rol SCROLL_ROW_BMP + 27*8, x
        rol SCROLL_ROW_BMP + 26*8, x
        rol SCROLL_ROW_BMP + 25*8, x
        rol SCROLL_ROW_BMP + 24*8, x
        rol SCROLL_ROW_BMP + 23*8, x
        rol SCROLL_ROW_BMP + 22*8, x
        rol SCROLL_ROW_BMP + 21*8, x
        rol SCROLL_ROW_BMP + 20*8, x
        rol SCROLL_ROW_BMP + 19*8, x
        rol SCROLL_ROW_BMP + 18*8, x
        rol SCROLL_ROW_BMP + 17*8, x
        rol SCROLL_ROW_BMP + 16*8, x
        rol SCROLL_ROW_BMP + 15*8, x
        rol SCROLL_ROW_BMP + 14*8, x
        rol SCROLL_ROW_BMP + 13*8, x
        rol SCROLL_ROW_BMP + 12*8, x
        rol SCROLL_ROW_BMP + 11*8, x
        rol SCROLL_ROW_BMP + 10*8, x
        rol SCROLL_ROW_BMP +  9*8, x
        rol SCROLL_ROW_BMP +  8*8, x
        rol SCROLL_ROW_BMP +  7*8, x
        rol SCROLL_ROW_BMP +  6*8, x
        rol SCROLL_ROW_BMP +  5*8, x
        rol SCROLL_ROW_BMP +  4*8, x
        rol SCROLL_ROW_BMP +  3*8, x
        rol SCROLL_ROW_BMP +  2*8, x
        rol SCROLL_ROW_BMP +  1*8, x
        rol SCROLL_ROW_BMP +  0*8, x
        jmp !row_next+

!row_odd:
        // Odd row: ROR chain shifts content RIGHT, new bit enters cell 0 bit 7.
        // In mode 2 the bit comes from pending_odd (filled from
        // text_ptr_odd's char) so the odd-row strips read forward
        // despite scrolling rightward. Modes 0/1 use pending_row.
        lda zp_scroll_mode
        cmp #2
        beq !row_odd_mode2+
        lsr pending_row,x
        jmp !ror_chain+
!row_odd_mode2:
        lsr pending_odd,x
!ror_chain:
        ror SCROLL_ROW_BMP +  0*8, x
        ror SCROLL_ROW_BMP +  1*8, x
        ror SCROLL_ROW_BMP +  2*8, x
        ror SCROLL_ROW_BMP +  3*8, x
        ror SCROLL_ROW_BMP +  4*8, x
        ror SCROLL_ROW_BMP +  5*8, x
        ror SCROLL_ROW_BMP +  6*8, x
        ror SCROLL_ROW_BMP +  7*8, x
        ror SCROLL_ROW_BMP +  8*8, x
        ror SCROLL_ROW_BMP +  9*8, x
        ror SCROLL_ROW_BMP + 10*8, x
        ror SCROLL_ROW_BMP + 11*8, x
        ror SCROLL_ROW_BMP + 12*8, x
        ror SCROLL_ROW_BMP + 13*8, x
        ror SCROLL_ROW_BMP + 14*8, x
        ror SCROLL_ROW_BMP + 15*8, x
        ror SCROLL_ROW_BMP + 16*8, x
        ror SCROLL_ROW_BMP + 17*8, x
        ror SCROLL_ROW_BMP + 18*8, x
        ror SCROLL_ROW_BMP + 19*8, x
        ror SCROLL_ROW_BMP + 20*8, x
        ror SCROLL_ROW_BMP + 21*8, x
        ror SCROLL_ROW_BMP + 22*8, x
        ror SCROLL_ROW_BMP + 23*8, x
        ror SCROLL_ROW_BMP + 24*8, x
        ror SCROLL_ROW_BMP + 25*8, x
        ror SCROLL_ROW_BMP + 26*8, x
        ror SCROLL_ROW_BMP + 27*8, x
        ror SCROLL_ROW_BMP + 28*8, x
        ror SCROLL_ROW_BMP + 29*8, x
        ror SCROLL_ROW_BMP + 30*8, x
        ror SCROLL_ROW_BMP + 31*8, x
        ror SCROLL_ROW_BMP + 32*8, x
        ror SCROLL_ROW_BMP + 33*8, x
        ror SCROLL_ROW_BMP + 34*8, x
        ror SCROLL_ROW_BMP + 35*8, x
        ror SCROLL_ROW_BMP + 36*8, x
        ror SCROLL_ROW_BMP + 37*8, x
        ror SCROLL_ROW_BMP + 38*8, x
        ror SCROLL_ROW_BMP + 39*8, x

!row_next:
        inx
        cpx #8
        beq !rowloop_done+
        jmp !rowloop-
!rowloop_done:
        // Outro freeze: once zp_outro is armed, keep shifting (so the row
        // drains naturally over ~320 frames) but skip advance + load so we
        // don't walk zp_text_ptr past $ff into sprite_shape garbage.
        lda zp_outro
        beq !no_outro_gate+
        rts
!no_outro_gate:

        // Increment bit count; every 8 frames advance to next char
        inc zp_smooth
        lda zp_smooth
        cmp #8
        beq !advance+
        rts                     // not a step boundary — bail. Inline rts
                                // because the !done: label below is out of
                                // bne branch range from here.
!advance:
        lda #0
        sta zp_smooth
        // Mode 1 walks zp_text_ptr backwards through block 2 so chars
        // sliding rightward off cell 0 spell the source forward.
        lda zp_scroll_mode
        cmp #1
        beq !back+
        inc zp_text_ptr
        bne !nowrap+
        inc zp_text_ptr+1
!nowrap:
        // Mode 2: ALSO decrement text_ptr_odd so the odd-row half of
        // the zig-zag walks backward through block 3. Clamp at
        // block3_start so we don't read the closing $fe of block 2
        // into pending_odd once the odd pointer reaches the start.
        lda zp_scroll_mode
        cmp #2
        bne !skip_odd_dec+
        lda text_ptr_odd
        cmp #<block3_start
        bne !do_odd_dec+
        lda text_ptr_odd+1
        cmp #>block3_start
        beq !skip_odd_dec+
!do_odd_dec:
        lda text_ptr_odd
        bne !no_borrow_o+
        dec text_ptr_odd+1
!no_borrow_o:
        dec text_ptr_odd
!skip_odd_dec:
        // After both mode-2 pointers move, check if (zp_text_ptr -
        // text_ptr_odd) >= SPLIT_MEET_OFFSET. This needs a proper
        // 16-bit SIGNED compare because for the first half of mode 2
        // zp_text_ptr is BELOW text_ptr_odd (they start at opposite
        // ends of block 3 and walk toward each other); an 8-bit
        // unsigned compare on the low byte alone gives a huge
        // wrap-around value pre-cross and false-triggers immediately.
        //
        // Strategy: 16-bit subtract via low-then-high SBC chain. The
        // high-byte SBC result + carry tells us the sign:
        //   bmi → result negative   → still pre-cross, skip
        //   bne → result ≥ +256     → way past, definitely trigger
        //   else (hi byte = 0)      → low byte is the unsigned diff;
        //                              compare to SPLIT_MEET_OFFSET.
        lda zp_scroll_mode
        cmp #2
        bne !no_meet_check+
        lda split_pause_armed
        bne !no_meet_check+
        lda zp_text_ptr
        sec
        sbc text_ptr_odd
        pha                          // save diff low byte
        lda zp_text_ptr+1
        sbc text_ptr_odd+1
        bmi !no_meet_pop+            // signed negative → pre-cross
        bne !meet_pop+               // hi byte > 0 → diff >= 256, past
        pla                          // hi byte = 0: A = diff low
        cmp #SPLIT_MEET_OFFSET
        bcc !no_meet_check+
        jmp !meet+
!no_meet_pop:
        pla
        jmp !no_meet_check+
!meet_pop:
        pla
!meet:
        inc split_pause_armed
        lda #SPLIT_PAUSE_FRAMES
        sta split_pause_ctr
!no_meet_check:
        jmp !recheck+
!back:
        // If ptr == block2_start we've just displayed the first source
        // char of the block — jump ptr to the closing $fe so recheck
        // bumps mode 1→2 and we resume forward through block 3.
        lda zp_text_ptr
        cmp #<block2_start
        bne !back_dec+
        lda zp_text_ptr+1
        cmp #>block2_start
        bne !back_dec+
        lda #<block2_end
        sta zp_text_ptr
        lda #>block2_end
        sta zp_text_ptr+1
        jmp !recheck+
!back_dec:
        lda zp_text_ptr
        bne !no_borrow+
        dec zp_text_ptr+1
!no_borrow:
        dec zp_text_ptr
!recheck:
        ldy #0
        lda (zp_text_ptr),y
        cmp #$ff
        bne !chk_fe+
        // End-of-text: trigger outro instead of rewinding. zp_text_ptr
        // stays parked on the $ff byte; the next-frame outro gate above
        // prevents the advance from walking off into sprite_shape data.
        lda #1
        sta zp_outro
        rts
!chk_fe:
        cmp #$fe
        bne !load+
        // Mode-change sentinel: advance past it and bump mode (mod 3).
        inc zp_text_ptr
        bne !nm+
        inc zp_text_ptr+1
!nm:    lda zp_scroll_mode
        clc
        adc #1
        cmp #3
        bcc !nm2+
        lda #0
!nm2:   sta zp_scroll_mode
        // Entering mode 1: jump zp_text_ptr to last TEXT char of block 2 so
        // the backwards advance walks toward block2_start. block2_end
        // is the first byte AFTER the closing $fe sentinel, so
        // (block2_end - 2) is the last text char and (block2_end - 1)
        // is the $fe itself. Pointing at the $fe would make recheck
        // bump straight to mode 2 — silently skipping all of block 2.
        cmp #1
        bne !nm_check2+
        lda #<(block2_end - 2)
        sta zp_text_ptr
        lda #>(block2_end - 2)
        sta zp_text_ptr+1
        jmp !nm_done+
!nm_check2:
        // Entering mode 2: zp_text_ptr keeps the just-incremented
        // forward position (= block3_start) for even rows. Initialise
        // text_ptr_odd to the LAST text char of block 3 so the
        // odd-row backwards walk starts there. pending_odd gets filled
        // by !load on the next call (the existing !nm_done flow falls
        // into !recheck → !load).
        cmp #2
        bne !nm_done+
        lda #<(block3_end - 2)
        sta text_ptr_odd
        lda #>(block3_end - 2)
        sta text_ptr_odd+1
!nm_done:
        jmp !recheck-
!load:
        // Load pending_row from font of new char (used by mode 0 and
        // mode 1, and by mode 2 for even rows).
        ldy #0
        lda (zp_text_ptr),y
        sta zp_tmp
        asl
        asl
        asl
        sta $02
        lda zp_tmp
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc #>FONT_BASE
        sta $03
        ldy #7
!fill:  lda ($02),y
        sta pending_row,y
        dey
        bpl !fill-

        // Mode 2: ALSO load pending_odd from text_ptr_odd. zp is full,
        // so swap text_ptr_odd in via the stack to use indirect-Y
        // addressing, then restore zp_text_ptr. ~40 cycles added per
        // char-boundary load when in mode 2.
        lda zp_scroll_mode
        cmp #2
        bne !done+
        lda zp_text_ptr
        pha
        lda zp_text_ptr+1
        pha
        lda text_ptr_odd
        sta zp_text_ptr
        lda text_ptr_odd+1
        sta zp_text_ptr+1
        ldy #0
        lda (zp_text_ptr),y
        sta zp_tmp
        asl
        asl
        asl
        sta $02
        lda zp_tmp
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc #>FONT_BASE
        sta $03
        ldy #7
!fill_o:lda ($02),y
        sta pending_odd,y
        dey
        bpl !fill_o-
        pla
        sta zp_text_ptr+1
        pla
        sta zp_text_ptr
!done:
        rts

// Sprite Y for top-border sprites — range 16..52. Raised floor from
// 14→16 because Y=14 put the sprite in the top border zone where VIC
// renders inconsistently on some frames → flicker at sine peak.
// With Y-expand the display reaches 16..58, still well into FLD zone.
// Phases 0/80/160 keep the 3 top sprites at different cycle points so
// they don't all bunch into the FLD zone simultaneously.
.align 256
sine_top:
        .fill 256, 16 + round(18 * (1 - cos(toRadians(i * 360 / 256))))

// Sprite Y for display-area sprites — range 90..200.
// Floor 90 keeps mid sprites out of the FLD zone ($3C..$58 max):
// sprite DMA during FLD lines would steal cycles from the per-line
// yscroll writes and drift them past VIC's cycle-14 check.
.align 256
sine_mid:
        .fill 256, 90 + round(55 * (1 - cos(toRadians(i * 360 / 256))))

// Sprite Y for bottom-border sprites — range 226..240 (≤ $f4)
.align 256
sine_bot:
        .fill 256, 226 + round(7 * (1 - cos(toRadians(i * 360 / 256))))


// pre-pad with 40 spaces so text scrolls IN from the right.
// $fe = mode-switch sentinel (left → right → zig-zag → loops).
// $ff = end-of-text (rewind + mode 0).
.encoding "screencode_mixed"
scroll_text:
        .text "                                        "
        // ---- block 1: mode 0 (left scroll, normal) ----
        .text " deFEEST presents Anus and Kloot using codebase.c64.org                       "
        .byte $fe
        // ---- block 2: mode 1 (right scroll) ----
        // update_bmp_scroll walks zp_text_ptr backwards across this
        // block (block2_end-1 → block2_start) so the source reads
        // forward despite chars sliding rightward off cell 0.
block2_start:
        .text "                           Open borders, FLD logo, rainbows, 8-sprite balls, custom SID. "
        .byte $fe
block2_end:
        // ---- block 3: mode 2 (zig-zag split) ----
        // Even rows (left scroll) read zp_text_ptr walking forward
        // from block3_start. Odd rows (right scroll) read text_ptr_odd
        // walking backward from (block3_end - 2). Both halves of the
        // zig-zag read forward — the start of the block streams in
        // from the right while the end streams in from the left, and
        // they converge over the duration of the block.
block3_start:
        .text "  Greetings to anyone still vibeing the Commodore 64                "
        .byte $ff
block3_end:


// X2026 party logo sprite — based on xparty.net/img/x.png
sprite_shape:
        .byte %00000000, %00000000, %01111110   // .................######.
        .byte %01000000, %01000000, %00011100   // .#.......#.........###..
        .byte %01101111, %01100001, %10111011   // .##.####.##....##.###.##
        .byte %11110111, %10110011, %01110110   // ####.####.##..##.###.##.
        .byte %01111011, %11011111, %11101100   // .####.####.########.##..
        .byte %00111101, %11101111, %11011000   // ..####.####.######.##...
        .byte %00011110, %11111111, %10110000   // ...####.#########.##....
        .byte %00001111, %01111111, %01100000   // ....####.#######.##.....
        .byte %00000111, %11111110, %11000000   // .....##########.##......
        .byte %00000011, %11111111, %11000000   // ......############......
        .byte %00000001, %11111111, %01100000   // .......#########.##.....
        .byte %00000001, %11111111, %10110000   // .......##########.##....
        .byte %00000011, %11111111, %11011000   // ......############.##...
        .byte %00000111, %11111111, %11101100   // .....##############.##..
        .byte %00001111, %11111111, %11110110   // ....################.##.
        .byte %00011111, %10011111, %11111011   // ...######..##########.##
        .byte %00111111, %00111111, %11111101   // ..######..############.#
        .byte %01111010, %01110111, %11111110   // .####.#..###.##########.
        .byte %11110100, %11100011, %01111111   // ####.#..###...##.#######
        .byte %01101110, %00000001, %10111111   // .##.###........##.######
        .byte %11011100, %00000000, %11011111   // ##.###..........##.#####
