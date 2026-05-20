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

        // Memory: code + tables at $80-$84 (5 pages: plasma wave, raster bars, etc.)
        .byte 'P', $80, $84
        // Sprite shape data at $2000-$21FF (8 sprite-letters × 64 bytes
        // for the AI WROTE drop). Must live in VIC bank 0 so VIC sees
        // it via the $80..$87 sprite block pointers.
        .byte 'P', $20, $21
        // Inherit intro's music tables at $10-$12 — we call intro's
        // my_music_play at $119e. Pefchain MUST NOT overwrite these.
        .byte 'I', $10, $12
        // Zero-page: $f4-beat_phase, $f5-filt_cut, $f6-beat_count,
        //            $f7-xphase, $f8-plasma_tgl, $f9-bar_clr_ofs,
        //            $fa-wave_phs, $fb-yphase, $fc-tmp, $fd-y_contrib
        .byte 'Z', $f4, $fd
        // I/O safe (we leave $01 at $35)
        .byte 'S'
        .byte $00
