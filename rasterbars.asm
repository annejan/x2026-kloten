//==================================================================
// outline-64 — clean: open borders + 4 visible sprites + scroller
//
// No bars. Focus on the sprites being PRESENT (no Y-wraparound
// blink) and the scroll being smooth.
//
// Sprite blink fix: sprites 0,1 disabled at line $f9 and re-enabled
// at line $01. Their Y-wraparound duplicates (at raster Y+256) fall
// between those lines, where SPR_EN says they're off.
//==================================================================

.const SPR_X        = $d000
.const SPR_Y        = $d001
.const SPR_MSB      = $d010
.const VIC_CTRL1    = $d011
.const VIC_RASTER   = $d012
.const SPR_EN       = $d015
.const SPR_YEXP     = $d017
.const VIC_CTRL2    = $d016
.const SPR_MC       = $d01c
.const SPR_XEXP     = $d01d
.const VIC_BORDER   = $d020
.const VIC_BG       = $d021
.const SPR_COL      = $d027

.const SCREEN       = $0400        // text-mode screen (unused in bitmap mode)
.const BMP_SCREEN   = $0c00        // bitmap-mode colour-info screen RAM
.const BITMAP       = $2000        // 8000-byte bitmap data (VIC sees in bank 0)
.const COLOUR_RAM   = $d800
.const SPR_PTRS     = BMP_SCREEN + $3f8   // last 8 bytes of bitmap-mode screen
.const SPR_DATA     = $0a00        // sprite shape block $28 (free area; $1000-$1FFF is chargen ROM from VIC's view!)
.const SPR_BLOCK    = SPR_DATA / 64
.const FONT_BASE    = $4c00        // chargen ROM copy
.const SCROLL_ROW_BMP = BITMAP + 0 * 40 * 8    // bitmap row 0: $2000..$213F
                                                // Above FLD trigger ($43) so it doesn't bounce.


.const BAR_TOP      = $80       // first line of bar zone (after FLD + music)
.const BAR_BOT      = $ec       // first line PAST bar zone (in open bot border)

// Zero-page
.const zp_text_ptr  = $fb
.const zp_smooth    = $fd
.const zp_frame     = $fe
.const zp_tmp       = $f9
.const zp_msb       = $fa
.const zp_intro     = $f8       // intro tick counter (ticks every 2 frames), saturates at $ff

// Intro phase thresholds (in zp_intro ticks; 2 frames per tick @ 50 Hz so 1 tick = 40 ms)
.const T_BARS      = 40          // bars enable (~1.6 sec)
.const T_BALLS     = 120         // balls enable (~4.8 sec)
.const T_SCROLLER  = 200         // scroller enable (~8 sec)

.var logo  = LoadBinary("defeest.kla", BF_KOALA)

BasicUpstart2(start)

.pc = $0810 "Main"
start:
        sei
        lda #$35
        sta $01

        lda #$7f
        sta $dc0d
        sta $dd0d
        bit $dc0d
        bit $dd0d

        jsr copy_chargen
        jsr clear_screen
        jsr init_slide_hide
        jsr init_sprites
        jsr init_bmp_scroll

        jsr my_music_init

        // Intro starts at frame 0.
        lda #0
        sta zp_intro

        // clear the VIC garbage byte
        sta $3fff

        lda #$00
        sta VIC_BORDER          // black border
        lda #logo.getBackgroundColor()
        sta VIC_BG              // bitmap-mode bg (also used by bars/IRQ)

        // Multicolour bitmap mode: D011=$3B (BMM+DEN+RSEL+yscroll=3),
        // D016=$D8 (MCM+CSEL+xscroll=0), D018=$38 (screen at $0C00,
        // bitmap at $2000 within VIC bank 0).
        lda #$3b
        sta VIC_CTRL1
        lda #$d8
        sta VIC_CTRL2
        lda #$38
        sta $d018

        // raster IRQ chain
        lda #<irq_close
        sta $fffe
        lda #>irq_close
        sta $ffff
        lda #$f9
        sta VIC_RASTER
        lda #$01
        sta $d01a
        lda #$ff
        sta $d019

        cli

