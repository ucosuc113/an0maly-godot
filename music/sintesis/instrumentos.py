"""Capas 1 a 3: voces e instrumentos.

  capa 1  generadores: osciladores de dsp.py combinados (unisono, FM, aditiva,
          granular) a partir de una curva de altura por muestra.
  capa 2  voz: generador + envolvente + filtro + modulaciones (LFO, deriva).
  capa 3  instrumento ("patch"): una o varias voces con su caracter fijo y
          su lugar en el estereo. La partitura solo habla con esta capa.

Cada patch devuelve (L, R) del largo justo de la nota mas su cola.
"""
import numpy as np

from . import dsp
from .dsp import SR


def fit(x, n):
    """Recorta o rellena con ceros a `n` muestras (los redondeos de las
    envolventes pueden diferir en una muestra)."""
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


class Bus:
    """Pista estereo donde se suman los instrumentos de una capa."""

    def __init__(self, seconds, name):
        self.n = int(seconds * SR)
        self.L = np.zeros(self.n)
        self.R = np.zeros(self.n)
        self.name = name

    def add(self, t, L, R=None, gain=1.0):
        if R is None:
            R = L
        i = int(round(t * SR))
        if i >= self.n:
            return
        k = min(len(L), self.n - i)
        self.L[i:i + k] += L[:k] * gain
        self.R[i:i + k] += R[:k] * gain


# ------------------------------------------------------------- capa 1: alturas

def pitch_curve(events, total, glide=0.06, start_midi=None):
    """Curva de altura (MIDI, por muestra) para una voz legato.

    events: [(t_inicio_s, midi), ...]. Entre notas la altura se acerca a la
    nueva con un portamento exponencial de constante `glide` s.
    """
    target = np.empty(total)
    ts = [int(t * SR) for t, _ in events] + [total]
    first = events[0][1] if start_midi is None else start_midi
    target[:ts[0]] = first
    for (t, m), a, b in zip(events, ts, ts[1:]):
        target[a:b] = m
    if glide <= 0:
        return target
    return dsp.onepole(target, np.exp(-1.0 / (glide * SR)))


def supersaw(freq, voices=7, spread=0.18, rng=None, stereo=True):
    """Unisono de sierras desafinadas (en semitonos +-spread), abiertas en el
    estereo. Fases aleatorias para que cada nota tenga su propio batido."""
    rng = rng or np.random.default_rng(0)
    L = np.zeros(len(freq))
    R = np.zeros(len(freq))
    for v in range(voices):
        x = (v / (voices - 1) - 0.5) * 2.0 if voices > 1 else 0.0
        det = 2.0 ** (x * spread / 12.0)
        s = dsp.saw(freq * det, rng.uniform())
        p = x * 0.8 if stereo else 0.0
        l, r = dsp.pan(s, p)
        L += l
        R += r
    g = 1.0 / np.sqrt(voices)
    return L * g, R * g


# ----------------------------------------------------- capa 2/3: instrumentos

def facility_lead(midi, dur, rng, glide_to=None, glide_time=0.0, vel=1.0):
    """Leitmotiv I: cristal FM de laboratorio + pulso suave una octava abajo.

    Afinacion perfecta, sin vibrato: la instalacion no duda. El indice de FM
    cae rapido (golpe brillante -> tono puro), como un instrumento de medicion.
    `glide_to` dobla la nota hacia otra altura (el agujero negro la arrastra).
    """
    tail = 0.9
    n = int((dur + tail) * SR)
    m = np.full(n, float(midi))
    if glide_to is not None:
        k0 = int(0.12 * dur * SR)
        k1 = min(n, k0 + int(glide_time * SR))
        sh = np.linspace(0, 1, k1 - k0) ** 2.2
        m[k0:k1] = midi + (glide_to - midi) * sh
        m[k1:] = glide_to
    f = dsp.midi_hz(m)
    idx = 0.4 + 3.2 * dsp.perc(n, 0.09)
    glass = dsp.fm(f, 3.0, idx, fb=0.25)
    bell = dsp.fm(f * 2.0, 3.5, 1.2 * dsp.perc(n, 0.25)) * 0.22
    body = dsp.pulse(f * 0.5, np.full(n, 0.32), rng.uniform())
    body = dsp.lowpass(body, 900.0 + 1800.0 * dsp.perc(n, 0.15), 0.8) * 0.28
    env = dsp.adsr(int(dur * SR), 0.004, 0.35, 0.55, tail, curve=5.0)
    x = (glass + bell + body) * fit(env, n) * vel
    x = dsp.highpass(x, 160.0)
    return dsp.pan(x, 0.08)


