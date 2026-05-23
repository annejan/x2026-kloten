# Intro architecture — outline-64

Living document for the intro part. Captures the current IRQ chain,
the music architecture, cycle budgets, and the design rationale
behind each choice. Update this as the design evolves over the
2-week sprint.

## IRQ chain layout

PAL 50 Hz, 312 raster lines × 63 cy = **19,656 cy/frame**.

```
   $F9 ──irq_close──> $01 ──irq_open──> $59 ──irq_fld_pre──> $5B ──irq_fld──> $80
                                                                          │
   irq_close <─── $F9 ──irq_fld_bottom@$C3+K ────── irq_bars ──────────────┘
```

| Stage | Window | Lines | Cycles | Work |
|-------|--------|-------|--------|------|
| `irq_close@$F9` → `irq_open@$01` | bottom border + vblank | 64 | 4032 | `update_bmp_scroll` (~2400), `update_scroll_colors` (~150), `update_fade_text` (~280), my_music_step (~10..210), counters, vector |
| `irq_open@$01` → `irq_fld_pre@$59` | top border + rows 0..4 | 88 | 5544 | counters, fade-in bg ramp, reveal_column, move_sprites, my_music_critical (~85), vector |
| `irq_fld_pre@$59` → `irq_fld@$5B` | 2-line trampoline | 2 | 126 | self-mod register save, pre-compute K, vector swap, `tsx + cli + 40× nop` |
| `irq_fld@$5B` → `irq_bars@$80` | top FLD + slack | 37 | 2331 | stall delay (39 cy), top FLD K writes (raster-locked = K × 63 cy, K≤20), vector |
| `irq_bars@$80` → `irq_fld_bottom@$C3+K` | bars + handover | 67..95 | 4222..5985 | tight bar palette loop `$80..$BE`, vector with self-modified raster |
| `irq_fld_bottom@$C3+K` → `irq_close@$F9` | bottom FLD + tail | 22..54 | 1386..3402 | bottom FLD (K_max-K) writes (raster-locked), 40-cy latch pad, vector |

K_max = **20** (range 0..20). yscroll lands at 0 after K_max writes
(`(5+19) & 7 == 0`), clean. Peak `dK = 10 × (1080/256)·π/180 =
0.74` K-units per frame so the sine plateaus at K = same value
for 2-3 frames at its extrema — visible as mild "block-jump"
twitching at peak/trough. Was tried at K_max=28 with the stable
raster in place; logo still tore top AND bottom because per-line
mid-sprite DMA on FLD lines (sine_mid Y≥90 displays into the FLD
zone $5C..$5C+K) drifts the in-loop `cmp $d012` polling exit by
enough cy to break the spurious-badline pattern on a few lines
per frame. Stable raster fixed only the entry cycle, not in-loop
DMA. Path to K_max=28: sprite-free FLD lines (raise sine_mid
Y_min above $77 or raster-toggle SPR_EN off across the FLD zone).

## Stable raster (Mäkelä / JackAsser double-IRQ)

`irq_fld_pre@$59` is the cycle-UNSTABLE entry: jittered IRQ latency
(7–13 cy depending on the interrupted instruction) doesn't matter
because all it does is set up the trigger for `irq_fld@$5B` and then
`tsx + cli + 40× nop`. The NOP run is the alignment window — the
next IRQ fires somewhere inside it with **0–1 cy jitter** (NOPs are
2-cy instructions, so the worst case is being interrupted between
NOP boundaries).

`irq_fld@$5B`'s first instruction is `txs` which restores SP to the
value pre saved with `tsx`, discarding pre's own IRQ frame. The
final `rti` then pops the *original* return (the pefchain idle
loop) — pre's path is skipped entirely.

Why this matters:

- Without it, `irq_open`'s variable load plus per-line sprite DMA on
  `$5B`/`$5C` shifted the FLD loop's first write cycle by enough cy
  to break VIC's spurious-badline trigger at K = 28, causing logo-
  top sawtooth tearing. K ≤ 20 was the only stable choice without
  stable raster, but its peak dK = 0.74 produced "plateau" twitching.