forever:
        jmp forever


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
        // Intro gate: balls off until T_BALLS. Sprites 0-2 always off
        // here (their low Y wraps and would re-fire); 3-7 conditional.
        lda zp_intro
        cmp #T_BALLS
        bcc !ballsoff_c+
        lda #%11111000          // sprites 3,4,5,6,7 enabled
        bne !setspr_c+
!ballsoff_c:
        lda #0
!setspr_c:
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
        // Sprite enable depends on intro phase.
        lda zp_intro
        cmp #T_BALLS
        bcc !ballsoff+
        lda #%11111111          // all 8 sprites on
        bne !setspr+
!ballsoff:
        lda #0                  // balls off during intro
!setspr:
        sta SPR_EN

        inc zp_frame            // global animation tick (was in do_scroll)

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
        jsr reveal_column        // expose one more bitmap column from the left

        // Update sprite positions FIRST while raster is at line 1..~8.
        // Top sprites start at Y=14, bottom sprites finished previous
        // frame at raster ~282. This window is safe → no tearing.
        jsr move_sprites

        // Chain to irq_fld at line $43. Rows 0 (scroll) and 1 (empty)
        // display normally before FLD kicks in — so the scroll at the
        // top is stable while FLD bounces the logo below.
        lda #<irq_fld
        sta $fffe
        lda #>irq_fld
        sta $ffff
        lda #$43
        sta VIC_RASTER

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// irq_fld — fires at line $43 (after rows 0+1 of bitmap have rendered
// normally). Suppresses badlines so bitmap row 2 repeats N times,
// pushing the logo (rows 8+) down by N pixels. Row 0 (scroll) and
// row 1 (empty) sit above the bounce, fixed at lines $32..$41.
// Then plays SID. Chains to irq_bars at BAR_TOP=$80.
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
        lda bounce_total,x      // total FLD lines K (0..28)
        beq !skip+
        sta zp_tmp              // zp_tmp = K (iteration cap)

        // CYCLE-EXACT FLD. The previous implementation computed yscroll
        // inline (clc/lda/adc/and/ora/sta = 16 cy after wait), which
        // pushed the write to cycle ~20 of the new line — AFTER VIC's
        // badline check at cycle 14. The check therefore saw the
        // PREVIOUS line's yscroll, and at K%8 == 2 boundaries that old
        // value happened to match line%8, firing a spurious badline that
        // restarted the row and bumped the shift by 7 lines.
        //
        // Fix: pre-compute the next yscroll into A while still on the
        // current line, then STA $d011 immediately after the raster
        // tick (cycle ~7-8, well before cycle 14).

        // Wait for line $44.
        lda #$43
!w1:    cmp VIC_RASTER
        beq !w1-

        // First write: yscroll=5 (== line%8+1 at $44).
        lda #$3d                // BMM + DEN + RSEL + yscroll=5
        sta VIC_CTRL1

        ldx #1                  // X = next fl_table index
        cpx zp_tmp
        bcs !done+              // K==1: just the first write, done.

!fld_loop:
        lda fl_table,x          // 4 cy — pre-loaded value
        ldy VIC_RASTER          // 4 cy — sample raster
!w2:    cpy VIC_RASTER          // 4 cy
        beq !w2-                // 2/3 cy — exits at cycle ~4 of new line
        sta VIC_CTRL1           // 4 cy — write at cycle ~8, BEFORE cycle 14
        inx                     // 2 cy
        cpx zp_tmp              // 3 cy
        bne !fld_loop-          // 2/3 cy

!done:
        // DON'T restore yscroll — leaving it at incremented value
        // means next badline fires K lines later than default. That's
        // what gives the pixel-level shift. (HCL pattern.)

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
        lda zp_intro
        cmp #T_BARS
        bcc !barsoff+

        // Self-modify the lda's lo byte so the palette shifts per
        // frame. bar_palette is page-aligned and 512 bytes long (16
        // reps of the 32-entry palette), so any low-byte offset 0..$ff
        // plus y of $40..$cf always lands within the table.
        lda zp_frame
        lsr                     // /2 for slower colour drift
        sta bar_lda+1

        // 21-cy tight loop writing BOTH $d021 (bg) and $d020 (border).
        // Border writes extend bars into the left/right side stripes.
        // 21 cy fits within the 23-cy badline CPU budget.
