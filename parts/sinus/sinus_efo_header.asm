//==================================================================
// EFO2 header for sinus.pef.
//==================================================================

.import source "sinus.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"
        .word $0000              // prepare
        .word setup              // setup
        .word interrupt          // interrupt
        .word $0000              // main
        .word fadeout            // fadeout
        .word $0000              // cleanup
        .word $0000              // callmusic

        // Code + tables span $0800-$0DFF (6 pages):
        //   code + setup    @ $0800-$09xx
        //   sine_tab        @ $0A00 (.align 256)
        //   col_tab         @ $0B00 (.align 256)
        //   bg_tab          @ $0C00 (.align 256)
        //   narrative text  @ $0Cxx (story fragments, ~100 bytes)
        //   stripe palette  @ $0Dxx (col-RAM address tables + row colours)
        //   driver          @ $0Dxx (Spindle-appended)
        .byte 'P', $08, $0D
        // Inherit intro's music tables
        .byte 'I', $10, $12
        // Zero-page: $f6-timer/transition, $f7-tmp, $fb-line, $fc-frame.
        // We MUST avoid $f9/$fa — intro's my_music_play clobbers them every
        // call as its own zp_tmp/zp_msb, so any counter stored there gets
        // overwritten on each frame's JSR INTRO_MUSIC_PLAY.
        .byte 'Z', $f6, $fc
        // I/O safe
        .byte 'S'
        .byte $00
