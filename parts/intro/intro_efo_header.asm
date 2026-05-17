//==================================================================
// EFO2 header for intro.pef. Built with `-binfile`, then concatenated
// with intro.prg to produce intro.efo.
//
// `setup`, `irq_close`, `fadeout` symbols come from intro.sym.
//==================================================================

.import source "intro.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"             // magic
        .word $0000              // prepare
        .word setup              // setup
        .word irq_close          // interrupt (first link in raster chain)
        .word $0000              // intro
        .word fadeout            // fadeout (silences SID, returns C=1)
        .word $0000              // cleanup
        .word $0000              // callmusic (music driven from IRQ chain)

        // Memory pages used by intro:
        //   $04-$09 BitmapScreenRAM ($0400-$09f1)
        //   $0B     Sprite shape
        //   $10-$12 Music
        //   $20-$3F Bitmap
        //   $40-$47 Tables
        //   $4C-$53 Chargen-ROM copy (built at runtime in copy_chargen)
        //   $54-$5B BmpScroll
        .byte 'P', $04, $09
        .byte 'P', $0B, $0B
        .byte 'P', $10, $12
        .byte 'P', $20, $3F
        .byte 'P', $40, $47
        .byte 'P', $4C, $53
        .byte 'P', $54, $5B
        // Zero-page: $f5..$fe
        .byte 'Z', $f5, $fe
        // I/O safe (interrupts leave $01 at $35)
        .byte 'S'
        .byte $00                // end of tags
