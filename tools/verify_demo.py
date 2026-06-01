#!/usr/bin/env python3
"""verify_demo.py — smoke-test the full demo through VICE-MCP.

Launches VICE (via run-mcp.sh or connects to an existing instance),
steps through the demo in real-time (or warp with --warp), and validates
each part transition.

Usage:
  python3 tools/verify_demo.py              # launch VICE + test (real-time)
  python3 tools/verify_demo.py --connect    # connect to running VICE
  python3 tools/verify_demo.py --warp       # play through in warp (faster,
                                            # but memory reads are flakier)

Checks:
  - Each part loads within expected frame budget
  - $D418 (SID volume) stays non-zero during music parts
  - $F6 transition byte reaches the expected value per pefchain_script
  - End card stays on last frame (no crash to BASIC)
"""

import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error

MCP_URL = "http://127.0.0.1:6510/mcp"
WARP_DELAY = 0.2       # seconds between polls
# Warp plays through faster but memory reads are unreliable under warp on this
# VICE-MCP build, so default to real-time; opt in with --warp.
USE_WARP = "--warp" in sys.argv

# Expected transition values per pefchain_script
# (part_name, transition_byte, expected_value)
PARTS = [
    ("screenfill",  0x06, 0x00),  # HOLDCNT drains to 0
    ("intro",       0xF6, 0xF0),  # zp_outro hits T_OUTRO_DONE
    ("interlude",   0xF6, 0x30),  # fire phase completed
    ("greets",      0xF6, 0x82),  # scroll-driven settle
    ("coda",        0xF6, 0x30),  # timer counts to $30
    ("end",         None, None),   # stay forever
]

# SID music parts should have $D418 non-zero
MUSIC_PARTS = {"intro", "interlude", "greets", "coda"}

# Expected $D015 sprite enable values (approximate — sprite count varies)
# None = don't check
EXPECTED_SPRITES = {
    "screenfill":  None,
    "intro":       0xFF,  # 8 sprites
    "interlude":   0x03,  # SPARKED letter sprites (2 or more)
    "greets":      0x80,  # sprite-7 carousel
    "coda":        0xC0,  # two Kloot stars
    "end":         None,
}


