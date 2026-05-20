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

        // Code + parallax starfield state/tables + col_tab + sin_tab.
        // Code, tier tables, row lookups and per-star state span
        // $0800-$0DFF (6 pages). col_tab page-aligned at $0E00,
        // sin_tab at $0F00 (drives twin-star orbital motion).
        .byte 'P', $08, $0F
        // Kloot star quad sprite shapes (Stage E — pre-rendered zoom):
        // 4 quadrants × 24 frames × 64 B = 6 KB contiguous at
        // $2000-$37FF. Each 24-frame sequence = 8 zoom (small→full
        // with rotation built in) + 16 steady rotation. Coda walks a
        // single shape counter 0..23, wraps 24→8, so the zoom plays
        // once and the rotation loops afterwards. Sprite payloads MUST
        // avoid $1000-$1FFF (chargen ROM visible to VIC there).
        //
        //   $2000-$25FF  TR  (ptr $80..$97, stride 24 = $18)
        //   $2600-$2BFF  TL  (ptr $98..$AF)
        //   $2C00-$31FF  BL  (ptr $B0..$C7)
        //   $3200-$37FF  BR  (ptr $C8..$DF)
        //
        // $30-$37 overlaps end's claim, but end runs AFTER coda so
        // pefchain just defers that half of end's payload to a post-
        // coda load chunk (~0.5 s gap at the coda → end transition).
        .byte 'P', $20, $37
        // Inherit intro's resident music tables.
        .byte 'I', $10, $12
        // Zero-page: $f6 (timer / transition), $fb (subtick), $fc (frame).
        // MUST avoid $f9/$fa — intro's my_music_play clobbers them every
        // call as its own zp_tmp/zp_msb.
        .byte 'Z', $f6, $fc
        // I/O safe.
        .byte 'S'
        .byte $00
