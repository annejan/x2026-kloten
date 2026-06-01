# sim6502 unit tests

6502 unit tests for the demo's **pure routines**, using
[sim6502](https://github.com/barryw/sim6502) (Barry Walker's 6502 assembly
testing framework) via its Docker image.

## Run

```bash
./tests/sim6502/run.sh          # build parts + run all suites
./tests/sim6502/run.sh -t       # with instruction trace
```

`run.sh` (re)assembles each part-under-test to a `.prg` + copies its
KickAssembler `.sym`, then runs every `*.6502` suite through
`ghcr.io/barryw/sim6502:latest` (repo root mounted at `/code`).

Exit code is 0 if all tests pass, 1 otherwise — CI-friendly.

## What can be tested here

The `sim` backend is a **flat 64 KB RAM** machine — no VIC-II, no raster, no
badlines. So only **pure, deterministic, `jsr`/`rts` routines** belong here:
they read inputs from registers/memory, compute, write outputs, and return.

- ✅ Good: math, table lookups, counters, memory fills/copies, sprite-attribute
  bit-twiddling (writes to `$d0xx` just land in RAM, harmless).
- ❌ Not here: anything that **polls `$d012`** (raster waits hang forever in
  flat RAM), depends on IRQ timing, badlines, or live VIC/SID behaviour.
  Those need the `vice` backend (hardware-accurate, via the VICE-MCP server)
  — see the sim6502 README's "VICE Backend" section.

## Suites

| File | Part | Routines (cases) |
|------|------|---------|
| `intro.6502` | intro | `calc_active_count` (9), `reveal_column` (7), `wipe_out_column` (5), `move_sprites` (4) — cascade count, logo wipe, sine-driven sprite positions |
| `coda.6502` | coda | `kloot_advance` (5) — ping-pong star-shape counter |
| `end.6502` | end | `push_next_credit_row` (6) — credit-row push + header/body/fade colour; `scroll_rows_up` (4) — credit roll coarse scroll-up |
| `interlude.6502` | interlude | `fire_propagate` (5) — fire engine: open-bus mask, cool/no-cool, banner guard/burn; `write_plasma_row` (3) — 2D plasma colour kernel |
| `greets.6502` | greets | `update_sprite_ptrs` (4) — reversed char→ptr DYCP rebuild, carousel, 16-bit reach |

## Adding a test

1. Pick a pure routine (no `$d012` polling). Note its inputs/outputs
   (registers + zero-page/memory addresses) and its label.
2. If the part isn't built yet, add it to `PARTS=(...)` in `run.sh`.
3. Add a `test(...)` block (or a new `<part>.6502` suite): set inputs, `jsr`
   the label, `assert` the outputs. `.const`s aren't in the `.sym` (KickAss
   emits labels only) — use raw addresses (e.g. `$f8`) for those.