- With it, the FLD loop enters at a deterministic cycle of `$5B`
  every frame, so the per-line yscroll writes land in the same
  cy 23–25 window every frame. K = 28 holds the spurious-badline
  pattern across all frames including step-boundary music + peak
  sprite DMA.

Pattern lifted directly from `/tmp/ranzbak/Raster.asm`
(`rasirq1 → rasirq2`) — same form as the codebase64 pages:
`making_stable_raster_routines`, `double_irq`,
`stable_timing_-_jackasser`.

Register save uses self-modification (`sta fld_a_save+1`) instead
of `pha` — the IRQ entry only stacks PC+flags, so the `txs` in
`irq_fld` discards a clean 3-byte IRQ frame. A `pha` trio in pre
would push 3 extra bytes that `txs` would mis-account for.

## Music architecture

### Why we split

`my_music_play` originally bundled three classes of work:

1. **Per-frame critical** — master volume, V3 arpeggio, V3 gate.
   Tiny (~85 cy), must run every frame.
2. **Step-boundary** — V1 bass, V2 lead, V3 drum trigger.
   Fires every `STEP_FRAMES` (8 frames at the current tempo).
   Heavy (~200 cy) when it fires, near-zero otherwise.
3. **Drum tick** — per-frame V3 override (noise + pitch sweep)
   while `drum_state > 0`.

Monolithic execution meant irq_open had a worst-case load on
step-boundary frames. When that frame coincided with all sprites
visible (= maximum sprite DMA) and reveal/move_sprites/counters
all running, irq_open overran past the `irq_fld@$43` trigger.
The FLD chain's spurious-badline pattern depends on the first
write landing before cy 14 of `$44`, and a late IRQ entry breaks
the chain for the first K writes → partial stretch → fade-text
"pulled up" and SID register writes arrive at inconsistent raster
positions across frames (audible as music glitch).

### What we split into

```
my_music_critical         (called by intro irq_open, every frame)
   vol fade   ──>   V3 arp   ──>   V3 gate   ──>   drum tick
                                                       │
                                                       ▼
                                            V3 noise+pitch override
                                            if drum_state > 0
   ~85 cy peak, constant per frame.

my_music_step             (called by intro irq_close, every frame)
   inc mu_frame
   if mu_frame == STEP_FRAMES:
       inc mu_step
       V1 bass note + V2 lead note + V3 drum trigger
   ~10 cy idle, ~210 cy on step-boundary frames.

my_music_play             (at $119e, called by inheritor parts)
   jsr my_music_critical  ──>   jmp my_music_step
   Dispatcher. Byte-for-byte identical to the old monolith.
```

Inheritor parts (`interlude`, `hush`, `greets`, `coda`) call
`INTRO_MUSIC_PLAY = $119e` once per frame and get the monolithic
behaviour unchanged. The `.pc = $119e "MusicDispatch"` anchor in
`intro.asm` keeps that address stable across future reorderings of
the music segment.

### One-frame timing shift

In the monolith, V1/V2 step-triggers and the next V3 arp write all
happened in the same call. In the split:

- frame N `irq_close` (raster `$F9`): step boundary fires →
  V1/V2 notes triggered, drum_state armed, mu_step incremented.
- frame N+1 `irq_open` (raster `$01`): critical runs → V3 arp
  reads the new mu_step.

Both events still happen within the same 20 ms frame transition,
so the audible alignment is identical. The drum override
continues uninterrupted because drum_tick runs inside critical
(after the V3 arp/gate writes) — so V3's last write per frame
is the noise+pitch override whenever drum is active.

### References

- **Codebase64 — SID programming**
  `https://codebase.c64.org/doku.php?id=base:sid_programming`
  Player-structure ideas. The critical-vs-step split is the
  standard "per-frame light work + step-boundary heavy work"
  pattern from the SID programming guide.

- **Codebase64 — Interrupts**
  `https://codebase.c64.org/doku.php?id=base:interrupts`
  IRQ chain design patterns. Our 5-IRQ chain follows the
  "raster-driven state machine" pattern, with each IRQ
  switching `$FFFE/$FFFF` to the next handler before `RTI`.

## FLD architecture

### Symmetric FLD (Jesder/ranzbak pattern)

