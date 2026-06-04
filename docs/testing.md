# Testing — outline-64

Two layers of automated checks back this demo:

1. **sim6502 unit tests** (`tests/sim6502/`) — fast, deterministic 6502
   assertions on the demo's *pure* routines, run in a flat-RAM simulator.
2. **MCP full-demo smoke test** (`tools/verify_demo.py`) — drives a real VICE
   instance via the VICE-MCP server, watching part transitions + SID health
   (see [`mcp-debugging.md`](./mcp-debugging.md)).

This doc is about layer 1 and the coverage picture across both.

## sim6502 unit tests

We use [sim6502](https://github.com/barryw/sim6502) (Barry Walker's 6502
assembly testing framework) via its Docker image. Tests are written in its
`.6502` DSL: load a part's assembled `.prg` + KickAssembler `.sym`, set
register/memory inputs, `jsr` a routine, assert on the outputs.

```bash
./tests/sim6502/run.sh          # build parts + run every suite
./tests/sim6502/run.sh -t       # with instruction trace
```

`run.sh` (re)assembles each part-under-test to `<part>.prg` + copies its
`.sym`, then runs each `tests/sim6502/*.6502` suite in
`ghcr.io/barryw/sim6502:latest` (repo mounted at `/code`). Exit 0 = all
pass, 1 = failure → CI-friendly. The `.prg`/`.sym` are build artifacts
(gitignored); only the `.6502` sources are tracked.

### Two backends — what goes where

| Backend | Machine | Use for |
|---------|---------|---------|
| `sim` (what `run.sh` uses) | flat 64 KB RAM, no VIC/SID/raster | **pure routines**: deterministic `jsr`/`rts`, output depends only on register+memory inputs, **no `$d012` raster-polling** |
| `vice` | hardware-accurate C64 via VICE-MCP | raster-locked loops, IRQ handlers, anything reading live VIC/SID/CIA |

A routine that *looks* pure but contains a `cpy $d012 / bne` raster wait will
**hang forever** on the flat-RAM backend — it belongs on `vice`. Writing to
`$d0xx` is fine on `sim` (it just lands in RAM).

## Coverage

> Snapshot 2026-06-01, from a per-part classification sweep. The counts are a
> reasonable estimate from static analysis; exact testability is confirmed
> when a routine's test is actually written (e.g. a routine that reads
> `$d41b` needs a seeded value; one that turns out to poll `$d012` moves to
> the `vice` column).

**76 classified routines** across the six parts:
**50 sim-testable** · **11 vice-only** · **15 not-unit** (IRQ-handler entries,
inline relocatable code, data tables).

**Tested today: 25 routines, 172 assertions** (83 test cases in 20 suites).
intro: `calc_active_count`, `reveal_column`, `wipe_out_column`,
`move_sprites`, plus the fill/copy routines `clear_screen`, `clear_bitmap`,
`copy_logo`, `copy_chargen`, `update_scroll_colors`. coda: `kloot_advance`,
`star_field`. end: `push_next_credit_row`, `scroll_rows_up`. interlude:
`fire_propagate`, `write_plasma_row`, the line-A typewriter (`update_line_a` /
`la_pause` / `la_backspace`), and the sprite steppers (`sp_off` / `sp_in` /
`sp_bounce` / `sp_out`). greets: `update_sprite_ptrs`, `copy_font`.
screenfill: `fadeout`. **sim coverage = 50 %** (25 of 50 pure routines),
across all 6 parts.

| Part | sim-testable | vice-only | not-unit | tested |
|------|:---:|:---:|:---:|:---:|
| screenfill | 4 | 0 | 0 | **1** |
| intro | 17 | 0 | 4 | **9** |
| interlude | 15 | 9 | 0 | **9** |
| greets | 4 | 1 | 9 | **2** |
| coda | 4 | 1 | 0 | **2** |
| end | 6 | 0 | 2 | **2** |
| **total** | **50** | **11** | **15** | **25** |

### Sim-testable routines per part (the untested surface)