def singularity_lead(events, end, rng, redshift=-0.8, glide=0.16, bright=1.0):
    """Leitmotiv II: voz legato de sierras desafinadas con portamento.

    events: [(t_s, midi), ...] relativo al inicio de la frase; `end` = largo.
    Cada salto es un glissando lento (la gravedad tira de la nota). La ultima
    nota se corre al rojo `redshift` semitonos y el vibrato crece en las notas
    largas, como una senal que se estira al acercarse al horizonte.
    """
    tail = 2.5
    n = int((end + tail) * SR)
    m = pitch_curve(events, n, glide=glide)
    # Antes de cada salto la nota "cae" un poco: arrastre gravitacional.
    for (t, _), (t2, m2) in zip(events, events[1:]):
        a, b = int(t2 * SR) - int(0.12 * SR), int(t2 * SR)
        if a > int(t * SR):
            m[a:b] -= np.linspace(0, 0.35, b - a) ** 2
    # Corrimiento al rojo en la ultima nota.
    t_last = events[-1][0]
    a = int(t_last * SR)
    m[a:] += redshift * (np.linspace(0, 1, n - a) ** 1.6)
    # Vibrato que crece con el tiempo dentro de cada nota.
    starts = np.array([int(t * SR) for t, _ in events] + [n])
    age = np.zeros(n)
    for s0, s1 in zip(starts, starts[1:]):
        age[s0:s1] = np.arange(s1 - s0) / SR
    vib = 0.18 * np.clip((age - 0.35) / 1.2, 0, 1) * dsp.lfo(n, 4.6)
    f = dsp.midi_hz(m + vib)
    L, R = supersaw(f, voices=5, spread=0.14, rng=rng)
    sub = dsp.sine(f * 0.5) * 0.45
    L, R = L + sub, R + sub
    env = fit(dsp.adsr(int(end * SR), 0.18, 0.6, 0.85, tail, curve=3.0), n)
    cut = (600.0 + 2600.0 * bright * env) * (1.0 + 0.25 * dsp.lfo(n, 0.21))
    L = dsp.ladder(L * env, cut, 0.9, 1.4)
    R = dsp.ladder(R * env, cut * 1.03, 0.9, 1.4)
    return L * 0.9, R * 0.9


def arp_note(midi, dur, rng, accent=1.0, bend=0.0, crush=True):
    """Secuenciador: pulso con PWM + sierra, filtro con golpe de envolvente.
    Corto, seco y preciso: el reloj de la instalacion (lenguaje Portal 2)."""
    tail = 0.12
    n = int((dur + tail) * SR)
    f = dsp.midi_hz(np.full(n, midi + bend))
    pw = 0.5 + 0.18 * dsp.lfo(n, 0.7, rng.uniform())
    x = dsp.pulse(f, pw, rng.uniform()) * 0.7 + dsp.saw(f * 1.003, rng.uniform()) * 0.35
    fenv = dsp.perc(n, 0.07 + 0.05 * accent)
    x = dsp.svf(x, 380.0 + 4200.0 * accent * fenv, 2.2, 0)
    env = dsp.adsr(int(dur * 0.85 * SR), 0.002, 0.11, 0.35, tail, curve=6.0)
    x = x * fit(env, n) * (0.6 + 0.4 * accent)
    if crush:
        x = dsp.bitcrush(x, bits=9, hold=2) * 0.6 + x * 0.4
    return x


