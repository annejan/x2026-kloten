//==================================================================
// outline-64 — Spindle "screenfill" part (loading screen)
//
// First part loaded from the .d64 by Spindle's boot loader.
// Port of ranzbak's defeest-screenfill: walks a "DEFEEST" string
// over the screen, choosing upper or lower case per cell via a
// rotating bit-mask. After the fill, runs a water-ripple colour
// cycle for ~3 sec — concentric rings expand from screen centre —
// then triggers Spindle's loader (jsr $200) and JMPs into the main
// demo at $0810.
//
// Lives at $c000 — well above main demo's $0810..$5bbc range so the
// screenfill code SURVIVES the `jsr $200` that loads main into RAM.
// Crucial: $4000-$47ff is main's Tables segment; an earlier $4000
// placement got the screenfill code overwritten mid-load and `jmp
// $0810` was replaced by palette bytes → CPU ran into garbage.
//
// Spindle 3.1 conventions:
//   - $01 stays at $35 (CPU sees full RAM)
//   - VIC bank via $dd02 ($3c → bank 0); DON'T touch $dd00
//   - leaves Spindle's resident loader at $0200..$02FF intact, and
//     keeps off zp $f4-$f8 across `jsr $200` calls
//==================================================================

.const VIC_MEM    = $d018
.const VIC_BORDER = $d020
.const VIC_BG     = $d021
.const COLOUR_RAM = $d800

.const MASK    = $fb           // bit-mask scratch
.const CHARCNT = $02           // position within "DEFEEST" (0..6)
.const SCRPOS  = $03           // 0..255 within current char_table page
.const WCNT    = $04           // word counter / mask seed
.const PHASE   = $05           // ripple phase (incremented per frame)
.const HOLDCNT = $06           // remaining ripple frames (script → 0)
.const RADIUS  = $07           // current ring being filled (0..15, 16=done)
.const RFRAME  = $08           // frames elapsed within current ring

// Radial fill pacing: 8 frames per ring × 16 rings ≈ 2.6 s — slow
// enough to read the BASIC text underneath transforming into the
// bloom as the disc expands outward.
.const ANIM_FRAMES_PER_RING = 8

// === Spindle 3.1 effect lifecycle ===
// setup:     called once. Inits VIC, fills screen with DEFEEST pattern,
//            initialises ripple state. Pefchain enables IRQ on return.
// interrupt: per-frame raster IRQ. Runs one tick of the water-ripple +
//            staged fadeout. When HOLDCNT hits 0 the work is over;
//            interrupt becomes a no-op and pefchain's script condition
//            ("06 = 0") triggers transition to main.
// fadeout:   no-op (sec; rts) — transition already triggered by HOLDCNT.

* = $c000 "ScreenFill"
setup:
        // pefchain leaves $01=$35 and CIAs configured for the loader,
        // so we don't sei / write $01 / touch $dc0d / $dd0d.

        // VIC bank 0, screen $0400, lower-case chargen at $1800.
        lda #$3c
        sta $dd02
        lda #%00010111
        sta VIC_MEM

        // Establish VIC state (don't trust the previous effect to have
        // left it sensible): text mode + RSEL, 40-col, sprites off.
        lda #$1b
        sta $d011
        lda #$08
        sta $d016
        lda #$00
        sta $d015

        // Bg → blue so the DEFEEST chars bloom over the BASIC text
        // (which was blue/light-blue), but leave BORDER at BASIC's $0E
        // (light blue). Border stays at the BASIC default through the
        // entire radial-fill phase (~2.5 s) — the interrupt drops it
        // to $06 once RADIUS hits 16 (ripple starts), then to $00 in
        // the existing late-ripple fade. Avoids a jarring border-color
        // snap immediately after RUN.
        lda #$06
        sta VIC_BG

        // Colour RAM → light blue. (Ripple overwrites it during hold.)
        ldx #0
        lda #$0e
!col:   sta COLOUR_RAM+$000,x
        sta COLOUR_RAM+$100,x
        sta COLOUR_RAM+$200,x
        sta COLOUR_RAM+$2e8,x
        inx
        bne !col-

        // Init counters.
        lda #0
        sta WCNT
        sta SCRPOS

loop_outer:
        lda #0
        sta CHARCNT

loop_char:
        // mask = 1 << ((CHARCNT & 7) + 1)
        lda CHARCNT
        and #%00000111
        clc
        adc #1
        tax
        lda #$01
