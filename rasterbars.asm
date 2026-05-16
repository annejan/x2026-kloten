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

.const SCREEN       = $0400
.const COLOUR_RAM   = $d800
.const SPR_PTRS     = $07f8
.const SPR_DATA     = $2000
.const SPR_BLOCK    = SPR_DATA / 64

.const SCROLL_ROW   = 4
.const SCROLL_SCR   = SCREEN + SCROLL_ROW * 40
.const SCROLL_COL   = COLOUR_RAM + SCROLL_ROW * 40

.const BAR_TOP      = $40       // first line of bar zone
.const BAR_BOT      = $d0       // first line PAST bar zone

// Zero-page
.const zp_text_ptr  = $fb
.const zp_smooth    = $fd
.const zp_frame     = $fe
.const zp_tmp       = $f9
.const zp_msb       = $fa

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

        jsr clear_screen
        jsr init_sprites
        jsr init_scroll

        // clear the VIC garbage byte
        lda #0
        sta $3fff

        lda #$06
        sta VIC_BORDER          // blue border
        lda #$00
        sta VIC_BG              // black bg

        lda VIC_CTRL1
        and #$7f
        ora #$1b
        sta VIC_CTRL1

        // 38-col mode for smooth scroll edges (CSEL=0)
        lda #$00
        sta VIC_CTRL2

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
// irq_close — line $f9. Toggle 24-row mode (border opens),
// DISABLE sprites 0+1 (their Y-wraparound duplicates fire between
// here and line $01 of next frame — keep them off).
//==================================================================
irq_close:
        pha
        lda #$ff
        sta $d019
        lda #$13                // 24-row, DEN
        sta VIC_CTRL1
        // Disable sprites 0,1,2 — their low Y causes the comparator
        // to fire again at Y+256 (in the bottom of the rendered area).
        // Sprites 3..7 don't have visible duplicates so stay on.
        lda #%11111000          // sprites 3,4,5,6,7 enabled
        sta SPR_EN
        lda #<irq_open
        sta $fffe
        lda #>irq_open
        sta $ffff
        lda #$01
        sta VIC_RASTER
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
        lda #$1b                // 25-row, DEN
        sta VIC_CTRL1
        lda #%11111111          // all 8 sprites on
        sta SPR_EN

        // Update sprite positions FIRST while raster is at line 1..~8.
        // Top sprites start at Y=14, bottom sprites finished previous
        // frame at raster ~282. This window is safe → no tearing.
        jsr move_sprites

        jsr do_scroll
        lda zp_smooth
        sta VIC_CTRL2           // X-scroll (CSEL=0)
        jsr update_scroll_colors

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

        lda zp_frame
        lsr                     // /2 for slower colour drift
        sta zp_tmp

        // Tight raster-following loop. Read current raster line as
        // the palette index — robust to IRQ entry jitter and won't
        // hang on overshoot (unlike cpx equality polling).
!loop:  lda VIC_RASTER
        cmp #BAR_BOT
        bcs !done+
        clc
        adc zp_tmp
        and #$1f
        tay
        lda bar_palette,y
        sta VIC_BG
        jmp !loop-

!done:  lda #$00
        sta VIC_BG              // restore bg to black

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


bar_palette:
        // 32-entry smooth rainbow gradient (each colour repeated)
        .byte $06,$06,$0e,$0e,$03,$03,$0d,$0d
        .byte $07,$07,$01,$01,$07,$07,$0d,$0d
        .byte $03,$03,$0e,$0e,$06,$06,$04,$04
        .byte $02,$02,$04,$04,$06,$06,$0e,$0e


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
// update_scroll_colors — rainbow effect. Each cell at row 4 gets
// rainbow[(col + frame>>1) & $0f]. frame>>1 → smoother flow.
//==================================================================
update_scroll_colors:
        lda zp_frame
        lsr                     // /2 so the rainbow flows at half speed
        sta zp_tmp
        ldy #39
!loop:  tya
        clc
        adc zp_tmp
        and #$0f
        tax
        lda rainbow_palette,x
        sta SCROLL_COL,y
        dey
        bpl !loop-
        rts

rainbow_palette:
        // 16-entry smooth-ish C64 rainbow
        .byte $02,$08,$08,$07,$07,$0d,$05,$0d
        .byte $03,$03,$0e,$0e,$06,$04,$0a,$02


//==================================================================
do_scroll:
        inc zp_frame
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
!next:  lda (zp_text_ptr),y
        cmp #$ff
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

// Sprite X sine — 9-bit values 24..344 (full content width!).
// We need MSB so use TWO tables: low byte + MSB flag.
.align 256
sine_x_lo:
        .fill 256, (24 + round(160 * (1 + sin(toRadians(i * 360 / 256))))) & $ff

.align 256
sine_x_hi:
        .fill 256, ((24 + round(160 * (1 + sin(toRadians(i * 360 / 256))))) >> 8) & 1

// 8 X-phase offsets so sprites swing at different positions
sprite_xphase: .byte 0, 32, 64, 96, 128, 160, 192, 224
// 8 Y-phase offsets — also distinct
sprite_yphase: .byte 0, 80, 160, 40, 120, 200, 56, 184

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
.encoding "screencode_upper"
scroll_text:
        .text "                                        "
        .text "HELLO FROM OUTLINE 64! "
        .text "THIS IS A MINIMAL OPEN-BORDER DEMO WITH FOUR SPRITES AND A SMOOTH-SCROLLING MESSAGE. "
        .text "THE TOP/BOTTOM BORDERS ARE OPENED USING THE CANONICAL HCL POLLING TRICK FROM CODEBASE64. "
        .text "TWO WHITE/CYAN BALLS LIVE IN THE OPENED TOP BORDER, AND TWO YELLOW/GREEN BALLS DOWN BELOW IN THE OPENED BOTTOM BORDER. "
        .text "                                        "
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
