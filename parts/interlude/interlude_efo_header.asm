//==================================================================
// EFO2 header for interlude.pef. Built with -binfile, concatenated
// with interlude.prg → interlude.efo for mkpef.
//==================================================================

.import source "interlude.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"
        .word $0000              // prepare
        .word setup              // setup
        .word interrupt          // interrupt
        .word $0000              // main
        .word fadeout            // fadeout (sec/rts — script transitions on space)
        .word $0000              // cleanup
        .word $0000              // callmusic

        // Memory: code at $80 (single page — interlude is tiny).
        .byte 'P', $80, $80
        // Inherit intro's music tables at $10-$12 — we call intro's
        // my_music_play at $119e. Pefchain MUST NOT overwrite these.
        .byte 'I', $10, $12
        // Zero-page: $f4 (kick phase), $f5 (filter cutoff), $f6 (beat count)
        .byte 'Z', $f4, $f6
        // I/O safe (we leave $01 at $35)
        .byte 'S'
        .byte $00
