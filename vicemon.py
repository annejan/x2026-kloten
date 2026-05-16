#!/usr/bin/env python3
"""
tools/vicemon.py — VICE binary monitor client for Umbra (C64 Platformer).
Stdlib-only, no external dependencies.

Protocol: https://vice-emu.sourceforge.io/vice_13.html#SEC338
Validated against https://github.com/Galfodo/pyvicemon

CLI usage:
  python3 tools/vicemon.py ping
  python3 tools/vicemon.py read ADDR LEN        # e.g.  read 0x0002 80
  python3 tools/vicemon.py dump-zp              # dump $0002-$00FF
  python3 tools/vicemon.py regs                 # CPU registers (A X Y PC SP FLAGS)
  python3 tools/vicemon.py resume               # resume execution (exit monitor pause)
  python3 tools/vicemon.py reset [hard]         # soft (default) or hard reset
  python3 tools/vicemon.py breakpoint ADDR [TIMEOUT_SEC]  # set, wait, show state

Python API:
  import sys; sys.path.insert(0, 'tools')
  import vicemon
  with vicemon.ViceMonitor() as mon:
      mem  = mon.read_memory(0x0002, 80)        # bytes
      regs = mon.get_registers()                # {'A':0,'X':0,'PC':0x0810,...}
      bp   = mon.set_breakpoint(0x1000)         # returns checkpoint_id
      mon.wait_for_event(timeout=5.0)           # True if hit, False if timeout
      mon.delete_breakpoint(bp)

VICE must be running with:
  x64sc -binarymonitor -binarymonitoraddress 127.0.0.1:6502 build/game.d64
  (shortcut: make run-bg)
"""

import select
import socket
import struct
import sys
import time

HOST = '127.0.0.1'
PORT = 6502
TIMEOUT = 5.0

STX = 0x02
API_VERSION = 0x02

# Request header (11 bytes): STX B | API_VER B | body_size I | req_id I | cmd B
REQ_HDR_FMT  = '<BBIIB'
REQ_HDR_SIZE = struct.calcsize(REQ_HDR_FMT)   # 11

# Response header (12 bytes): STX B | API_VER B | body_size I | resp_type B | error B | req_id I
RESP_HDR_FMT  = '<BBIBBI'
RESP_HDR_SIZE = struct.calcsize(RESP_HDR_FMT)  # 12

# Command codes (MonCommand enum from pyvicemon vice_monitor.py)
CMD_MEM_GET           = 0x01
CMD_MEM_SET           = 0x02
CMD_CHECKPOINT_SET    = 0x12
CMD_CHECKPOINT_DELETE = 0x13
CMD_REGISTERS_GET     = 0x31
CMD_REGISTERS_AVAIL   = 0x83
CMD_PING              = 0x81
CMD_EXIT              = 0xAA  # resume execution
CMD_RESET             = 0xCC
CMD_KEYBOARD_FEED     = 0x72

# Unsolicited response types VICE sends when execution changes state
RESP_STOPPED  = 0x62
RESP_RESUMED  = 0x63
RESP_JAM      = 0x61  # CPU JAM (illegal opcode)

# Breakpoint mode flags (combinable)
BREAK_EXEC  = 0x04
BREAK_LOAD  = 0x01
BREAK_STORE = 0x02

MEM_MAIN = 0x00


class ViceError(RuntimeError):
    pass


