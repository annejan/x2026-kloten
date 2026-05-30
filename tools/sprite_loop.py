#!/usr/bin/env python3
"""sprite_loop.py — fast sprite iteration without rebuilding the demo.

Parses the `sprite_shape:` .byte rows out of parts/intro/intro.asm and:
  - prints them as a unicode half-block grid in the terminal (instant, no emulator)
  - with --poke: writes the 63 bytes live into the running VICE at $0B00
    (sprite block $2C, where intro copies the shape) and screenshots.

Usage:
  python3 tools/sprite_loop.py                 # terminal preview only
  python3 tools/sprite_loop.py --poke          # + live-poke running VICE + screenshot
  python3 tools/sprite_loop.py --save-snap      # snapshot current VICE state (do once, in intro)
  python3 tools/sprite_loop.py --poke --restore # restore snapshot, then poke (drift-proof)
  python3 tools/sprite_loop.py --label NAME    # read a different label
"""
import json, re, sys, urllib.request

ASM = "parts/intro/intro.asm"
SPR_ADDR = 0x0B00            # SPR_DATA in intro.asm (block $2C)
MCP = "http://127.0.0.1:6510/mcp"
SNAP = "/tmp/sprite_intro.vsf"   # snapshot at sprite-visible frame

def parse_shape(path, label="sprite_shape"):
    rows = []
    grabbing = False
    for line in open(path):
        s = line.strip()
        if s.startswith(label + ":"):
            grabbing = True
            continue
        if not grabbing:
            continue
        m = re.match(r"\.byte\s+%([01]{8}),\s*%([01]{8}),\s*%([01]{8})", s)
        if m:
            rows.append([int(m.group(i), 2) for i in (1, 2, 3)])
        elif s.startswith(".byte 0") or s == "" or s.startswith("//"):
            if rows:               # stop at the sentinel after data
                break
        else:
            if rows:
                break
    return rows

def preview(rows):
    # hires sprite: 24 px wide, 1 bit/px. Pair rows into half-blocks.
    bits = []
    for r in rows:
        line = ""
        for byte in r:
            for k in range(7, -1, -1):
                line += "#" if (byte >> k) & 1 else "."
        bits.append(line)
    print(f"\n  {len(rows)} rows × 24 px\n")
    # render two source-rows per text-row using ▀▄█ space
    i = 0
    while i < len(bits):
        top = bits[i]
        bot = bits[i + 1] if i + 1 < len(bits) else "." * 24
        out = "  "
        for t, b in zip(top, bot):
            t = t == "#"; b = b == "#"
            out += "█" if t and b else "▀" if t else "▄" if b else " "
        print(out)
        i += 2
    print()

def mcp(method, args):
    payload = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
               "params": {"name": method, "arguments": args}}
    req = urllib.request.Request(MCP, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        d = json.loads(resp.read())
    if "error" in d:
        raise RuntimeError(d["error"])
    return d.get("result", {}).get("content", [{}])[0].get("text", "")

def poke(rows, shot="/tmp/sprite_live.png"):
    data = [b for r in rows for b in r]      # 63 bytes
    mcp("vice.memory.write", {"address": SPR_ADDR, "data": data})
    mcp("vice.display.screenshot", {"path": shot, "format": "png"})
    print(f"poked {len(data)} bytes @ ${SPR_ADDR:04X} → {shot}")

if __name__ == "__main__":
    label = "sprite_shape"
    if "--label" in sys.argv:
        label = sys.argv[sys.argv.index("--label") + 1]
    rows = parse_shape(ASM, label)
    preview(rows)
    if "--save-snap" in sys.argv:
        mcp("vice.snapshot.save", {"name": "sprite_intro"})
        print("snapshot saved (name=sprite_intro)")
    if "--restore" in sys.argv:
        mcp("vice.snapshot.load", {"name": "sprite_intro"})
        print("snapshot restored (name=sprite_intro)")
    if "--poke" in sys.argv:
        poke(rows)
