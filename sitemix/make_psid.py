#!/usr/bin/env python3
"""Wrap a KickAssembler .prg into a PSID v2 file (PAL, 8580, one song).

Usage: make_psid.py in.prg out.sid
The .prg's load address is the player's init address; play is init + 3.
"""
import struct
import sys

TITLE = 'Kloten met de broodtrommel (site mix)'
AUTHOR = 'Anus/deFEEST'
RELEASED = '2026 deFEEST'


def text(value):
    data = value.encode('latin-1')[:32]
    return data + b'\0' * (32 - len(data))


def main(prg_path, sid_path):
    prg = open(prg_path, 'rb').read()
    load = prg[0] | prg[1] << 8
    flags = 0x0004 | 0x0020            # PAL clock, 8580 SID
    header = struct.pack('>4sHHHHHHHI', b'PSID', 2, 0x7c, 0, load, load + 3, 1, 1, 0)
    header += text(TITLE) + text(AUTHOR) + text(RELEASED)
    header += struct.pack('>HBBH', flags, 0, 0, 0)
    assert len(header) == 0x7c
    open(sid_path, 'wb').write(header + prg)    # load address 0 in the header: keep the .prg's own


if __name__ == '__main__':
    main(*sys.argv[1:3])
