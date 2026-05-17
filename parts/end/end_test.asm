//==================================================================
// end_test.asm — standalone test harness for parts/end/end.asm.
//
// Adds a BASIC stub at $0801 so VICE can autostart end.prg without
// going through screenfill + main + outro. Use for fast iteration
// on the credit roll. NOT included in the demo build.
//
// Build + run from repo root:
//   ( cd parts/end && java -jar ../../kickass/KickAss.jar end_test.asm )
//   pkill -f x64sc; /usr/bin/x64sc -autostart parts/end/end_test.prg &
//
// Or: ./tools/test-end.sh
//==================================================================

.pc = $0801 "BasicStub"
        BasicUpstart2($3800)

.import source "end.asm"
