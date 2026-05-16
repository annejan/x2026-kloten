//==================================================================
// outline-64 — minimal open-borders + sprites + smooth scroll text
//
//   - HCL polling pattern (codebase64) for open top/bottom borders:
//       wait raster == $f9 → toggle to 24-row mode
//       wait raster wrap past 255 → back to 25-row
//   - 4 fixed sprites positioned to demonstrate the open borders:
//       sprite 0 (white)  Y=$10  TOP BORDER
//       sprite 1 (cyan)   Y=$40  display, top
//       sprite 2 (yellow) Y=$80  display, mid
//       sprite 3 (green)  Y=$f0  BOTTOM BORDER
//   - smooth-scrolling text at row 24:
//       38-col mode ($d016 CSEL=0) so chars slide into hidden
//       4-px border zones at each edge instead of popping
//       wraps around on $ff sentinel
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

.const SCREEN       = $0400
.const COLOUR_RAM   = $d800
.const SPR_PTRS     = $07f8
.const SPR_DATA     = $2000
.const SPR_BLOCK    = SPR_DATA / 64

.const SCROLL_ROW   = 4
.const SCROLL_SCR   = SCREEN + SCROLL_ROW * 40
.const SCROLL_COL   = COLOUR_RAM + SCROLL_ROW * 40

// Zero-page locations — text_ptr MUST be in ZP for (zp),y indirect
.const zp_text_ptr  = $fb               // 2 bytes: $fb, $fc
.const zp_smooth    = $fd
.const zp_frame     = $fe
.const need_update  = $ff               // IRQ → mainloop flag

BasicUpstart2(start)

.pc = $0810 "Main"
start:
        sei
        lda #$35
        sta $01

        // Disable CIA IRQs
        lda #$7f
        sta $dc0d
        sta $dd0d
        bit $dc0d
        bit $dd0d

        jsr clear_screen
        jsr init_sprites
        jsr init_scroll

        // Clear $3fff so open borders don't show garbage
        lda #0
        sta $3fff

        // Border = blue, background = black for clean contrast
        lda #$06
        sta VIC_BORDER
        lda #$00
        sta VIC_BG

        lda VIC_CTRL1
        and #$7f
        ora #$1b                // DEN | RSEL | yscroll=3 (25-row)
        sta VIC_CTRL1

        // 38-col mode, X-scroll=0 — set ONCE, never touch $d016 again.
        // Chars at col 0 / col 39 have their outermost 4 px hidden by
        // the extended side border, so they fade in/out at the edges.
        lda #$00
        sta VIC_CTRL2

        // Install raster IRQ to open the borders (deterministic timing).
        lda #<irq_close
        sta $fffe
        lda #>irq_close
        sta $ffff
        lda #$f9
        sta VIC_RASTER
        lda #$01
        sta $d01a               // enable raster IRQ
        lda #$ff
        sta $d019               // ack

        cli

//------------------------------------------------------------------
// Mainloop draws ONE smooth-gradient rasterbar from line_colors[]
// which is rebuilt each frame in irq_open (sine-positioned).
//------------------------------------------------------------------
.const BAR_ZONE_TOP   = $70             // first scanline of bar zone
.const BAR_ZONE_LEN   = 80              // length of zone
.const BAR_HEIGHT     = 14              // height of the moving bar

forever:
        // wait line $6f
        ldy #BAR_ZONE_TOP - 1
        cpy VIC_RASTER
        bne *-3
        // disable DEN: kills bad-line cycle theft in the bar zone
        lda #$0b
        sta VIC_CTRL1
        // sync to start of bar zone
        ldy #BAR_ZONE_TOP
        cpy VIC_RASTER
        bne *-3

        ldx #0
        jmp bar_loop            // skip the .align padding (which is $00 = BRK)

.align $100                     // ensure bne stays on one page → always 3 cy
bar_loop:                       // 63-cycle iter: every line's sta lands at the same cy
        lda line_colors,x       // 4
        sta VIC_BORDER          // 4
        sta VIC_BG              // 4
        nop                     // 2  (22 NOPs = 44 cy padding)
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        nop                     // 2
        inx                     // 2
        cpx #BAR_ZONE_LEN       // 2
        bne bar_loop            // 3 taken → 63 cy total per iter

        // restore CTRL1 + colours
        lda #$1b
        sta VIC_CTRL1
        lda #$06
        sta VIC_BORDER
        lda #$00
        sta VIC_BG
        jmp forever


