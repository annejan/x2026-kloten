# VICE-MCP debugging cookbook

The MCP server exposes ~70 tools for poking VICE from outside the
emulator. This doc captures the ones we use, the gotchas, and
ready-to-paste recipes for the kinds of measurements we keep
needing on this project.

`./run-mcp.sh` boots the demo with VICE-MCP listening on
`127.0.0.1:6510`. After ~17 s of real-time boot + autostart, the
demo is live and the MCP is responsive.

## Calling the MCP from Python

The MCP server speaks JSON-RPC over HTTP POST. Every tool call has
the shape:

```python
body = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {"name": "<toolname>", "arguments": {...}}
}
```

### Gotcha: don't name your helper's first arg `name`

If you write a wrapper like `def call(name, **args)`, Python's kwarg
expansion collides with `name=` when the MCP tool itself has a
`name` argument (e.g. `vice.symbols.lookup`). Use a different
parameter name in your helper:

```python
def call(toolname, **args):
    body = {"jsonrpc":"2.0","id":1,"method":"tools/call",
            "params":{"name":toolname,"arguments":args}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                  headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(json.load(r)["result"]["content"][0]["text"])

# Now this works:
call("vice.symbols.lookup", name="my_music_play")
```

### Result-format quirk

Most tools return JSON, but it's wrapped twice: the HTTP body is
JSON-RPC with `result.content[0].text` being **another JSON string**
that you need to parse. The helper above handles it.

## Tool catalogue (the ones we actually use)

### Execution control
- `vice.execution.pause` / `vice.execution.run` — pause/resume.
- `vice.execution.step` — single-step instructions (N steps).
- `vice.run_until` — run until address OR for N cycles. Has a
  `timeout` arg (seconds) so you don't hang the session.
- `vice.machine.reset` — soft/hard reset.

### Symbols
- `vice.symbols.load` — pass a `.sym` file path. The intro's lives
  at `parts/intro/intro.sym`. KickAsm sym files are auto-detected.
- `vice.symbols.lookup` — `name="my_music_play"` or `address=$119e`
  to resolve symbol ↔ address either way.

Always load symbols once per session before doing checkpoint /
breakpoint work — the tool output is much more readable when
addresses come back with labels.

### Memory
- `vice.memory.read` — `address=...`, `size=...`. Returns a list
  of hex bytes as strings. **NB**: the param is `size`, not
  `length`.
- `vice.memory.write` — `address=...`, `data=[...]` (bytes).
- `vice.memory.search` — pattern search, useful for finding loose
  references after a refactor.
- `vice.memory.compare` — compare two ranges, or a range against
  a snapshot. Mode flag picks behaviour.
- `vice.memory.fill` — repeat-byte fill.

### Checkpoints / breakpoints
- `vice.checkpoint.add` — drop a breakpoint on an address (or
  range). Use the lookup-by-symbol pattern for readability.
- `vice.checkpoint.set_condition` — gate a checkpoint by an
  expression. Lets us catch "K=0 only" frames or similar.
- `vice.checkpoint.group.create` / `add` / `toggle` — bundle
  related breakpoints so you can flip them all at once.
- `vice.checkpoint.set_auto_snapshot` — when this breakpoint hits,
  auto-save a snapshot. Pure gold for capturing intermittent bugs.

### Cycle / timing measurement
- `vice.cycles.stopwatch` — `reset` to start, `read` for elapsed
  CPU cycles. This is how you actually verify the budget estimates
  in `intro-architecture.md`. Wrap the routine under test in a
  stopwatch reset + read, possibly with checkpoint triggers.
- `vice.interrupt.log.start` / `read` / `stop` — record every
  IRQ/NMI/BRK with timestamps. Returns a `log_id` you pass back
  to read/stop. Essential for seeing whether IRQs fire late.

### Display / capture
- `vice.display.screenshot` — `path="..."` writes to a file, or
  omit `path` to get base64 in the response. PNG.
- `vice.display.get_dimensions` — output frame dimensions.

### VIC / SID / CIA state
- `vice.vicii.get_state` — dump every VIC register + computed
  state (raster line, sprite collisions, etc.).
- `vice.vicii.set_state` — write VIC regs.
- `vice.sid.get_state` — voice freq/duty/ctrl/ADSR + filter +
  master vol. Read after a `pause` to see what music_play left.
- `vice.cia.get_state` — CIA1/CIA2 state including timers,
  used by Spindle for NMI loader timing.

### Sprites
- `vice.sprite.inspect` — visual ASCII representation of a
  sprite's bitmap data. Reads pointer + data + multicolour
  setup. Saves the "is that sprite shape what we think it is?"
  back-and-forth.
- `vice.sprite.get` / `set` — read/write sprite X/Y/colour.

### Disassembly + trace
- `vice.disassemble` — disassemble N bytes from an address.
- `vice.trace.start` / `stop` — record an execution trace to a
  file. Returns instruction count etc.

### Snapshots
- `vice.snapshot.save` — name your save. Useful for "freeze
  the moment something glitched" workflows.
- `vice.snapshot.load` — restore. Combined with auto-snapshot on
  checkpoint, this is how you reproducibly bisect a bug that
  only happens 1-in-100 frames.

