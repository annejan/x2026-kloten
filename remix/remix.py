#!/usr/bin/env python3
"""Kloten met de broodtrommel — remix for annejan.com.

A full remix of the demo's music, synthesised from scratch with numpy/scipy
(no samples, no soundfonts). The material is the demo's own: the Am-Em-F-G
progression, bass_pattern and lead_pattern from parts/intro/intro.asm, at the
demo's 125 BPM, but half-time: one chord per bar, the bass and lead in 8ths.
The arrangement follows docs/sound-arc.md: intro, intro outro, interlude,
hush, greets, coda, end.

80 bars = 320 beats = 153.6 s: five 64-beat loops of the site demo, so the
demo's visuals stay on the beat when the audio loops.

Usage: remix.py out/remix.wav
"""
import sys
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 48000
BPM = 125
BEAT = 60 / BPM                 # 0.48 s
BAR = 4 * BEAT
E8 = BEAT / 2                   # an 8th
E16 = BEAT / 4
BARS = 80
LENGTH = BARS * BAR
N = int(round(LENGTH * SR))
rng = np.random.default_rng(2026)

# --- Material from intro.asm (note numbers there are octave*12+semitone; MIDI = +12) -------

def demo_note(n):
    return n + 12

N_ = dict(E2=28, F2=29, G2=31, A2=33, B2=35, C3=36, D3=38, E3=40, F3=41, G3=43, A3=45,
          B3=47, C4=48, D4=50, E4=52, F4=53, G4=55, A4=57, B4=59)
R = None
CHORDS = [  # Am, Em, F, G: root, 3rd, 5th (demo octave)
    (N_['A2'], N_['C3'], N_['E3']),
    (N_['E2'], N_['G2'], N_['B2']),
    (N_['F2'], N_['A2'], N_['C3']),
    (N_['G2'], N_['B2'], N_['D3']),
]
BASS = [
    'A2 A2 A3 A2 A2 E3 A3 A2', 'E2 E2 E3 E2 E2 B2 E3 E2',
    'F2 F2 F3 F2 F2 C3 F3 F2', 'G2 G2 G3 G2 G2 D3 G3 G2',
]
BASS = [[N_[x] for x in row.split()] for row in BASS]
LEAD = '''
A3 - E3 - A3 C4 E3 -   G3 - B3 - E4 G3 E3 -   F3 - A3 - F4 A3 C4 -   G3 - B3 - D4 G4 F4 E4
A4 C4 E4 A4 C4 E4 C4 A3   B3 D4 G3 B3 E4 G3 E3 B3   C4 A3 F3 A3 F4 C4 A3 F3   D4 B3 G3 B3 G4 D4 B3 G3
E4 A4 E4 C4 A4 E4 A4 E4   B3 E4 G4 B4 E4 B3 E4 G4   C4 F4 A4 - F4 C4 A3 F3   G4 B4 D4 - B4 G4 D4 B3
E4 - C4 - A3 - - -   E4 - B3 - G3 - - -   F3 - C4 - F3 - - -   G3 - D4 - G3 - - -
'''.split()
LEAD = [None if x == '-' else N_[x] for x in LEAD]
assert len(LEAD) == 128


def hz(demo_n, octave=0):
    m = demo_note(demo_n) + 12 * octave
    return 440.0 * 2 ** ((m - 69) / 12)


def t2i(t):
    return int(round(t * SR))


# --- Building blocks --------------------------------------------------------------------------

def env_adsr(n, a, d, s, r, hold):
    """ADSR in seconds; `hold` is the gate length; returns n samples."""
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-6), 1.0)
    dec = np.exp(-(t - a) / max(d, 1e-6)) * (1 - s) + s
    e = np.where(t >= a, dec, e)
    rel = np.where(t > hold, np.exp(-(t - hold) / max(r, 1e-6)), 1.0)
    return e * rel


def saw(f, t, phase=0.0):
    x = (f * t + phase) % 1.0
    return 2 * x - 1


def pulse(f, t, width):
    return np.where(((f * t) % 1.0) < width, 1.0, -1.0)