!loop:  ldy VIC_RASTER          // 4
bar_lda:
        lda bar_palette,y       // 4 (5 if page-cross — rare)
        sta VIC_BG              // 4
        sta VIC_BORDER          // 4
        cpy #BAR_BOT            // 2
        bcc !loop-              // 3

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
        // --- Master volume fade-in: vol = min(intro >> 3, $0f). ---
        // intro ticks at 25 Hz so vol reaches max at intro=$78=120 ticks =
        // ~4.8 sec, lining up with T_BALLS. Cost: 9 cy / frame.
        lda zp_intro              // 3
        lsr                       // 2
        lsr                       // 2
        lsr                       // 2  (now intro >> 3)
        cmp #$10                  // 2
        bcc !volok+               // 3
        lda #$0f                  // (skipped once saturated)
!volok:
        sta $d418                 // 4

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
        bne !done+

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
!done:
        rts

// Multicolour bitmap data — 8000 bytes at $2000.
.pc = BITMAP "Bitmap"
.fill logo.getBitmapSize(), logo.getBitmap(i)

// Bitmap-mode screen RAM ($0C00) holds 2 colour nibbles per cell —
// uniform for our 4-colour logo. We could also do this at runtime
// in clear_screen; doing it at compile time saves startup time.
.pc = $0c00 "BitmapScreenRAM"
.fill 1000, $67

// Page-aligned tables segment — placed past bitmap.
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

// FLD bounce: number of yscroll writes per frame.
// Effective pixel shift for K writes (FLD at line $43 = row 2):
//   K=0:    0
//   K=1..6: 2..7   (the "RC<7" regime)
//   K=7:    0      (phase-wrap discontinuity)
//   K=7..N: K-7    (the "RC=7 idle" regime — RC sticks at 7 so VCBASE
//                   freezes at row 3 and the badline at $44+K cleanly
//                   slides the next row by K-7 pixels)
// Staying in K=7..35 gives a smooth 0..28-pixel bounce, no phase wrap.
// Last FLD line at $44+34=$66, badline at $67, well before BAR_TOP=$80.
.align 256
bounce_total:
        .fill 256, round(21 + 14 * sin(toRadians(i * 360 / 256)))


// Pre-computed $D011 values for cycle-exact FLD. yscroll cycles
// 5,6,7,0,1,2,3,4 — bytes $3d,$3e,$3f,$38,$39,$3a,$3b,$3c — keeping
// BMM+DEN+RSEL bits set ($38) and yscroll bits 0-2 sweeping.
// 36 entries cover K up to 36 (we use K=7..35).
fl_table:
        .byte $3d, $3e, $3f, $38, $39, $3a, $3b, $3c
        .byte $3d, $3e, $3f, $38, $39, $3a, $3b, $3c
        .byte $3d, $3e, $3f, $38, $39, $3a, $3b, $3c
        .byte $3d, $3e, $3f, $38, $39, $3a, $3b, $3c
        .byte $3d, $3e, $3f, $38


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
        // Rows 8-16 of screen RAM: $0C00+8*40=$0D40 .. $0E87 (360 bytes)
        // Rows 8-16 of colour RAM: $D800+8*40=$D940 .. $DA87 (360 bytes)
        lda #0
        ldx #0
!c1:    sta $0d40,x
        sta $d940,x
        inx
        bne !c1-
        ldx #0
!c2:    sta $0e40,x
        sta $da40,x
        inx
        cpx #104          // 360 - 256
        bne !c2-
        rts


//==================================================================
// reveal_column — expose one cell column of bitmap rows 8-16.
// Called every frame; idempotent. zp_intro=K reveals cells 0..K-1.
// Cost: 18 sta abs,X = ~92 cy when revealing, ~10 cy when done.
//==================================================================
reveal_column:
        lda zp_intro
        beq !done+
        cmp #41
        bcs !done+
        sec
        sbc #1
        tax                       // X = column index 0..39

        lda #$67                  // screen RAM nibbles: blue/yellow
        sta $0d40,x               // row 8
        sta $0d68,x               // row 9
        sta $0d90,x               // row 10
        sta $0db8,x               // row 11
        sta $0de0,x               // row 12
        sta $0e08,x               // row 13
        sta $0e30,x               // row 14
        sta $0e58,x               // row 15
        sta $0e80,x               // row 16

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