## Recipes

### Time the demo's full intro deterministically

The demo runs at PAL 50 Hz with `WarpMode=0`. From boot to "intro
mid-phase with all effects":
- Screenfill: ~5.6 s
- Intro setup: ~0.5 s
- T_SCROLLER reached: intro tick 240 = 9.6 s after intro start

So `sleep 17` puts you ~7 s into intro = full effects visible.

### Verify a label landed at the address we expect

```python
r = call("vice.symbols.lookup", name="my_music_play")
assert r["address"] == 0x119e, f"Music dispatcher moved to {r['address']:04x}!"
```

The inheritor parts (interlude/sinus/greets/coda) hard-code
`INTRO_MUSIC_PLAY = $119e`. After any refactor of the music
segment, run this check.

### Measure how many cycles `my_music_step` actually costs

```python
call("vice.symbols.load", path="parts/intro/intro.sym")
step_addr = call("vice.symbols.lookup", name="my_music_step")["address"]
rts_addr  = step_addr + N   # find rts via disassemble first

# checkpoint at entry and exit
cp_in  = call("vice.checkpoint.add", address=step_addr)
cp_out = call("vice.checkpoint.add", address=rts_addr)

call("vice.run_until", address=step_addr, timeout=2.0)
call("vice.cycles.stopwatch", action="reset")
call("vice.run_until", address=rts_addr,  timeout=2.0)
cy = call("vice.cycles.stopwatch", action="read")["cycles"]
print(f"my_music_step took {cy} cycles this call")
```

Repeat over many frames (some on step boundaries, some not) to
build a distribution.

### Catch the K=0 fade-text-pulled-up frame

```python
# bounce_total is at $4800 (page-aligned). zp_frame is at $FE.
# K = bounce_total[zp_frame]. A K=0 frame is one where
# bounce_total[zp_frame] == 0.

# Auto-snapshot on entry to irq_fld_bottom when K=0:
fld_bot = call("vice.symbols.lookup", name="irq_fld_bottom")["address"]
cp = call("vice.checkpoint.add", address=fld_bot)
call("vice.checkpoint.set_condition",
     checkpoint_num=cp["checkpoint_num"],
     condition="MEM($4800 + MEM($FE)) == 0")
call("vice.checkpoint.set_auto_snapshot",
     checkpoint_num=cp["checkpoint_num"],
     name="k0-frame")

# Now run the demo for a few seconds. When K=0 happens, we get a
# snapshot file. Restore later with vice.snapshot.load to inspect.
```

### Log every IRQ over 1 frame to verify chain order

```python
log_id = call("vice.interrupt.log.start")["log_id"]
call("vice.run_until", cycles=20_000)        # one PAL frame
entries = call("vice.interrupt.log.stop", log_id=log_id)["entries"]
for e in entries:
    print(f"  {e['type']:4s} @raster {e['raster']:>3x} cy {e['cycle']:>5d}")
```

Expected (intro, K=0):
```
  IRQ  @raster   1 ...  # irq_open
  IRQ  @raster  43 ...  # irq_fld
  IRQ  @raster  80 ...  # irq_bars
  IRQ  @raster  c3 ...  # irq_fld_bottom (K=0, trigger = $C3 + 0)
  IRQ  @raster  f9 ...  # irq_close
```

If any trigger lands later than expected → IRQ overrun in the
previous handler. The interrupt log makes this immediately
obvious where a flat raster check from outside would miss it.

### Compare SID state across frames to spot music glitches

```python
call("vice.execution.pause")
sid_a = call("vice.sid.get_state")
call("vice.execution.run")
time.sleep(0.02)              # exactly one frame at 50 Hz
call("vice.execution.pause")
sid_b = call("vice.sid.get_state")

# Compare V3 freq+ctrl across frames
print("V3 freq", sid_a["voices"][2]["freq"], "→", sid_b["voices"][2]["freq"])
print("V3 ctrl", sid_a["voices"][2]["ctrl"], "→", sid_b["voices"][2]["ctrl"])
```

If V3 ctrl is flipping between `$81` (noise = drum) and `$41`
(pulse = arp) every other frame, drum_tick is fighting with the
arp write. That was our pre-split race; the new my_music_critical
writes drum_tick LAST so V3 stays at `$81` for the full drum
window.

## Things to remember next session

- VICE-MCP boots at `127.0.0.1:6510`; `./run-mcp.sh` from project
  root handles startup.
- After symbols are loaded, every tool that takes an address can
  take a `name=` instead — much more readable in scripts.
- `vice.machine.config.set` with `Speed=400` + `WarpMode=0` gives
  a predictable 4× warp. Pure `WarpMode=1` is unbounded (= 100×+
  on a modern host).
- Write checkpoints with `store=true` are flaky under warp — use
  `vice.execution.pause` + polling for part-transition detection.
- The `'P', lo, hi` page-claim tags in EFO headers are the most
  common source of "this table was clean last frame but garbage
  now" bugs. Cross-check `intro.sym` against
  `intro_efo_header.asm` whenever a new resident table is added.
- For X2026 hardware target: PAL only. Don't optimize timing for
  NTSC.