def lowpass(x, cutoff, q=0.707):
    sos = signal.butter(2, min(cutoff, SR * 0.45), 'low', fs=SR, output='sos')
    return signal.sosfilt(sos, x)


def highpass(x, cutoff):
    sos = signal.butter(2, cutoff, 'high', fs=SR, output='sos')
    return signal.sosfilt(sos, x)


def bandpass(x, lo, hi):
    sos = signal.butter(2, [lo, hi], 'band', fs=SR, output='sos')
    return signal.sosfilt(sos, x)


def sweep_lowpass(x, cutoffs, block=256):
    """Low-pass with a cutoff that changes per block (cutoffs: one value per sample)."""
    out = np.zeros_like(x)
    zi = np.zeros((1, 2))
    for i in range(0, len(x), block):
        c = float(np.clip(cutoffs[min(i + block // 2, len(cutoffs) - 1)], 40, SR * 0.45))
        b, a = signal.butter(2, c, 'low', fs=SR)
        sos = np.concatenate([b, a])[None, :]
        out[i:i + block], zi = signal.sosfilt(sos, x[i:i + block], zi=zi)
    return out


def add(buf, start, sig, gain=1.0, pan=0.0):
    """Mix a mono signal into a stereo buffer at time `start` with constant-power pan."""
    i = t2i(start)
    if i >= N:
        return
    sig = sig[:N - i]
    left = np.cos((pan + 1) * np.pi / 4) * gain
    right = np.sin((pan + 1) * np.pi / 4) * gain
    buf[0, i:i + len(sig)] += sig * left
    buf[1, i:i + len(sig)] += sig * right


# --- Instruments ------------------------------------------------------------------------------

def kick():
    n = t2i(0.45)
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t / 0.035)
    phase = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t / 0.22)
    click = rng.standard_normal(n) * np.exp(-t / 0.002) * 0.3
    return np.tanh(1.6 * (body + highpass(click, 2000)))


def clap():
    n = t2i(0.35)
    t = np.arange(n) / SR
    noise = bandpass(rng.standard_normal(n), 900, 3500)
    bursts = sum(np.exp(-np.clip(t - d, 0, None) / 0.006) * (t >= d) for d in (0, 0.011, 0.022))
    tail = np.exp(-np.clip(t - 0.03, 0, None) / 0.12) * (t >= 0.03)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.05) * 0.4
    return (noise * (bursts * 0.6 + tail) + tone) * 0.8


def hat(open_=False):
    n = t2i(0.4 if open_ else 0.06)
    t = np.arange(n) / SR
    noise = highpass(rng.standard_normal(n), 7000)
    return noise * np.exp(-t / (0.12 if open_ else 0.018)) * 0.5


def crash():
    n = t2i(2.0)
    t = np.arange(n) / SR
    return highpass(rng.standard_normal(n), 5000) * np.exp(-t / 0.7) * 0.35


def snare_roll_hit(i, total):
    n = t2i(0.12)
    t = np.arange(n) / SR
    noise = bandpass(rng.standard_normal(n), 1500, 6000)
    return noise * np.exp(-t / 0.04) * (0.3 + 0.7 * i / total)


def riser(seconds):
    n = t2i(seconds)
    x = rng.standard_normal(n)
    cut = np.geomspace(300, 9000, n)
    y = sweep_lowpass(x, cut)
    return y * np.linspace(0, 1, n) ** 2 * 0.35


def sub_bass(f, dur):
    n = t2i(dur + 0.05)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * f * t) * env_adsr(n, 0.005, 0.2, 0.8, 0.04, dur)


def saw_bass(f, dur, bright):
    n = t2i(dur + 0.05)
    t = np.arange(n) / SR
    x = saw(f, t) + 0.5 * saw(f * 1.005, t)
    e = env_adsr(n, 0.003, 0.12, 0.35, 0.05, dur)
    return lowpass(x, 300 + bright) * e * 0.5


