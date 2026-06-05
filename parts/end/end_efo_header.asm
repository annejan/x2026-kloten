//==================================================================
// EFO2 header for end.pef. Built as a raw binary (KA -binfile),
// then concatenated with end.prg to produce end.efo for mkpef.
//
// `setup` and `interrupt` symbols come from end.sym, which KA
// emits when end.asm is built.
//==================================================================

.import source "end.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"             // magic
        .word $0000              // prepare
        .word setup              // setup
        .word interrupt          // interrupt
        .word $0000              // main
        .word $0000              // fadeout
        .word $0000              // cleanup
        .word $0000              // callmusic (end has its own player)

        // memory pages: font $30-$37, code+data+decrunch-launcher $38-$57,
        // exomizer-crunched friet stash $58-$79
        .byte 'P', $30, $79
        // zero-page: $f3..$fc (mu_frame, mu_step, yscroll, text_row,
        // frame, tmp, fade, wrap_pending)
        .byte 'Z', $f3, $fc
        // interrupt is I/O safe (we leave $01 at $35)
        .byte 'S'
        .byte $00                // end of tags
