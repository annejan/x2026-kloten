#!/usr/bin/env python3
"""Restart the demo in the running VICE-MCP, run real-time to the coda,
detect it by signature, and record a tight clip (video + audio) of the
beat-reactive title card.

Coda signature (all must hold):
  - $d018 == $14            (coda sets screen $0400 / chargen $1000)
  - $05c0..$05c1 == 0b 0c   ("KL" of KLOTEN on text row 11, col 8)
  - $d015 != 0              (Kloot star sprites enabled)

Requires VICE-MCP already up at 127.0.0.1:6510 + X display + ffmpeg.
"""
import json, subprocess, sys, time, urllib.request

URL = "http://127.0.0.1:6510/mcp"
D64 = "/home/annejan/Projects/x2026/outline-64.d64"
OUT = "/tmp/coda_beat.mp4"
WIN_NAME = "VICE"
REC_SECONDS = 16


def call(name, **args):
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": name, "arguments": args}}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as r:
        d = json.load(r)
    return json.loads(d["result"]["content"][0]["text"])


def rd(addr, size=1):
    # Retry transient MCP hiccups (occasional missing 'result' / timeout).
    last = None
    for _ in range(4):
        try:
            d = call("vice.memory.read", address=addr, size=size)
            return [int(b, 16) for b in d["data"]]
        except Exception as e:
            last = e
            time.sleep(0.1)
    raise last


def find_window():
    out = subprocess.check_output(["wmctrl", "-lG"], text=True)
    for line in out.splitlines():
        if WIN_NAME in line:
            p = line.split()
            return int(p[2]), int(p[3]), int(p[4]), int(p[5])
    raise RuntimeError("no VICE window")


def find_monitor():
    out = subprocess.check_output(["pactl", "list", "short", "sources"], text=True)
    best, bestscore = None, -1
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 5 or ".monitor" not in parts[1]:
            continue
        score = (10 if parts[-1] == "RUNNING" else 0) + (5 if "Speaker" in parts[1] else 0)
        if score > bestscore:
            best, bestscore = parts[1], score
    return best


def state():
    d011 = rd(0xd011)[0]; d018 = rd(0xd018)[0]; d015 = rd(0xd015)[0]
    f8 = rd(0x07f8)[0]; row11 = rd(0x05c0, 6)
    return d011, d018, d015, f8, row11


def is_coda(st):
    d011, d018, d015, f8, row11 = st
    # text mode (BMM clear) + sprites on + Kloot sprite pointer range.
    # End has sprites off; intro is bitmap (BMM set).
    return (d011 & 0x20) == 0 and d015 != 0 and 0x80 <= f8 <= 0xdf


def main():
    print("config: WarpMode=0, SidModel=1", file=sys.stderr)
    call("vice.machine.config.set", resources={"WarpMode": 0, "SidModel": 1})
    print("hard reset + autostart", file=sys.stderr)
    call("vice.machine.reset", mode="hard")
    time.sleep(0.4)
    call("vice.autostart", path=D64)

    t0 = time.time()
    POLL_AFTER = 110.0      # coda is ~144s in; start polling early to be safe
    TIMEOUT = 240.0
    print(f"running real-time; logging+polling for coda after {POLL_AFTER:.0f}s...", file=sys.stderr)
    detected = False
    last_log = 0.0
    while time.time() - t0 < TIMEOUT:
        el = time.time() - t0
        if el >= POLL_AFTER:
            st = state()
            if el - last_log >= 1.0:
                d011, d018, d015, f8, row11 = st
                print(f"t={el:5.1f} d011={d011:#04x} d018={d018:#04x} d015={d015:#04x} "
                      f"07f8={f8:#04x} row11={' '.join(f'{b:02x}' for b in row11)}", file=sys.stderr)
                last_log = el
            if is_coda(st):
                detected = True
                print(f"CODA detected at t={el:.1f}s", file=sys.stderr)
                break
            time.sleep(0.3)
        else:
            time.sleep(2.0)

    if not detected:
        print("coda not detected within timeout", file=sys.stderr)
        return 2

    # Grab VICE framebuffer screenshots (immune to screensaver/overlays).
    import os
    shotdir = "/tmp/codashot"
    os.makedirs(shotdir, exist_ok=True)
    for f in os.listdir(shotdir):
        os.remove(os.path.join(shotdir, f))
    n = 0
    t1 = time.time()
    while time.time() - t1 < 12.0:        # ~12s of coda
        p = f"{shotdir}/f{n:03d}.png"
        try:
            call("vice.display.screenshot", path=p, format="png")
            n += 1
        except Exception as e:
            print(f"shot {n} err {e}", file=sys.stderr)
        time.sleep(0.18)
    print(f"DONE: {n} screenshots in {shotdir}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