!rol:   asl
        dex
        bne !rol-
        sta MASK

        // upper vs lower decision: (WCNT & mask) ? upper : lower
        lda WCNT
        and MASK
        beq is_lower

        // Upper: emit raw screen code (already upper in screencode_mixed).
        ldx CHARCNT
        lda dtext,x
        jmp emit

is_lower:
        ldx CHARCNT
        lda dtext,x
        cmp #$20                // keep space
        beq emit
        sec
        sbc #$40                // upper → lower in screencode_mixed

emit:
        ldx SCRPOS
chrtab_w:
        sta char_table,x
        inc SCRPOS
        bne !nowrap+
        // SCRPOS wrapped → advance chrtab_w to next page.
        inc chrtab_w+2
        // After 4 pages ($c700-$caff) we're past the cell area — stop.
        // Note the explicit parens: KA evaluates `>char_table + 4` as
        // `>(char_table+4)` which is just $c7 — leaves the wrap-stop
        // comparison permanently unequal and walks setup over all 64K.
        lda chrtab_w+2
        cmp #((>char_table) + 4)
        beq fill_done
!nowrap:

        inc CHARCNT
        lda CHARCNT
        cmp #7                  // "DEFEEST" len
        bne loop_char

        inc WCNT
        jmp loop_outer


//==================================================================
// fill_done — char_table is fully built. We deliberately DO NOT clear
// screen RAM here: whatever BASIC / Spindle's loader left on screen
// (READY., LOAD"*",8,1, SEARCHING, LOADING, RUN, …) stays visible
// underneath the radial fill. The chargen swap to lowercase ($D018
// = $17 above) is itself the "case-sensitive mode" transition — the
// BASIC text re-renders in its lowercase glyphs as the demo begins,
// and the DEFEEST bloom then expands outward over it.
// Init fill + ripple state and arm raster IRQ at vsync.
//==================================================================
fill_done:
        lda #0
        sta RADIUS
        sta RFRAME
        sta PHASE
        lda #150
        sta HOLDCNT
        lda #$ff
        sta $d012                // raster line for IRQ (vsync)
        rts


//==================================================================
// interrupt — fires at raster $ff (vsync). Two phases:
//   1. RADIAL FILL  (RADIUS = 0..15) — every ANIM_FRAMES_PER_RING
//      frames, emit one ring of DEFEEST chars (cells whose dist_table
//      value matches RADIUS). HOLDCNT stays untouched.
//   2. RIPPLE+FADE  (RADIUS >= 16) — original palette cycle + fade.
//      Decrements HOLDCNT each frame; script transitions on HOLDCNT=0.
//==================================================================
interrupt:
        pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta $d019                // ack IRQ

        // ---- phase select ----
        lda RADIUS
        cmp #16
        bcs !do_ripple+

        // ===== RADIAL FILL =====
        inc RFRAME
        lda RFRAME
        cmp #ANIM_FRAMES_PER_RING
        bcs !emit_ring+
        jmp irq_done
!emit_ring:
        lda #0
        sta RFRAME

        // For every cell whose dist_table == RADIUS, copy char_table[c]
        // into screen RAM. 4 × 256 cells, ~10k cy total — fits a frame.
        ldy #0
!p1:    lda dist_table+$000,y
        cmp RADIUS
        bne !nx1+
        lda char_table+$000,y
        sta $0400,y
!nx1:   iny
        bne !p1-
!p2:    lda dist_table+$100,y
        cmp RADIUS
        bne !nx2+
        lda char_table+$100,y
        sta $0500,y
!nx2:   iny
        bne !p2-
!p3:    lda dist_table+$200,y
        cmp RADIUS
        bne !nx3+
        lda char_table+$200,y
        sta $0600,y
!nx3:   iny
        bne !p3-
!p4:    lda dist_table+$300,y
        cmp RADIUS
        bne !nx4+
        lda char_table+$300,y
        sta $0700,y
!nx4:   iny
        bne !p4-

        inc RADIUS
        // On the last ring (RADIUS just became 16) → one-shot transition
        // border from BASIC's light-blue ($0E) to blue ($06). MUST be a
        // one-shot: writing $06 every ripple frame would clobber the
        // $00 snap at HOLDCNT=56 next frame and the border would flicker.
        lda RADIUS
        cmp #16
        bne irq_done_jmp
        lda #$06
        sta VIC_BORDER
irq_done_jmp:
        jmp irq_done

!do_ripple:
        // ===== RIPPLE + FADE =====
        lda HOLDCNT
        beq irq_done

        // current_pal[i] = ripple_palette[(i - PHASE) & 15]
        ldy #0