//------------------------------------------------------------------
// build_bar — rebuild line_colors each frame with a smooth-
// gradient bar at a sine-driven vertical position.
//------------------------------------------------------------------
//------------------------------------------------------------------
// build_bar — one sine-moving rasterbar with smooth warm gradient.
//------------------------------------------------------------------
build_bar:
        // clear line_colors
        ldx #BAR_ZONE_LEN-1
        lda #0
!clr:   sta line_colors,x
        dex
        bpl !clr-

        // paint bar at sine_bar[frame]
        ldy zp_frame
        lda sine_bar,y
        tax
        ldy #0
!paint: lda bar_palette,y
        sta line_colors,x
        inx
        iny
        cpy #BAR_HEIGHT
        bne !paint-
        rts


bar_palette:
        // brown → red → orange → light red → light grey → yellow → white
        .byte $09,$02,$08,$0a,$0f,$07,$01
        .byte $01,$07,$0f,$0a,$08,$02,$09

.align 256
sine_bar:
        // 0..(BAR_ZONE_LEN - BAR_HEIGHT - 1) = 0..65
        .fill 256, round(32.5 * (1 - cos(toRadians(i * 360 / 256))))

.align 256
line_colors:
        .fill BAR_ZONE_LEN, 0


//==================================================================
// irq_close — fires at $f9, switches to 24-row so the bottom-
// comparator at $fa can't fire. Chains to irq_open at $01.
//==================================================================
irq_close:
        pha
        lda #$ff
        sta $d019
        lda #$13                // explicit value: DEN | yscroll=3, RSEL=0
        sta VIC_CTRL1
        lda #<irq_open
        sta $fffe
        lda #>irq_open
        sta $ffff
        lda #$01
        sta VIC_RASTER
        pla
        rti


//==================================================================
// irq_open — fires at $01 (well past $fa). Switches back to 25-row.
// Does ALL the per-frame work here (scroll + sprite motion) so
// the timing is fully deterministic each frame: no mainloop race
// with the row-4 bad-line at $5b.
//==================================================================
irq_open:
        pha
        txa
        pha
        tya
        pha

        lda #$ff
        sta $d019
        lda #$1b                // 25-row + yscroll=3 + DEN
        sta VIC_CTRL1

        // All scroll + sprite work happens here, well before line $5b.
        jsr build_bar
        jsr do_scroll
        // Write $d016 AFTER do_scroll has updated smooth so we get
        // the canonical 1x1 sub-pixel scroll sequence 6,5,4,3,2,1,0,7,...
        lda zp_smooth
        sta VIC_CTRL2
        jsr move_sprites

        lda #<irq_close
        sta $fffe
        lda #>irq_close
        sta $ffff
        lda #$f9
        sta VIC_RASTER

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// move_sprites — bounce each sprite around the screen via sine.
//  - sprite 0: bounces in TOP border (Y 0..30 + X sine)
//  - sprite 1: in display
//  - sprite 2: in display
//  - sprite 3: bounces in BOTTOM border (Y 226..246 + X sine)
//==================================================================
move_sprites:
        // sprite 0 — top border ball
        lda zp_frame
        clc
        adc #0                  // phase 0
        tay
        lda sine_x,y
        sta SPR_X+0
        lda zp_frame
        tay
        lda sine_top,y
        sta SPR_Y+0

        // sprite 1
        lda zp_frame
        clc
        adc #64
        tay
        lda sine_x,y
        sta SPR_X+2
        lda zp_frame
        clc
        adc #50
        tay
        lda sine_upper,y
        sta SPR_Y+2

        // sprite 2 — lower display area, just below bar zone
        lda zp_frame
        clc
        adc #128
        tay
        lda sine_x,y
        sta SPR_X+4
        lda zp_frame
        clc
        adc #100
        tay
        lda sine_lower,y
        sta SPR_Y+4

        // sprite 3 — bottom border ball
        lda zp_frame
        clc
        adc #192
        tay
        lda sine_x,y
        sta SPR_X+6
        lda zp_frame
        tay
        lda sine_bot,y
        sta SPR_Y+6

        // No MSB needed if all X values stay < 256
        lda #0
        sta SPR_MSB
        rts


//==================================================================
clear_screen:
        ldx #0
        lda #$20
