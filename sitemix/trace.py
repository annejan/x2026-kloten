#!/usr/bin/env python3
"""Run the site-mix player in a 6502 emulator and log SID writes per frame.

Usage: trace.py out/sitemix.prg [frames]
Prints, per step boundary, which V3 drum row fired, so the drum pattern can be
checked without listening.
"""
import sys
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory


def run(prg_path, frames):
    prg = open(prg_path, 'rb').read()
    load = prg[0] | prg[1] << 8
    mem = ObservableMemory()
    for i, b in enumerate(prg[2:]):
        mem[load + i] = b
    writes = []
    mem.subscribe_to_write(range(0xd400, 0xd419), lambda addr, val: writes.append((addr, val)))
    mpu = MPU(memory=mem)

    def call(addr):
        # JSR addr with a return to a BRK-free trampoline at $0300: RTS lands on $0302, we stop there.
        mem[0x0300], mem[0x0301], mem[0x0302] = 0x20, addr & 0xff, addr >> 8
        mem[0x0303] = 0xea
        mpu.pc = 0x0300
        mpu.sp = 0xff
        for _ in range(200000):
            mpu.step()
            if mpu.pc == 0x0303:
                return
        raise RuntimeError('player did not return')

    call(load)
    log = []
    for f in range(frames):
        writes.clear()
        call(load + 3)
        log.append(list(writes))
    return log


if __name__ == '__main__':
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 7680
    log = run(sys.argv[1], frames)
    for f, w in enumerate(log):
        regs = dict(w)
        print(f, ' '.join(f'{a - 0xd400:02x}={v:02x}' for a, v in w))