def pad_chord(notes, dur, octave=1):
    """Supersaw chord: 7 detuned saws per note, slow attack, soft low-pass."""
    n = t2i(dur + 0.6)
    t = np.arange(n) / SR
    left = np.zeros(n)
    right = np.zeros(n)
    detunes = [-0.18, -0.11, -0.05, 0, 0.05, 0.11, 0.18]
    for note in notes:
        f = hz(note, octave)
        for k, d in enumerate(detunes):
            v = saw(f * 2 ** (d / 12), t, phase=rng.random())
            if k % 2:
                left += v
            else:
                right += v
    e = env_adsr(n, 0.25, 0.6, 0.75, 0.5, dur)
    return lowpass(left, 2500) * e * 0.05, lowpass(right, 2500) * e * 0.05


def chip_arp(notes, dur, step=1 / 50):
    """The demo's SID arp: a pulse that cycles root/3rd/5th/octave every frame (50 Hz)."""
    n = t2i(dur)
    t = np.arange(n) / SR
    seq = list(notes) + [notes[0] + 12]
    idx = (t / step).astype(int) % 4
    f = np.array([hz(seq[i], 1) for i in range(4)])[idx]
    phase = np.cumsum(f) / SR
    width = 0.25 + 0.15 * np.sin(2 * np.pi * 0.3 * t)
    x = np.where((phase % 1.0) < width, 1.0, -1.0)
    return lowpass(x, 3000) * env_adsr(n, 0.01, 0.1, 0.9, 0.05, dur - 0.05) * 0.06


def lead_note(f, dur, kind='pulse', vibrato=True):
    n = t2i(dur + 0.25)
    t = np.arange(n) / SR
    vib = np.where(t > 0.15, 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t), 1.0) if vibrato else 1.0
    phase = np.cumsum(f * vib) / SR
    if kind == 'bell':
        x = np.sin(2 * np.pi * phase) + 0.3 * np.sin(2 * np.pi * phase * 3.01) * np.exp(-t / 0.15)
        e = env_adsr(n, 0.002, 0.5, 0.0, 0.3, dur)
        return x * e * 0.35
    width = 0.3 + 0.15 * np.sin(2 * np.pi * 0.7 * t)
    x = 0.6 * np.where((phase % 1.0) < width, 1.0, -1.0) + 0.4 * (2 * (phase % 1.0) - 1)
    e = env_adsr(n, 0.004, 0.18, 0.6, 0.12, dur)
    return lowpass(x, 4500) * e * 0.22


# --- Effects ----------------------------------------------------------------------------------

def reverb_ir(seconds=2.2, predelay=0.02):
    n = t2i(seconds)
    t = np.arange(n) / SR
    ir = np.zeros((2, n + t2i(predelay)))
    for ch in range(2):
        noise = rng.standard_normal(n) * np.exp(-t / (seconds / 6.9))
        ir[ch, t2i(predelay):] = lowpass(noise, 6000)
    return ir / np.sqrt((ir ** 2).sum(axis=1, keepdims=True))


def reverb(stereo, wet, ir):
    out = np.zeros_like(stereo)
    for ch in range(2):
        out[ch] = signal.fftconvolve(stereo[ch], ir[ch])[:stereo.shape[1]]
    return stereo + out * wet


def pingpong(stereo, delay, feedback, mix):
    d = t2i(delay)
    out = stereo.copy()
    tap = stereo.mean(axis=0)
    gain = mix
    for k in range(1, 6):
        ch = k % 2
        if d * k >= stereo.shape[1]:
            break
        out[ch, d * k:] += tap[:-d * k] * gain
        gain *= feedback
    return out


def sidechain(times, depth=0.6, release=0.18):
    """Gain curve that ducks after every kick time."""
    g = np.ones(N)
    shape = 1 - depth * np.exp(-np.arange(t2i(release * 3)) / (release * SR / 2))
    for tm in times:
        i = t2i(tm)
        seg = shape[:N - i]
        g[i:i + len(seg)] = np.minimum(g[i:i + len(seg)], seg)
    return g


# --- Arrangement ------------------------------------------------------------------------------

SECTIONS = [  # name, first bar, bars
    ('intro', 0, 8), ('intro_outro', 8, 8), ('interlude', 16, 8), ('hush', 24, 8),
    ('greets', 32, 16), ('coda', 48, 16), ('end', 64, 16),
]


