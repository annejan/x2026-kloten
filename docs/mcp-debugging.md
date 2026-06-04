# VICE-MCP debugging cookbook

The MCP server exposes 64 tools (`tools/list`) for poking VICE from outside the
emulator. This doc captures the ones we use, the gotchas, and
ready-to-paste recipes for the kinds of measurements we keep
needing on this project.

`./run-mcp.sh` boots the demo with VICE-MCP listening on
`http://127.0.0.1:6510/mcp`. After ~17 s of real-time boot + autostart, the
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
- `vice.memory.read` — `address=...`, `size=...`. Returns a JSON
  object `{"address":…, "size":…, "encoding":"array",
  "data":["67","0f",…]}` — `data` is a list of hex-byte **strings**
  (parse with `int(b, 16)`). **NB**: the param is `size`, not
  `length`. (Older builds returned a bare list of ints; current ones
  wrap it in the object above — see `tools/verify_demo.py` `read_mem`
  for a both-formats parser.)
- `vice.memory.write` — `address=...`, `data=[...]` (list of ints).
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

### CPU / registers
- `vice.registers.get` — returns a JSON object with **uppercase**
  keys: `{"PC":…, "A":…, "X":…, "Y":…, "SP":…}` plus boolean status
  flags `N V B D I Z C`. (Watch the case — `regs["pc"]` is a classic
  silent `None`.) `PC` is decimal; format with `"$%04X" % pc`.
- `vice.registers.set` — write any of the same registers.
- `vice.ping` — `{"status":"ok","version":…,"machine":…,
  "execution":"running"|"paused"}`. Handy: the `execution` field
  tells you if a prior `run_until` left the machine paused.

### Display / capture
- `vice.display.screenshot` — `path="..."` writes to a file, or
  omit `path` to get base64 in the response. PNG. Returns
  `{"status":"ok","format":"PNG","path":…}`.
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

The inheritor parts (interlude/greets/coda) hard-code
`INTRO_MUSIC_PLAY = $119e`. After any refactor of the music
segment, run this check.

### Measure how many cycles `my_music_play` actually costs

The music routine is monolithic — `my_music_play` (at $119e) does the
whole per-frame update (V1/V2/V3 + the V3 drum table), so this is the
routine to time. It advances `mu_step` only on `STEP_FRAMES` boundaries,
so the cost varies frame to frame.

```python
call("vice.symbols.load", path="parts/intro/intro.sym")
play_addr = call("vice.symbols.lookup", name="my_music_play")["address"]
rts_addr  = play_addr + N   # find rts via disassemble first

# checkpoint at entry and exit
cp_in  = call("vice.checkpoint.add", address=play_addr)
cp_out = call("vice.checkpoint.add", address=rts_addr)

call("vice.run_until", address=play_addr, timeout=2.0)
call("vice.cycles.stopwatch", action="reset")
call("vice.run_until", address=rts_addr,  timeout=2.0)
cy = call("vice.cycles.stopwatch", action="read")["cycles"]
print(f"my_music_play took {cy} cycles this call")
```

Repeat over many frames (some on step boundaries, some not) to
build a distribution.

### Catch the K=0 fade-text-pulled-up frame

```python
# bounce_total is at $4800 (page-aligned). zp_frame is at $FE.
# K = bounce_total[zp_frame]. A K=0 frame is one where
# bounce_total[zp_frame] == 0.

# Auto-snapshot on entry to irq_fld when K=0:
fld = call("vice.symbols.lookup", name="irq_fld")["address"]
cp = call("vice.checkpoint.add", address=fld)
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

Expected (intro):
```
  IRQ  @raster   1 ...  # irq_open
  IRQ  @raster  3b ...  # irq_fld   (FLD stretch zone lines $3B..$3B+K)
  IRQ  @raster  80 ...  # irq_bars  (BAR_TOP)
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

During a snare hit V3 ctrl reads `$81` (noise = drum) and during the
arp it reads `$41` (pulse = arp) — kick rows use `$11` (triangle).
This is by design: inside the monolithic `my_music_play` the V3 drum
tick block runs LAST (after the arp's gate write), so the drum
waveform wins for the whole `DRUM_LEN` window. If you instead see the
ctrl thrashing $41/$81 mid-window, something is writing $d412 after
the drum tick.

## Known limitations of this VICE-MCP build

These came up in real sessions; document so we don't re-discover.

### `vice.interrupt.log` is a config stub
The `start` call returns a `log_id` but logs nothing — the response
includes the note *"Config stored. Actual logging requires VICE
interrupt hook integration."* Don't rely on it for IRQ-chain
verification. Fall back to PC polling: pause / `registers.get` /
resume in a tight loop catches PC across the chain probabilistically.

### `vice.run_until` is asynchronous and unreliable
The schema says "Run until address …" but in practice the call
returns immediately with a "resumed, will stop at target" status
and doesn't always actually pause when the target is hit. PC stays
in the scroller's tight loop at $5Exx forever even with checkpoints
set at IRQ entry addresses. Suspect the binary monitor's checkpoint
"stop on hit" isn't fully wired in this build.

**Workaround**: don't use `run_until` for "advance to this address
then measure"; use `vice.execution.run` for a known wall-clock
duration + `vice.execution.pause` + `vice.registers.get`. Sample
PC many times to build a coverage distribution if you need to know
"is this handler being hit at all".

### `vice.cycles.stopwatch` only accumulates while running
- `reset` while paused: OK, sets cycle counter to 0.
- `read` while paused: returns the cycles accumulated during the
  PREVIOUS run window.
- The `read` value is 0 if reset was the last call and no `run`
  happened between reset and read.

To time a routine entry-to-exit, you'd need: pause-at-entry,
reset, run-until-exit (which is broken — see above), read. We
don't currently have a reliable end-to-end cycle measurement
recipe; the path forward is either to fix the VICE-MCP build's
checkpoint hooks or to use the binary monitor directly via
`tools/vicemon.py`.

### `vice.snapshot.load` doesn't auto-resume
After load, the emulator stays paused. Explicit
`vice.execution.run` afterwards.

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
- For cycle-accurate measurements: prefer `tools/vicemon.py` direct
  binary-monitor calls over the MCP layer. The MCP's stopwatch +
  run_until pair isn't sufficient for entry-to-exit timing of
  raster IRQ handlers in this build.