def pad_chord(midis, dur, rng, cutoff=1400.0, dark=0.0):
    """Colchon armonico: 7 sierras por nota, ataque y caida lentos, chorus."""
    rel = 2.2
    n = int((dur + rel) * SR)
    L = np.zeros(n)
    R = np.zeros(n)
    for m in midis:
        f = dsp.midi_hz(np.full(n, float(m)))
        f = f * (1.0 + 0.0012 * dsp.smooth_random(n, 0.4, rng))
        l, r = supersaw(f, voices=7, spread=0.2, rng=rng)
        L += l
        R += r
    env = fit(dsp.adsr(int(dur * SR), 1.1, 1.5, 0.8, rel, curve=3.0), n)
    cut = cutoff * (1.0 - 0.6 * dark) * (0.75 + 0.25 * env) * (1.0 + 0.12 * dsp.lfo(n, 0.13))
    L = dsp.lowpass(L, cut, 0.9) * env
    R = dsp.lowpass(R, cut * 1.04, 0.9) * env
    g = 0.35 / np.sqrt(len(midis))
    return L * g, R * g


def bass_note(midi, dur, rng, glide_from=None):
    """Bajo: sierra + sub seno, pasabajos de 24 dB con golpe de filtro."""
    tail = 0.08
    n = int((dur + tail) * SR)
    m = np.full(n, float(midi))
    if glide_from is not None:
        m = midi + (glide_from - midi) * np.exp(-np.arange(n) / (0.09 * SR))
    f = dsp.midi_hz(m)
    x = dsp.saw(f, rng.uniform()) * 0.6
    x = dsp.ladder(x, 160.0 + 900.0 * dsp.perc(n, 0.08), 1.1, 1.8)
    x += dsp.sine(f) * 0.7
    env = fit(dsp.adsr(int(dur * SR), 0.003, 0.2, 0.75, tail, curve=5.0), n)
    return x * env


def bass_legato(events, end, rng, glide=0.5):
    """Bajo del horizonte: una sola nota continua que se desliza hacia abajo."""
    tail = 1.5
    n = int((end + tail) * SR)
    m = pitch_curve(events, n, glide=glide)
    f = dsp.midi_hz(m)
    x = dsp.saw(f, rng.uniform()) * 0.5 + dsp.pulse(f * 0.5, np.full(n, 0.5), 0.0) * 0.3
    x = dsp.ladder(x, 220.0 * (1.0 + 0.3 * dsp.lfo(n, 0.25)), 1.3, 1.6)
    x += dsp.sine(f) * 0.6
    env = fit(dsp.adsr(int(end * SR), 0.4, 1.0, 0.9, tail, curve=3.0), n)
    return x * env


def kick(rng, deep=False):
    """Bombo sintetico: seno con caida de altura + clic filtrado."""
    dur = 0.9 if deep else 0.45
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 42.0 + (170.0 if not deep else 120.0) * np.exp(-t / (0.035 if not deep else 0.08))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * dsp.perc(n, 0.22 if not deep else 0.5, attack=0.001)
    click = dsp.bandpass(dsp.white(n, rng), 3200.0, 1.2) * dsp.perc(n, 0.006, attack=0.0005) * 0.5
    return dsp.saturate(body + click, 1.6)


# ------------------------------------------------------- capa 3: texturas

def drone(n, rng, level):
    """Zumbido del reactor por sintesis aditiva: parciales de A1 con batidos
    lentos; cada parcial respira con su propia deriva aleatoria."""
    L = np.zeros(n)
    R = np.zeros(n)
    base = 55.0
    partials = [(1, 0.55), (2, 0.5), (3, 0.32), (4, 0.18), (5, 0.12), (6, 0.08),
                (7, 0.05), (8, 0.04), (9.02, 0.03), (12, 0.025), (15.03, 0.015)]
    for k, (h, a) in enumerate(partials):
        amp = a * (0.6 + 0.4 * dsp.smooth_random(n, 0.08 + 0.03 * k, rng))
        f = base * h * (1.0 + 0.0009 * dsp.smooth_random(n, 0.05, rng))
        s = dsp.sine(np.full(n, 1.0) * f, rng.uniform()) * amp
        l, r = dsp.pan(s, (k % 3 - 1) * 0.35)
        L += l
        R += r
    return L * level * 0.16, R * level * 0.16