class ViceMonitor:
    def __init__(self, host=HOST, port=PORT, timeout=TIMEOUT):
        self.host = host
        self.port = port
        self.timeout = timeout
        self._sock = None
        self._req_id = 0
        self._buf = b''
        self._reg_ids = {}  # name -> id (populated lazily)

    def connect(self):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.settimeout(self.timeout)
        try:
            self._sock.connect((self.host, self.port))
        except ConnectionRefusedError:
            raise ViceError(
                f'Cannot connect to VICE binary monitor at {self.host}:{self.port}.\n'
                f'Start VICE with:  make run-bg'
            )
        except socket.timeout:
            raise ViceError(
                f'Timeout connecting to VICE binary monitor at {self.host}:{self.port}.'
            )

    def disconnect(self):
        if self._sock:
            self._sock.close()
            self._sock = None

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, *_):
        self.disconnect()

    # ------------------------------------------------------------------ low-level

    def _next_req_id(self):
        self._req_id += 1
        return self._req_id

    def _send(self, cmd, body=b''):
        req_id = self._next_req_id()
        hdr = struct.pack(REQ_HDR_FMT, STX, API_VERSION, len(body), req_id, cmd)
        self._sock.sendall(hdr + body)
        return req_id

    def _recv_exactly(self, n):
        while len(self._buf) < n:
            chunk = self._sock.recv(65536)
            if not chunk:
                raise ViceError('VICE disconnected unexpectedly')
            self._buf += chunk
        data, self._buf = self._buf[:n], self._buf[n:]
        return data

    def _recv_response(self):
        hdr_raw = self._recv_exactly(RESP_HDR_SIZE)
        stx, ver, body_size, resp_type, error, req_id = struct.unpack(RESP_HDR_FMT, hdr_raw)
        if stx != STX or ver != API_VERSION:
            raise ViceError(f'Bad response header: {hdr_raw.hex()}')
        body = self._recv_exactly(body_size)
        return resp_type, error, req_id, body

    def _roundtrip(self, cmd, body=b''):
        """Send a command and return the matching response body. Discards unrelated events."""
        req_id = self._send(cmd, body)
        while True:
            resp_type, error, rid, data = self._recv_response()
            if rid == req_id:
                if error != 0:
                    raise ViceError(f'VICE returned error 0x{error:02x} for cmd 0x{cmd:02x}')
                return data
            # Discard unsolicited STOPPED/RESUMED events that arrive mid-command

    # ------------------------------------------------------------------ public API

    def ping(self):
        self._roundtrip(CMD_PING)

    def read_memory(self, addr, length, side_effects=False):
        """Read `length` bytes from C64 address `addr`. Returns bytes."""
        end_addr = min(addr + length - 1, 0xFFFF)
        body = struct.pack('<BHHBH',
            1 if side_effects else 0,
            addr, end_addr,
            MEM_MAIN, 0   # memspace=main, bank_id=0
        )
        data = self._roundtrip(CMD_MEM_GET, body)
        return data[2:]  # skip the 2-byte length prefix in the response

    def write_memory(self, addr, data, side_effects=False):
        """Write bytes to C64 address `addr`."""
        end_addr = min(addr + len(data) - 1, 0xFFFF)
        body = (struct.pack('<BHHBH',
            1 if side_effects else 0,
            addr, end_addr,
            MEM_MAIN, 0)
            + bytes(data))
        self._roundtrip(CMD_MEM_SET, body)

    def _load_registers_available(self):
        data = self._roundtrip(CMD_REGISTERS_AVAIL, struct.pack('<B', MEM_MAIN))
        count = struct.unpack_from('<H', data, 0)[0]
        offset = 2
        self._reg_ids = {}
        for _ in range(count):
            item_size  = data[offset]
            reg_id     = data[offset + 1]
            # reg_bitsize at offset+2 (unused here)
            name_len   = data[offset + 3]
            name       = data[offset + 4:offset + 4 + name_len].decode()
            self._reg_ids[name] = reg_id
            offset += item_size + 1

    def get_registers(self):
        """Return CPU registers as a dict, e.g. {'A':0,'X':0,'Y':0,'PC':2064,'SP':255,'Flags':0}."""
        if not self._reg_ids:
            self._load_registers_available()
        data = self._roundtrip(CMD_REGISTERS_GET, struct.pack('<B', MEM_MAIN))
        count = struct.unpack_from('<H', data, 0)[0]
        offset = 2
        id_to_name = {v: k for k, v in self._reg_ids.items()}
        regs = {}
        for _ in range(count):
            item_size = data[offset]        # always 3
            reg_id    = data[offset + 1]
            value     = struct.unpack_from('<H', data, offset + 2)[0]
            name      = id_to_name.get(reg_id, f'R{reg_id}')
            regs[name] = value
            offset += item_size + 1
        return regs

    def set_breakpoint(self, addr, end_addr=None, mode=BREAK_EXEC,
                       enabled=True, stop_when_hit=True, temporary=False):
        """Set a breakpoint and return its checkpoint_id (needed for delete_breakpoint)."""
        if end_addr is None:
            end_addr = addr
        body = struct.pack('<HHBBBBB',
            addr, end_addr,
            1 if enabled else 0,
            1 if stop_when_hit else 0,
            mode,
            1 if temporary else 0,
            MEM_MAIN,
        )
        data = self._roundtrip(CMD_CHECKPOINT_SET, body)
        checkpoint_id = struct.unpack_from('<I', data, 0)[0]
        return checkpoint_id

    def delete_breakpoint(self, checkpoint_id):
        """Delete a previously set breakpoint by its checkpoint_id."""
        self._roundtrip(CMD_CHECKPOINT_DELETE, struct.pack('<I', checkpoint_id))

    def resume(self):
        """Resume execution after a breakpoint pause. No-op if already running."""
        self._roundtrip(CMD_EXIT)
        # Flush any immediate RESUMED event so it doesn't confuse wait_for_event
        old_timeout = self._sock.gettimeout()
        self._sock.settimeout(0.1)
        try:
            self._recv_response()   # discard RESUMED event
        except (socket.timeout, ViceError):
            pass
        finally:
            self._sock.settimeout(old_timeout)

    def wait_for_event(self, timeout=10.0):
        """Wait up to `timeout` seconds for a STOPPED event (breakpoint hit or JAM).
        Returns True if stopped, False if timeout.
        Does NOT send resume — call resume() first if VICE is already paused.
        """
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            readable, _, _ = select.select([self._sock], [], [], min(remaining, 1.0))
            if not readable:
                continue
            try:
                resp_type, error, rid, data = self._recv_response()
                if resp_type in (RESP_STOPPED, RESP_JAM):
                    return True
            except socket.timeout:
                pass

    def reset(self, soft=True):
        """Soft reset (default) or hard reset (power cycle) the C64."""
        self._roundtrip(CMD_RESET, struct.pack('<B', 0 if soft else 1))

    def keyboard_feed(self, petscii_bytes):
        """Inject PETSCII bytes into the C64 keyboard buffer, e.g. b'RUN\\r'."""
        body = struct.pack('<B', len(petscii_bytes)) + bytes(petscii_bytes)
        self._roundtrip(CMD_KEYBOARD_FEED, body)


