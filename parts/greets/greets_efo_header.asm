//==================================================================
// EFO2 header for greets.pef.
//==================================================================

.import source "greets.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"
        .word $0000                // prepare
        .word setup                // setup
        .word interrupt            // interrupt
        .word $0000                // main
        .word fadeout              // fadeout
        .word $0000                // cleanup
        .word $0000                // callmusic

        // Owned pages:
        //   $20-$27 = sprite font shapes (32 glyphs × 64 B = 2 KB)
        //   $80-$86 = code + state + tables + inline font
        .byte 'P', $20, $27
        .byte 'P', $80, $86
        // Inherit intro's music tables ($10-$12)
        .byte 'I', $10, $12
        // Zero-page: $f4-$fa (kick state machine + shadow freq)
        .byte 'Z', $f4, $fa
        // I/O safe
        .byte 'S'
        .byte $00
