//==================================================================
// EFO2 header for coda.pef.
//==================================================================

.import source "coda.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"
        .word $0000              // prepare
        .word setup              // setup
        .word interrupt          // interrupt
        .word $0000              // main
        .word fadeout            // fadeout
        .word $0000              // cleanup
        .word $0000              // callmusic

        // Code + col_tab fit in 3 pages: code at $0800-$09xx, col_tab
        // at $0A00 (256 bytes). Reuses the area sinus claimed earlier
        // — by the time coda loads, sinus is long gone.
        .byte 'P', $08, $0B
        // Kloot star quad sprite shapes (Stage B): 4 quadrants × 16
        // frames × 64 bytes = 4 KB contiguous at $2800-$37FF. The
        // sprite payloads MUST avoid $1000-$1FFF — VIC sees chargen ROM
        // there in bank 0, not the RAM the CPU sees. Bases are aligned
        // to multiples of $400 ($A0/$B0/$C0/$D0) so the OR-based
        // pointer cycling in coda's interrupt works.
        //
        //   $2800-$2BFF  TR  (ptr $A0..$AF)
        //   $2C00-$2FFF  TL  (ptr $B0..$BF)
        //   $3000-$33FF  BL  (ptr $C0..$CF)
        //   $3400-$37FF  BR  (ptr $D0..$DF)
        //
        // $30-$37 overlaps end's claim, but end runs AFTER coda so
        // pefchain just defers that half of end's payload to a post-
        // coda load chunk (~0.5 s gap at the coda → end transition).
        .byte 'P', $28, $37
        // Inherit intro's resident music tables.
        .byte 'I', $10, $12
        // Zero-page: $f6 (timer / transition), $fb (subtick), $fc (frame).
        // MUST avoid $f9/$fa — intro's my_music_play clobbers them every
        // call as its own zp_tmp/zp_msb.
        .byte 'Z', $f6, $fc
        // I/O safe.
        .byte 'S'
        .byte $00