- **screenfill:** `prepare` `setup` `interrupt`¹ **`fadeout`** ✅
- **intro:** `setup` `fadeout` **`clear_screen`** ✅ `init_sprites` `my_music_init`
  `my_music_play` **`clear_bitmap`** ✅ **`copy_logo`** ✅ **`move_sprites`** ✅
  **`calc_active_count`** ✅ **`copy_chargen`** ✅ `init_slide_hide`
  **`reveal_column`** ✅ **`wipe_out_column`** ✅
  `init_bmp_scroll` **`update_scroll_colors`** ✅ `update_bmp_scroll`
- **interlude:** `setup` `init_sprites` **`write_plasma_row`**² ✅ **`update_line_a`** ✅
  **`la_pause`** ✅ **`la_backspace`** ✅ `update_sprites` **`sp_off`** ✅ **`sp_in`** ✅ **`sp_bounce`** ✅
  **`sp_out`** ✅ `fire_init` **`fire_propagate`**² ✅ `fire_seed` `fadeout`
- **greets:** `setup` `fadeout` **`update_sprite_ptrs`** ✅ **`copy_font`** ✅
- **coda:** `setup` `fadeout` **`kloot_advance`** ✅ **`star_field`** ✅
- **end:** `setup` `reveal_text` **`scroll_rows_up`** ✅
  **`push_next_credit_row`** ✅ `end_music_init` `end_music_play`

¹ `interrupt`/handlers that end in `rti` need `jsr(..., stop_on_address = …)`
rather than `stop_on_rts`. ² `fire_propagate` reads SID/noise (`$d41b`) — seed that byte before
the `jsr`. `write_plasma_row` is deterministic (no hardware reads).

**vice-only** (raster/IRQ — test on the hardware backend): interlude's
`interrupt` `fire_irq` `bar_chain_0..5` `bar_chain_end`, and the `interrupt`
handlers in greets/coda.

### Highest-value tests to add next

(Done — the 25 covered: intro `calc_active_count` `reveal_column`
`wipe_out_column` `move_sprites` `clear_screen` `clear_bitmap` `copy_logo`
`copy_chargen` `update_scroll_colors`; coda `kloot_advance` `star_field`; end
`push_next_credit_row` `scroll_rows_up`; interlude `fire_propagate`
`write_plasma_row` `update_line_a`+`la_pause`+`la_backspace`
`sp_off`+`sp_in`+`sp_bounce`+`sp_out`; greets `update_sprite_ptrs`
`copy_font`; screenfill `fadeout`.)

Half the pure surface is covered, and all the behaviourally-interesting
routines are locked. The remaining 25 are lower-priority:

1. **`setup`/`init_*` routines** (every part's `setup`, plus `init_sprites`,
   `init_bmp_scroll`, `init_slide_hide`, `prepare`, `fadeout` in other parts):
   long sequential register/pointer init. Testable but brittle and low-signal
   — assert only the load-bearing pointer/flag each leaves behind, if at all.
2. **The gnarly state machines (save for last):** intro `my_music_play` +
   `update_bmp_scroll`, end `end_music_play` — SID gating / 16-bit signed
   pointer compares + mode transitions; brittle to assert, test only
   sub-behaviours. `update_sprites` (interlude) is the dispatcher over the
   already-tested `sp_*` steppers — low marginal value.
3. **`my_music_init` / `end_music_init`** — table/pointer init for the music
   players; testable but only meaningful alongside the players themselves.

## Adding a test

1. Pick a pure routine (no `$d012` polling). Note its inputs/outputs
   (registers + zero-page/memory addresses) and its label.
2. If the part isn't built by `run.sh` yet, add it to `PARTS=(...)`.
3. Add a `test(...)` block to `tests/sim6502/<part>.6502`: set inputs, `jsr`
   the label, `assert` the outputs. `.const`s aren't in the `.sym`
   (KickAssembler emits labels only) — use raw addresses (e.g. `$f8`) for
   those. Add `cycles < N` asserts for hot paths and `memchk`/`memcmp` for
   fill/copy routines.
4. `./tests/sim6502/run.sh`.

See `tests/sim6502/intro.6502` for the worked example (the
`calc_active_count` suite) and `tests/sim6502/README.md` for the short version.