# ------------------------------------------------------------------ CLI helpers

def _hexdump(addr, data):
    lines = []
    for i in range(0, len(data), 16):
        chunk = data[i:i+16]
        hex_part = ' '.join(f'{b:02x}' for b in chunk)
        asc_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
        lines.append(f'${addr+i:04x}: {hex_part:<48}  {asc_part}')
    return '\n'.join(lines)


def _die(msg, code=1):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(code)


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]

    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__)
        return

    cmd = argv[0].lower()
    mon = ViceMonitor()
    try:
        mon.connect()
    except ViceError as e:
        _die(str(e))

    try:
        if cmd == 'ping':
            mon.ping()
            print('pong ok')

        elif cmd == 'read':
            if len(argv) < 3:
                _die('Usage: read ADDR LEN  (hex or decimal)')
            addr   = int(argv[1], 0)
            length = int(argv[2], 0)
            mem = mon.read_memory(addr, length)
            print(_hexdump(addr, mem))

        elif cmd == 'dump-zp':
            mem = mon.read_memory(0x02, 0xFE)   # skip $00-$01 (hardware I/O port)
            print(_hexdump(0x02, mem))

        elif cmd == 'regs':
            regs = mon.get_registers()
            width = max(len(k) for k in regs) if regs else 6
            for name, val in sorted(regs.items()):
                print(f'  {name:<{width}} = ${val:04x}  ({val})')

        elif cmd == 'resume':
            mon.resume()
            print('resumed')

        elif cmd == 'reset':
            hard = len(argv) > 1 and argv[1].lower() == 'hard'
            mon.reset(soft=not hard)
            print(f"{'hard' if hard else 'soft'} reset sent")

        elif cmd == 'breakpoint':
            if len(argv) < 2:
                _die('Usage: breakpoint ADDR [timeout_sec]')
            addr    = int(argv[1], 0)
            timeout = float(argv[2]) if len(argv) > 2 else 10.0
            bp_id   = mon.set_breakpoint(addr)
            print(f'Breakpoint {bp_id} set at ${addr:04x}. Waiting up to {timeout}s...')
            if mon.wait_for_event(timeout):
                regs = mon.get_registers()
                print(f'Stopped. PC=${regs.get("PC", 0):04x}')
                width = max(len(k) for k in regs) if regs else 6
                for name, val in sorted(regs.items()):
                    print(f'  {name:<{width}} = ${val:04x}  ({val})')
                mon.delete_breakpoint(bp_id)
            else:
                mon.delete_breakpoint(bp_id)
                _die(f'Timeout — breakpoint at ${addr:04x} not hit within {timeout}s')

        else:
            _die(f'Unknown command: {cmd!r}\n\nRun without arguments to see usage.')

    except ViceError as e:
        _die(str(e))
    except socket.timeout:
        _die('Timeout waiting for VICE response')
    finally:
        mon.disconnect()


if __name__ == '__main__':
    main()