!bp:    tya
        sec
        sbc PHASE
        and #$0f
        tax
        lda ripple_palette,x
        sta current_pal,y
        iny
        cpy #16
        bne !bp-

        // Splatter rings across all four colour-RAM pages.
        ldy #0
!r1:    ldx dist_table+$000,y
        lda current_pal,x
        sta $d800,y
        iny
        bne !r1-
!r2:    ldx dist_table+$100,y
        lda current_pal,x
        sta $d900,y
        iny
        bne !r2-
!r3:    ldx dist_table+$200,y
        lda current_pal,x
        sta $da00,y
        iny
        bne !r3-
!r4:    ldx dist_table+$300,y
        lda current_pal,x
        sta $db00,y
        iny
        bne !r4-

        // ----- staged fadeout -----
        // Text palette fade: every 8 frames step ripple_palette through
        // a hue-stable fadetab (each path monotonically darker:
        // $01→$0F→$0C→$0B→$00 and $03→$0E→$06→$00). 4 ticks at
        // HOLDCNT 80/72/64/56 walk the palette fully to $00.
        lda HOLDCNT
        cmp #85
        bcs !nofade+
        and #$07
        bne !nofade+
        ldy #15
!fl:    ldx ripple_palette,y
        lda fadetab,x
        sta ripple_palette,y
        dey
        bpl !fl-
!nofade:
        // bg + border snap at HOLDCNT=72 — mid-fade, after the palette
        // has stepped through fadetab once (at HOLDCNT=80) so the rings
        // are already partially dimmed when the bg drops. The remaining
        // fade ticks (at 64, 56) walk the rings the rest of the way to
        // $00 on a black bg, keeping the ripple visible right through
        // to the end. No early bg blink (snapping at 85 used to drop
        // bg to black while rings were still full bright), bg + border
        // drop together so neither lingers behind the other.
        lda HOLDCNT
        cmp #72
        bne !nbg+
        lda #$00
        sta VIC_BG
        sta VIC_BORDER
!nbg:

        inc PHASE
        dec HOLDCNT
irq_done:
        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// fadeout — no-op. The script transition condition ("06 = 0") fires
// when HOLDCNT (= zp $06) hits 0; pefchain then calls fadeout in a
// loop, expecting carry-set when ready. We return immediately.
//==================================================================
fadeout:
        sec
        rts

// Hue-preserving fade-to-black table — only the colours that appear in
// ripple_palette (plus their intermediate steps) walk toward black.
// Paths: $01→$0F→$0C→$0B→$00, $03→$0E→$06→$00, $0E→$06→$00, $06→$00.
fadetab:
        .byte $00, $0f, $00, $0e, $00, $00, $00, $00
        .byte $00, $00, $00, $00, $0b, $00, $06, $0c

// "DEFEEST" as upper-case screencodes in screencode_mixed:
// D=$44 E=$45 F=$46 E=$45 E=$45 S=$53 T=$54
dtext:
        .byte $44, $45, $46, $45, $45, $53, $54


//==================================================================
// Ripple data tables — placed at $c200 so they live well above the
// code and don't conflict with Spindle's $0200 loader or main's
// $0400-$5dxx layout. They're only used BEFORE jsr $200, so they
// don't need to survive the load.
//==================================================================

* = $c200 "RippleDist"
// dist_table[c] = scaled radial distance from screen centre (20,12),
// mapped to 0..15 so it indexes a 16-entry palette without seams.
// 1024 bytes — last 24 are past row 24 and never displayed.
dist_table:
.for (var i = 0; i < 1024; i++) {
    .var y  = floor(i / 40)
    .var x  = i - y * 40
    .var dx = x - 20
    .var dy = y - 12
    .var d  = round(sqrt(dx*dx + dy*dy) * 15 / 23)
    .byte d & $0f
}

* = $c600 "RipplePal"
// Symmetric palette: black → blue → cyan → white → cyan → blue → black.
// As PHASE advances, each ring index rotates through this ramp, so
// the same brightness band appears to expand outward = water wave.
ripple_palette:
        .byte $00, $06, $06, $0e, $0e, $03, $03, $01
        .byte $01, $03, $03, $0e, $0e, $06, $06, $00

current_pal:
        .fill 16, 0

// Reserved for upcoming radial fill animation — precomputed DEFEEST
// per-cell chars. 1024 bytes (only 1000 used) at $c700-$cae7.
* = $c700 "CharTable"
char_table:
        .fill 1024, 0