def section_of(bar):
    for name, start, length in SECTIONS:
        if start <= bar < start + length:
            return name, bar - start, length
    return 'end', 0, 16


def render():
    drums = np.zeros((2, N))
    bass = np.zeros((2, N))
    pads = np.zeros((2, N))
    arps = np.zeros((2, N))
    lead = np.zeros((2, N))
    fx = np.zeros((2, N))
    K, C, HC, HO, CR = kick(), clap(), hat(), hat(True), crash()
    kick_times = []

    for bar in range(BARS):
        name, b, length = section_of(bar)
        t0 = bar * BAR
        chord = CHORDS[bar % 4]
        last = b == length - 1

        # Drums
        full = name in ('intro_outro', 'greets', 'coda', 'hush') or (name == 'interlude' and b >= 7)
        if name == 'intro' and b >= 4:
            for q in range(4):
                add(drums, t0 + q * BEAT, lowpass(K, 250), 0.7)
                kick_times.append(t0 + q * BEAT)
        if full and not (name == 'interlude' and b < 7):
            for q in range(4):
                add(drums, t0 + q * BEAT, K, 0.95)
                kick_times.append(t0 + q * BEAT)
                if q in (1, 3):
                    add(drums, t0 + q * BEAT, C, 0.55, 0.05)
                add(drums, t0 + q * BEAT + E8, HO if name in ('greets', 'coda') else HC, 0.35, 0.3)
            if name in ('greets', 'coda'):
                for s in range(16):
                    if s % 2:
                        add(drums, t0 + s * E16, HC, 0.18, -0.35)
            if name in ('greets', 'coda') and b % 4 == 0:
                add(drums, t0, CR, 0.6, 0.0)
        if name in ('interlude', 'intro_outro', 'coda') and last:
            for s in range(16):                                    # snare roll into the next part
                add(drums, t0 + s * E16, snare_roll_hit(s, 16), 0.7, 0.1)
        if name in ('intro', 'interlude', 'coda') and last:
            add(fx, t0 - BAR, riser(2 * BAR), 1.0)

        # Bass: sub + saw in 8ths, the demo's pattern
        if name not in ('intro',) or b >= 4:
            if not (name == 'interlude' and b < 7) and name != 'end':
                for s, note in enumerate(BASS[bar % 4]):
                    f = hz(note, -1)
                    add(bass, t0 + s * E8, sub_bass(f, E8 * 0.9), 0.32)
                    add(bass, t0 + s * E8, saw_bass(hz(note, 0), E8 * 0.8, 900 if name in ('greets', 'coda') else 400), 0.6)
            elif name == 'end' and b < 12:
                add(bass, t0, sub_bass(hz(chord[0], -1), BAR * 0.95), 0.5)

        # Pads
        if name in ('intro', 'interlude', 'coda', 'end', 'greets', 'hush'):
            gain = {'intro': 0.6 + 0.05 * b, 'interlude': 1.0, 'coda': 1.1, 'end': 0.9, 'greets': 0.55, 'hush': 0.6}[name]
            pl, pr = pad_chord(chord, BAR)
            pads[0, t2i(t0):t2i(t0) + len(pl)] += pl[:N - t2i(t0)] * gain
            pads[1, t2i(t0):t2i(t0) + len(pr)] += pr[:N - t2i(t0)] * gain
        if name == 'greets':                                       # supersaw stabs on the off-beats
            for q in range(4):
                sl, sr_ = pad_chord(chord, E16, octave=1)
                add_st = t2i(t0 + q * BEAT + E8)
                ln = min(len(sl), N - add_st)
                pads[0, add_st:add_st + ln] += sl[:ln] * 1.4
                pads[1, add_st:add_st + ln] += sr_[:ln] * 1.4

        # The SID arp
        if (name == 'intro' and b >= 2) or name in ('intro_outro', 'greets', 'end', 'hush') or (name == 'interlude' and b >= 4):
            add(arps, t0, chip_arp(chord, BAR), 0.9 if name != 'end' else 0.7, -0.4)

        # Lead
        if name == 'end':
            # Reprise: half speed, one lead note per beat, bells.
            for q in range(4):
                note = LEAD[(b * 4 + q) % 128]
                if note is not None and b < 14:
                    add(lead, t0 + q * BEAT, lead_note(hz(note, 0), BEAT * 0.9, 'bell'), 0.7, 0.2)
        else:
            start_step = {'intro': 0, 'intro_outro': 64, 'interlude': 0, 'hush': 64, 'greets': 64, 'coda': 0}[name]
            if name == 'intro' and b < 4:
                continue_lead = False
            else:
                continue_lead = True
            if continue_lead:
                kind = 'bell' if name in ('interlude', 'intro') else 'pulse'
                octave = 1 if name == 'coda' and b >= 8 else 0
                for s in range(8):
                    step = (start_step + (b - 4 if name == 'intro' else b) * 8 + s) % 128
                    note = LEAD[step]
                    if note is None:
                        continue
                    # hold the note until the next note or rest
                    length = 1
                    while length < 4 and LEAD[(step + length) % 128] is None and s + length < 8:
                        length += 1
                    dur = E8 * length * 0.92
                    add(lead, t0 + s * E8, lead_note(hz(note, octave), dur, kind), 0.8, 0.0)
                    if name == 'coda' and octave:
                        add(lead, t0 + s * E8, lead_note(hz(note, 0), dur, kind), 0.45, -0.2)

    # Section-wide processing ------------------------------------------------------------------
    t = np.arange(N) / SR
    bar_of = (t / BAR).astype(int)

    # Intro: pads and arp open up; hush: everything but the drums closes.
    cut = np.full(N, 9000.0)
    intro = bar_of < 8
    cut[intro] = np.geomspace(250, 9000, intro.sum())
    hush = (bar_of >= 24) & (bar_of < 32)
    cut[hush] = np.geomspace(6000, 220, hush.sum())
    # Greets: wah on the lead (5 s LFO)
    greets = (bar_of >= 32) & (bar_of < 48)
    wah = np.full(N, 9000.0)
    wah[greets] = 900 + 2600 * (0.5 + 0.5 * np.sin(2 * np.pi * t[greets] / 5.12))

    for buf in (pads, arps, bass):
        for ch in range(2):
            buf[ch] = sweep_lowpass(buf[ch], cut)
    for ch in range(2):
        lead[ch] = sweep_lowpass(sweep_lowpass(lead[ch], cut), wah)

    bass = highpass(bass, 32)                                   # keep the sub off the kick's 45 Hz
    duck = sidechain(kick_times)
    bass *= duck
    pads *= 0.4 + 0.6 * duck
    arps *= 0.5 + 0.5 * duck

    ir = reverb_ir()
    lead = pingpong(lead, 3 * E16, 0.45, 0.35)
    lead = reverb(lead, 0.35, ir)
    pads = reverb(pads, 0.25, ir)
    arps = pingpong(arps, E8, 0.4, 0.3)
    arps = reverb(arps, 0.2, ir)
    drums = reverb(drums, 0.06, ir)
    fx = reverb(fx, 0.3, ir)

    mix = drums * 1.0 + bass * 0.8 + pads * 1.25 + arps * 0.85 + lead * 1.25 + fx * 0.8

    # End: fade out over the last 4 bars, into the intro's fade-in when the audio loops.
    fade = np.ones(N)
    tail = t2i(4 * BAR)
    fade[-tail:] = np.linspace(1, 0, tail) ** 1.5
    mix *= fade
    # Intro fade-in over the first bar (matches the loop seam).
    head = t2i(BAR)
    mix[:, :head] *= np.linspace(0, 1, head)

    # Master: gentle glue, soft clip, normalise to -1 dBFS peak.
    mix = highpass(mix, 25)
    mix = np.tanh(mix * 0.9) / np.tanh(0.9)
    mix *= 10 ** (-1 / 20) / np.abs(mix).max()
    return mix


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'out/remix.wav'
    mix = render()
    wavfile.write(out, SR, (mix.T * 32767).astype(np.int16))
    print(f'{out}: {mix.shape[1] / SR:.2f} s')
