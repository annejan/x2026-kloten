#!/usr/bin/env python3
"""Record the outline-64 demo to an MP4 from a running VICE-MCP session.

Pipeline:
  1. Reset + autostart the .d64 via VICE-MCP.
  2. ffmpeg `x11grab` captures the VICE window region.
  3. ffmpeg `-f pulse` captures the system speaker monitor (pulseaudio).
  4. Both streams encoded into a single MP4 (H.264 video + AAC audio).

Defaults are tuned for the canonical run:
  - 210 s duration = ~3 s boot + 117 s demo + ~90 s end credits
    (= a bit more than one full 61.4-second music cycle in end so the
     friends watching get to read the credits a touch longer than
     strictly necessary).
  - 50 fps to match the C64 PAL frame rate exactly.
  - CRF 20 H.264 + 192 kbps AAC ≈ 25-30 MB final size.

Requirements:
  - VICE-MCP server running at 127.0.0.1:6510 (./run-mcp.sh)
  - ffmpeg with x11grab + pulse demuxers
  - wmctrl (window geometry)
  - pactl (pulseaudio source enumeration)

Caveat: the speaker monitor captures EVERYTHING playing through the
default sink. Mute browsers/music players before recording or accept
that they'll bleed into the audio track.
"""
import argparse
import json
import subprocess
import sys
import time
import urllib.request

DEFAULT_URL = "http://127.0.0.1:6510/mcp"
DEFAULT_WIN_NAME = "VICE (C64SC)"
DEFAULT_DURATION_S = 210
DEFAULT_FPS = 50
DEFAULT_CRF = 20
DEFAULT_AUDIO_BITRATE = "192k"
DEFAULT_OUTPUT = "/tmp/outline64_demo.mp4"


def mcp_call(url: str, name: str, **args) -> dict:
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": name, "arguments": args}}
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        d = json.load(r)
    return json.loads(d["result"]["content"][0]["text"])


def find_window(name: str) -> tuple[int, int, int, int]:
    """Return (x, y, width, height) for the first window matching `name`."""
    out = subprocess.check_output(["wmctrl", "-lG"], text=True)
    for line in out.splitlines():
        if name in line:
            parts = line.split()
            return int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5])
    raise RuntimeError(f"no window matching {name!r} — is VICE running?")


def find_speaker_monitor() -> str:
    """Pick the most plausible 'system speakers' monitor source from pactl."""
    out = subprocess.check_output(["pactl", "list", "short", "sources"], text=True)
    candidates: list[tuple[int, str]] = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        name, state = parts[1], parts[-1]
        if ".monitor" not in name:
            continue
        score = 0
        if state == "RUNNING":
            score += 10        # actively playing audio — almost certainly the right one
        if "Speaker" in name:
            score += 5         # internal speakers > HDMI when both present
        candidates.append((score, name))
    if not candidates:
        raise RuntimeError("no pulseaudio monitor source found")
    candidates.sort(reverse=True)
    return candidates[0][1]


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--d64", default="/home/annejan/Projects/x2026/outline-64.d64",
                   help="path to the .d64 to autostart (default: %(default)s)")
    p.add_argument("-o", "--output", default=DEFAULT_OUTPUT,
                   help="output .mp4 path (default: %(default)s)")
    p.add_argument("-t", "--duration", type=int, default=DEFAULT_DURATION_S,
                   help="recording duration in seconds (default: %(default)s)")
    p.add_argument("--fps", type=int, default=DEFAULT_FPS,
                   help="capture frame rate (default: %(default)s; C64 PAL is 50)")
    p.add_argument("--crf", type=int, default=DEFAULT_CRF,
                   help="H.264 CRF, lower is better quality (default: %(default)s)")
    p.add_argument("--audio-bitrate", default=DEFAULT_AUDIO_BITRATE,
                   help="AAC audio bitrate (default: %(default)s)")
    p.add_argument("--window", default=DEFAULT_WIN_NAME,
                   help="VICE window title substring (default: %(default)r)")
    p.add_argument("--mcp-url", default=DEFAULT_URL,
                   help="VICE-MCP JSON-RPC endpoint (default: %(default)s)")
    p.add_argument("--no-reset", action="store_true",
                   help="skip the VICE reset+autostart (record whatever's "
                        "already running)")
    args = p.parse_args()

    x, y, w, h = find_window(args.window)
    audio_src = find_speaker_monitor()
    print(f"VICE window: {w}x{h} at +{x},{y}", file=sys.stderr)
    print(f"audio source: {audio_src}", file=sys.stderr)

    if not args.no_reset:
        # Ensure real-time playback (no warp).
        mcp_call(args.mcp_url, "vice.machine.config.set",
                 resources={"WarpMode": 0})
        mcp_call(args.mcp_url, "vice.machine.reset", mode="hard")
        time.sleep(0.3)
        mcp_call(args.mcp_url, "vice.autostart", path=args.d64)

    ffmpeg_cmd = [
        "ffmpeg", "-y",
        "-f", "x11grab",
        "-video_size", f"{w}x{h}",
        "-framerate", str(args.fps),
        "-i", f":0.0+{x},{y}",
        "-f", "pulse",
        "-i", audio_src,
        "-c:v", "libx264", "-preset", "fast", "-crf", str(args.crf),
        "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", args.audio_bitrate,
        "-t", str(args.duration),
        args.output,
    ]
    print(f"recording {args.duration}s → {args.output}", file=sys.stderr)
    print(" ".join(ffmpeg_cmd), file=sys.stderr)
    subprocess.run(ffmpeg_cmd, check=True)
    print(f"done: {args.output}", file=sys.stderr)
    subprocess.run(["ls", "-la", args.output])
    return 0


if __name__ == "__main__":
    sys.exit(main())