// Initialize: clear bitmap row 23, load pending from first char's font.
init_bmp_scroll:
        lda #<(scroll_text + 40)
        sta zp_text_ptr
        lda #>(scroll_text + 40)
        sta zp_text_ptr+1
        lda #0
        sta zp_smooth

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


// Per-frame: shift each pixel row of scroll bitmap by 1 bit.
// Even pixel rows (0,2,4,6) shift LEFT  (ROL cell 39→0, pending feeds at right edge).
// Odd pixel rows (1,3,5,7) shift RIGHT (ROR cell 0→39, pending feeds at left edge).
// Visual: zig-zag scroll — top of each char moves right-to-left, next row left-to-right.
update_bmp_scroll:
        ldx #0
!rowloop:
        txa
        and #$01
        bne !row_odd+

        // Even row: ROL chain shifts content LEFT, new bit enters cell 39 bit 0.
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
        lsr pending_row,x
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

        // Increment bit count; every 8 frames advance to next char
        inc zp_smooth
        lda zp_smooth
        cmp #8
        bne !done+
        lda #0
        sta zp_smooth
        inc zp_text_ptr
        bne !nowrap+
        inc zp_text_ptr+1
!nowrap:
        ldy #0
        lda (zp_text_ptr),y
        cmp #$ff
        bne !load+
        lda #<(scroll_text + 40)
        sta zp_text_ptr
        lda #>(scroll_text + 40)
        sta zp_text_ptr+1
!load:
        // Load pending from font of new char
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
!done:
        rts

// Sprite Y for top-border sprites — range 14..30
.align 256
sine_top:
        .fill 256, 14 + round(8 * (1 - cos(toRadians(i * 360 / 256))))

// Sprite Y for display-area sprites — range 60..200
.align 256
sine_mid:
        .fill 256, 60 + round(70 * (1 - cos(toRadians(i * 360 / 256))))

// Sprite Y for bottom-border sprites — range 226..240 (≤ $f4)
.align 256
sine_bot:
        .fill 256, 226 + round(7 * (1 - cos(toRadians(i * 360 / 256))))


// pre-pad with 40 spaces so text scrolls IN from the right
.encoding "screencode_mixed"
scroll_text:
        .text "                                        "
        .text "deFEEST presents a little C64 intro for the OUTLINE 2026 demoparty... "
        .text "Co-written by Anne Jan Brouwer and Claude Opus 4.7 over many cycle-exact hours. "
        .text "On display: open top and bottom borders via the canonical HCL trick, "
        .text "a multicolour bitmap logo that wipe-reveals from the left and then bounces on a flexible-line-distance effect, "
        .text "cylinder-shaded rasterbars with border-wrap stripes in a 21-cycle bad-line loop, "
        .text "eight expanded koorballen sprites swinging on sine paths, "
        .text "a stable bitmap-mode scroller on row zero riding above the bounce, "
        .text "and a hand-written three-voice SID jam that fades in voice by voice during the intro. "
        .text "Greetings to everyone who still codes the breadbin and thanks to the OUTLINE crew. "
        .text "Assembled with KickAssembler, run on VICE x64sc PAL, committed to git while screenshots were piped through MCP. "
        .text "Looping now...                          "
        .byte $ff


sprite_shape:
        .byte %00000001, %11111000, %00000000
        .byte %00000111, %11111110, %00000000
        .byte %00001111, %11111111, %00000000
        .byte %00011111, %11111111, %10000000
        .byte %00111111, %11111111, %11000000
        .byte %00111111, %11111111, %11000000
        .byte %01111111, %11111111, %11100000
        .byte %01111111, %11111111, %11100000
        .byte %11111111, %11111111, %11110000
        .byte %11111111, %11111111, %11110000
        .byte %11111111, %11111111, %11110000
        .byte %11111111, %11111111, %11110000
        .byte %11111111, %11111111, %11110000
        .byte %01111111, %11111111, %11100000
        .byte %01111111, %11111111, %11100000
        .byte %00111111, %11111111, %11000000
        .byte %00111111, %11111111, %11000000
        .byte %00011111, %11111111, %10000000
        .byte %00001111, %11111111, %00000000
        .byte %00000111, %11111110, %00000000
        .byte %00000001, %11111000, %00000000
        .byte 0