def air(n, rng, level, center):
    """Ventilacion: ruido rosa por un pasabanda que barre (estereo decorrelado)."""
    out = []
    for ch in range(2):
        x = dsp.pink(n, rng)
        c = center * (1.0 + 0.35 * dsp.smooth_random(n, 0.15, rng))
        out.append(dsp.bandpass(x, c, 1.6) * level * 0.08)
    return out[0], out[1]


def grain_source(rng):
    """Material para la nube granular: una campana FM larga en A4."""
    n = int(1.2 * SR)
    f = np.full(n, 440.0)
    x = dsp.fm(f, 1.4, 2.2 * dsp.perc(n, 0.6)) + 0.4 * dsp.fm(f * 2, 3.01, 0.8)
    return x * dsp.perc(n, 0.9, attack=0.01)


def grains(n, rng, density, pitches, shift, glen, level):
    """Sintesis granular: miles de fragmentos (ventana Hann) de una campana,
    transpuestos a las alturas de `pitches`. `shift` (array) es el factor de
    afinacion global: en el horizonte baja hacia 0.5 (corrimiento al rojo) y
    los granos se estiran."""
    src = grain_source(rng)
    L = np.zeros(n)
    R = np.zeros(n)
    t = 0.0
    T = n / SR
    while t < T:
        i = int(t * SR)
        d = density[min(i, n - 1)]
        if d <= 0.01:
            t += 0.05
            continue
        t += rng.exponential(1.0 / d)
        i = int(t * SR)
        if i >= n:
            break
        g = glen[i] * rng.uniform(0.6, 1.4)
        gn = int(g * SR)
        if gn < 64 or i + gn >= n:
            continue
        p = pitches[rng.integers(len(pitches))]
        ratio = 2.0 ** ((p - 69) / 12.0) * shift[i]
        pos0 = rng.uniform(0.02, 0.5) * SR
        idx = pos0 + np.arange(gn) * ratio
        idx = idx[idx < len(src) - 1]
        gn = len(idx)
        w = np.hanning(gn)
        grain = np.interp(idx, np.arange(len(src)), src) * w
        l, r = dsp.pan(grain, rng.uniform(-0.85, 0.85))
        a = level[i] * rng.uniform(0.4, 1.0)
        L[i:i + gn] += l * a
        R[i:i + gn] += r * a
    return L * 0.12, R * 0.12


def tick(rng, kind=0):
    """Rele / clic metalico de la instalacion (ruido + FM inarmonica)."""
    n = int(0.06 * SR)
    f0 = [6100.0, 4300.0, 8800.0][kind % 3]
    x = dsp.bandpass(dsp.white(n, rng), f0, 3.0) * dsp.perc(n, 0.008, attack=0.0003)
    x += dsp.fm(np.full(n, f0 * 0.31), 2.71, 3.0) * dsp.perc(n, 0.004, attack=0.0003) * 0.3
    return x


def horizon_sweep(dur, rng, f0=2400.0, f1=40.0):
    """Barrido del horizonte de sucesos: ruido y seno cayendo juntos por un
    filtro resonante que se cierra (la espaguetificacion de la senal)."""
    n = int(dur * SR)
    u = np.linspace(0, 1, n)
    fc = f0 * (f1 / f0) ** (u ** 0.8)
    nz = dsp.svf(dsp.pink(n, rng), fc, 6.0, 1) * 0.5
    tone = dsp.sine(fc * 0.5) * 0.35
    env = np.sin(np.pi * u) ** 0.7
    x = (nz + tone) * env
    L, R = dsp.pan(x, dsp.lfo(n, 0.5) * 0.7)
    return L, R


def sub_fall(dur, f0=110.0, f1=27.5):
    """Caida del sub: el fondo del pozo gravitatorio."""
    n = int(dur * SR)
    u = np.linspace(0, 1, n)
    f = f0 * (f1 / f0) ** u
    env = np.minimum(u * 8, 1) * (1 - u) ** 1.5
    return dsp.sine(f) * env