!loop:  sta SCREEN+$000,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$300,x
        inx
        bne !loop-
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

        lda #SPR_BLOCK
        sta SPR_PTRS+0
        sta SPR_PTRS+1
        sta SPR_PTRS+2
        sta SPR_PTRS+3

        lda #%00001111
        sta SPR_EN
        sta SPR_XEXP                    // X-expand for size
        sta SPR_YEXP                    // Y-expand too → round balls
        lda #0
        sta SPR_MC

        lda #$01
        sta SPR_COL+0
        lda #$03
        sta SPR_COL+1
        lda #$07
        sta SPR_COL+2
        lda #$05
        sta SPR_COL+3

        lda #50
        sta SPR_X+0
        lda #130
        sta SPR_X+2
        lda #200
        sta SPR_X+4
        lda #270-256
        sta SPR_X+6
        lda #%00001000
        sta SPR_MSB

        lda #$10
        sta SPR_Y+0             // top border
        lda #$40
        sta SPR_Y+2             // top of display
        lda #$80
        sta SPR_Y+4             // mid display
        lda #$f0
        sta SPR_Y+6             // bottom border (≤ $f7)
        rts


//==================================================================
// init_scroll — pre-fill SCROLL_ROW with the first 40 chars of the
// scroll message; reset text_ptr; colour the row cyan.
//==================================================================
init_scroll:
        ldx #0
!fill:  lda scroll_text,x
        sta SCROLL_SCR,x
        inx
        cpx #40
        bne !fill-

        lda #<(scroll_text + 40)
        sta zp_text_ptr
        lda #>(scroll_text + 40)
        sta zp_text_ptr+1

        lda #7
        sta zp_smooth
        lda #0
        sta zp_frame

        ldx #0
!col:   lda #$03                // cyan
        sta SCROLL_COL,x
        inx
        cpx #40
        bne !col-
        rts


//==================================================================
// do_scroll — runs once per frame:
//   - decrement smooth, write to $d016 (with CSEL=0 → 38-col mode
//     so chars slide into hidden border instead of popping)
//   - on wrap: shift chars left, pull next char from scroll_text,
//     wrap around on $ff sentinel
//==================================================================
do_scroll:
        // bump frame counter for sprite motion
        inc zp_frame

        // $d016 already written by IRQ this frame — just advance smooth
        dec zp_smooth
        bpl !done+

        lda #7
        sta zp_smooth

        ldx #0
!shift: lda SCROLL_SCR + 1, x
        sta SCROLL_SCR, x
        inx
        cpx #39
        bne !shift-

        ldy #0
!next:  lda (zp_text_ptr),y     // (zp),Y indirect — ZP only
        cmp #$ff                // sentinel → wrap text_ptr to start
        bne !place+
        lda #<scroll_text
        sta zp_text_ptr
        lda #>scroll_text
        sta zp_text_ptr+1
        jmp !next-
!place: sta SCROLL_SCR + 39
        inc zp_text_ptr
        bne !done+
        inc zp_text_ptr+1
!done:  rts


//==================================================================
// Data
//==================================================================

// Sprite-X sine: range 30..230 (avoids the right-MSB-needed zone)
.align 256
sine_x:
        .fill 256, 30 + round(100 * (1 + sin(toRadians(i * 360 / 256))))

// Top-border Y sine: range 0..30 (sprite stays fully in top border zone)
.align 256
sine_top:
        .fill 256, 0 + round(15 * (1 - cos(toRadians(i * 360 / 256))))

// Upper-display Y sine: range 35..70 (between top border and bar zone)
.align 256
sine_upper:
        .fill 256, 35 + round(17 * (1 - cos(toRadians(i * 360 / 256))))

// Lower-display Y sine: range 192..222 (between bar zone and bottom border)
.align 256
sine_lower:
        .fill 256, 192 + round(15 * (1 - cos(toRadians(i * 360 / 256))))

// Bottom-border Y sine: range 226..246 (stays below display, ≤ $f7)
.align 256
sine_bot:
        .fill 256, 226 + round(10 * (1 - cos(toRadians(i * 360 / 256))))

// pre-pad with 40 spaces so text scrolls IN from the right edge
.encoding "screencode_upper"
scroll_text:
        .text "                                        "
        .text "HELLO FROM OUTLINE 64! "
        .text "THIS IS A MINIMAL OPEN-BORDER DEMO WITH FOUR SPRITES AND A SMOOTH-SCROLLING MESSAGE AT THE BOTTOM. "
        .text "THE TOP/BOTTOM BORDERS ARE OPENED USING THE CANONICAL HCL POLLING TRICK FROM CODEBASE64. "
        .text "THIS WHITE BALL AT THE TOP LIVES IN THE OPENED TOP BORDER, AND THE GREEN BALL DOWN BELOW LIVES IN THE OPENED BOTTOM BORDER. "
        .text "THIS TEXT WILL SCROLL ENDLESSLY, WRAPPING AROUND WHEN IT REACHES THE END. "
        .text "GREETINGS TO ALL THE DEMOSCENERS, AND HAPPY HACKING ON YOUR FAVOURITE 6510! "
        .text "                                        "
        .byte $ff


//==================================================================
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