Total FLD writes per frame = `K_max = 36` (constant). Top FLD does
K writes (= row 1 stretched K times); bottom FLD does (K_max - K)
writes (= row 18 stretched K_max-K times). Net effect: rows 19+
land at the same raster position every frame regardless of K, so
fade-text at row 19 stays nailed at raster `$E3`.

### The first-write fix

The bottom-FLD's first write sets yscroll **explicitly** to
`(5+K) % 8`, not "current+1". For K >= 1 the two coincide (top FLD
left yscroll at `(4+K)%8`, so +1 → `(5+K)%8`); but for K=0 top FLD
didn't run, yscroll was still 3, and the old "+1" produced 4 —
which doesn't match `$C5`'s line%8=5, so no spurious badline fires
on the first line, total stretch is K_max-1 instead of K_max, and
the fade-text wobbles by 1 raster on K=0 frames. Explicit
(5+K)%8 covers all K.

### The latch_final_bitmap_line pad

An 8-iteration `dex/bne` (~40 cy) sits between the bottom FLD loop
and the chain to irq_close. It gives VIC's state machine one quiet
line to settle the last spurious badline's VC/VCBASE before the
chain transitions to natural display. Without it, the post-FLD
raster alignment was K-dependent — visible as fade-text wobble.
Borrowed from ranzbak's `defeest-fld/badline.asm`.

### Trigger move ($3B → $43 → $5B + pre)

The top-FLD trigger has moved twice. Originally at `$3B` (row 1's
natural badline), it gave irq_open only 58 lines = 3654 cy and
overran on heavy frames. Moved to `$43` (row 2): 66 lines /
4158 cy. Then to `$5B` (row 5): 88 lines / 5544 cy of irq_open
slack, plus an extra 2-line trampoline ($59 → $5B) for the
double-IRQ stable-raster wrapper.

Net effect: rows 0..4 (`$33..$5A`) all display normally — the
scroller at row 0 and the fade-band text at row 4 sit ABOVE the
bouncing logo at fixed Y. Row 5 (`$5B..$5B+K`) is the FLD-frozen
row (empty bg). Logo at row 8 still bounces `$73+K`.

### BAR_BOT margin

`BAR_BOT = $BE` (= bars zone `$80..$BD`) leaves 5 lines = ~315 cy
between bars-exit and the earliest `irq_fld_bottom` trigger at
`$C3`. Earlier `BAR_BOT = $C2` had only ~1 line of margin and
sometimes missed the trigger on K=0 frames (bars cleanup +
vector setup pushed the `sta VIC_RASTER` past `$C3`, so the IRQ
never fired this frame → no bottom FLD → full top-FLD shift
dragged the fade-text up with the logo).

## Sprite priority

`$D01B = $07` — top sprites (0..2) BEHIND bitmap, mid + bot
sprites (3..7) IN FRONT. Original design — balls bounce *over*
the logo and *over* the fade-text. With fade-text at row 19
(raster `$E3..$EA = Y=227..234`) and mid sprites' display range
ending at Y=241, mid sprites do occasionally cross the fade-text
on their down-swing. Accepted — it's part of the layered demo
look.

## Wishlist for the 2-week sprint

- **Bigger drum vocabulary** — currently V3 just does the kick
  override. Could add a snare on alternating steps (V3 noise +
  faster decay) and a hat on every step (V3 noise + very short).
  Each costs ~30 cy in my_music_step (= still under budget).
- **Mid sprite priority dynamic** — currently mid sprites IN
  FRONT. We could detect "sprite Y crosses fade-text Y band" and
  flip priority for those sprites' specific Y range via raster
  IRQ. Eliminates the occlusion. ~50 cy in an extra raster IRQ.
- **Second fade-text band below the logo** — bottom FLD ends at
  raster `$E2`, so rows 19..21 ($E3..$FA) are also fixed-Y. We
  could render a second fade-band text in the bottom bitmap and
  alternate phrases between top and bottom for a richer feel.
- **End-of-intro outro polish** — the wipe-out cascade is
  functional but a bit abrupt. Could ease it with K_max ramp-down
  (= K_max decreasing toward 0 over the outro window) so the logo
  smoothly settles rather than stops bouncing mid-arc.
