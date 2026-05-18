//==================================================================
// EFO2 header for screenfill.pef. Built with -binfile, concatenated
// with screenfill.prg → screenfill.efo for mkpef.
//==================================================================

.import source "screenfill.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"
        .word prepare            // restore BASIC colors during the leading-blank load gap
        .word setup              // setup
        .word interrupt          // interrupt
        .word $0000              // main
        .word fadeout            // fadeout
        .word $0000              // cleanup
        .word $0000              // callmusic

        // Pages: code at $c000-$c1, dist_table $c2-$c5, palette $c6,
        //        char_table $c7-$ca (reserved for radial fill anim).
        .byte 'P', $c0, $ca
        // Pages we WRITE during setup but don't keep "owning" — screen
        // RAM $04-$07. Declaring as 'P' would block pefchain from
        // pre-loading main's $04 chunk during screenfill; we accept a
        // small load pause at the transition instead by listing them.
        .byte 'P', $04, $07
        // Zero-page: $02..$08 (CHARCNT, SCRPOS, WCNT, PHASE, HOLDCNT,
        //                      RADIUS, RFRAME) + $fb (MASK)
        .byte 'Z', $02, $08
        .byte 'Z', $fb, $fb
        // I/O safe
        .byte 'S'
        .byte $00