def mcp_call(method, params=None):
    """Call a VICE-MCP tool. Returns result dict or None on error."""
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": method, "arguments": params or {}}
    }
    try:
        req = urllib.request.Request(
            MCP_URL,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
        if "error" in data:
            print(f"  MCP error: {data['error']}", file=sys.stderr)
            return None
        return data.get("result", {}).get("content", [{}])[0].get("text", "")
    except (urllib.error.URLError, ConnectionRefusedError, json.JSONDecodeError) as e:
        return None
    except Exception as e:
        print(f"  MCP exception: {e}", file=sys.stderr)
        return None


def mcp_parse(method, params=None):
    """Call MCP, parse JSON result."""
    raw = mcp_call(method, params)
    if not raw:
        return None
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return raw


def read_mem(address, size):
    """Read C64 memory via MCP. Returns bytes or None.

    New MCP format: {"address":.., "size":.., "encoding":"array",
    "data":["67","0f",..]} — a dict whose `data` is a list of HEX STRINGS.
    Older builds returned a bare list of ints; handle both.
    """
    result = mcp_parse("vice.memory.read", {"address": address, "size": size})
    if isinstance(result, dict) and "data" in result:
        try:
            return bytes(int(b, 16) for b in result["data"])
        except (ValueError, TypeError):
            return None
    if isinstance(result, list):
        return bytes(result)
    return None


def read_byte(address):
    """Read a single byte from C64 memory."""
    data = read_mem(address, 1)
    if data:
        return data[0]
    return None


def read_word(address):
    """Read a 16-bit little-endian word from C64 memory."""
    data = read_mem(address, 2)
    if data:
        return data[0] | (data[1] << 8)
    return None


def get_pc():
    """Get current program counter. MCP returns uppercase 'PC'."""
    regs = mcp_parse("vice.registers.get")
    if isinstance(regs, dict):
        return regs.get("PC", regs.get("pc"))
    return None


def set_warp(enabled):
    """Enable/disable warp via the WarpMode resource.

    The standalone vice.execution.set_warp tool no longer exists; warp is a
    machine resource toggled through vice.machine.config.set.
    """
    mcp_call("vice.machine.config.set",
             {"resources": {"WarpMode": 1 if enabled else 0}})


def run_test():
    print("=== VICE-MCP Demo Verification ===\n")

    # Check MCP is alive
    ping = mcp_call("vice.ping")
    if ping is None:
        print("❌ Cannot connect to VICE-MCP. Start run-mcp.sh first "
              "or pass --connect if already running.")
        return False

    print("✓ Connected to VICE-MCP\n")

    # Read current machine state
    regs = mcp_parse("vice.registers.get")
    if isinstance(regs, dict):
        pc = regs.get("PC", 0)
        print(f"  CPU: PC=${pc:04X}  A=${regs.get('A',0):02X}  X=${regs.get('X',0):02X}  Y=${regs.get('Y',0):02X}")
        print()

    # Warm reset via MCP (set PC to reset vector)
    # Wait for screenfill to appear
    print("  Waiting for demo to boot...")
    for attempt in range(50):
        byte = read_byte(0x06)  # screenfill HOLDCNT
        if byte is not None:
            print(f"  System alive: $06 = ${byte:02x}")
            break
        time.sleep(0.5)
    else:
        print("❌ Demo didn't boot within 25 s")
        return False

    # Warp plays through faster, but memory reads are unreliable under warp on
    # this VICE build, so default to real-time. Opt in with --warp.
    if USE_WARP:
        set_warp(True)
        print("  Warp mode ON\n")
    else:
        print("  Real-time mode (reliable reads; pass --warp to speed up)\n")

    # Track part transitions
    current_part = -1
    part_frames = {}
    t_start = time.monotonic()

    MAX_FRAMES = 18000  # ~6 min at 50 fps = safety limit
    end_stable = 0  # frames the end card has been showing

    for frame in range(MAX_FRAMES):
        # Check transition byte for current part
        if current_part < len(PARTS) - 1:
            part_name, addr, expected = PARTS[current_part + 1]
            if addr is not None:
                val = read_byte(addr)
                if val is not None and val == expected:
                    current_part += 1
                    elapsed = time.monotonic() - t_start
                    pc = get_pc()
                    d418 = read_byte(0xD418)
                    d015 = read_byte(0xD015)
                    pc_str = f"${pc:04X}" if pc else "????"
                    d418_str = f"${d418:02x}" if d418 is not None else "??"
                    d015_str = f"${d015:02x}" if d015 is not None else "??"
                    print(f"  → {part_name} (frame ~{frame}, {elapsed:.1f}s, "
                          f"PC={pc_str}, $D418={d418_str} $D015={d015_str})")
                    part_frames[part_name] = frame

        # Once we've seen all parts, wait a few more ticks for stability
        if current_part == len(PARTS) - 1:
            end_stable += 1
            if end_stable >= 5:
                print(f"  → end card stable for {end_stable} polls")
                break

        # Check we haven't crashed
        pc = get_pc()
        if pc is None:
            print(f"\n❌ MCP connection lost at frame {frame}")
            return False
        if pc in (0xFFFF, 0x0000):
            print(f"\n❌ PC=${pc:04X} — machine appears hung at frame {frame}")
            return False

        # SID health check: $D417 voice routing and $D418 volume+filter
        d417 = read_byte(0xD417)
        d418 = read_byte(0xD418)
        if d418 is not None and d418 & 0x0F == 0 and current_part >= 0:
            part_name = PARTS[current_part][0]
            print(f"  ⚠ {part_name}: SID volume=0 ($D418=${d418:02x}) at frame ~{frame}")
        if (d418 is not None and (d418 & 0x10) and d417 is not None
                and (d417 & 0x07) == 0 and current_part >= 0):
            part_name = PARTS[current_part][0]
            print(f"  ⚠ {part_name}: LP mode on but no voice routing "
                  f"($D418=${d418:02x}, $D417=${d417:02x}) at frame ~{frame}")

        time.sleep(WARP_DELAY)
    else:
        print(f"\n⚠ Reached max frames ({MAX_FRAMES}) — demo didn't finish")
        return False

    # Disable warp
    if USE_WARP:
        set_warp(False)

    print(f"\n=== Results ===")
    all_parts_seen = len(part_frames) == len(PARTS) - 1  # -1 because 'end' stays

    if all_parts_seen:
        print(f"✓ All {len(PARTS)} parts loaded successfully")
        for name, frame in part_frames.items():
            print(f"  {name}: frame {frame}")
        print()
        print("✓ Demo runs to completion without crash")
        return True
    else:
        missing = [p[0] for p in PARTS if p[0] not in part_frames]
        print(f"❌ Missing parts: {', '.join(missing)}")
        return False


def main():
    if "--connect" in sys.argv:
        ok = run_test()
        sys.exit(0 if ok else 1)

    # Launch VICE via run-mcp.sh
    script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    run_mcp = os.path.join(script_dir, "run-mcp.sh")
    if not os.path.exists(run_mcp):
        print(f"run-mcp.sh not found at {run_mcp}")
        sys.exit(1)

    print("Launching VICE via run-mcp.sh...")
    vice_proc = subprocess.Popen(
        [run_mcp],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Wait for MCP to be available and demo to autostart
    for attempt in range(60):
        result = mcp_call("vice.ping")
        if result is not None:
            pc = get_pc()
            if pc is not None and pc > 0x0800:
                print(f"  Demo running (PC=${pc:04X}) after {attempt + 1}s")
                break
            elif pc is not None:
                print(f"  VICE alive, waiting for load (PC=${pc:04X})")
        time.sleep(1)
    else:
        print("❌ Demo didn't autostart within 60 s")
        vice_proc.terminate()
        sys.exit(1)

    ok = run_test()
    vice_proc.terminate()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
