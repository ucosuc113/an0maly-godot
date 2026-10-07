"""Capa 0: primitivas DSP (muestra a muestra, compiladas con numba).

Todo lo que hay aca trabaja sobre arrays de numpy y no sabe nada de musica:
osciladores sin aliasing, filtros, envolventes, lineas de retardo, reverb,
dinamica. Las capas de arriba (instrumentos, partitura, mezcla) solo combinan
estas piezas.

Convencion: las frecuencias y cortes llegan como arrays (una por muestra) para
que cualquier parametro se pueda modular sin casos especiales.
"""
import numpy as np
from numba import njit

SR = 44100


# ---------------------------------------------------------------- osciladores

@njit(cache=True)
def _blep(t, dt):
    # Correccion PolyBLEP: suaviza el salto de una onda ideal para que no
    # genere armonicos por encima de Nyquist (aliasing).
    if t < dt:
        t /= dt
        return t + t - t * t - 1.0
    if t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


@njit(cache=True)
def saw(freq, phase0):
    n = freq.shape[0]
    out = np.empty(n)
    p = phase0
    for i in range(n):
        dt = freq[i] / SR
        out[i] = 2.0 * p - 1.0 - _blep(p, dt)
        p += dt
        if p >= 1.0:
            p -= 1.0
    return out


@njit(cache=True)
def pulse(freq, width, phase0):
    # Cuadrada de ancho variable (PWM): dos saltos por ciclo, dos BLEPs.
    n = freq.shape[0]
    out = np.empty(n)
    p = phase0
    for i in range(n):
        dt = freq[i] / SR
        w = width[i]
        v = 1.0 if p < w else -1.0
        v += _blep(p, dt)
        q = p - w
        if q < 0.0:
            q += 1.0
        v -= _blep(q, dt)
        out[i] = v
        p += dt
        if p >= 1.0:
            p -= 1.0
    return out


def phase_of(freq, phase0=0.0):
    """Fase acumulada (en ciclos) de una frecuencia variable."""
    return phase0 + np.cumsum(freq) / SR


def sine(freq, phase0=0.0):
    return np.sin(2.0 * np.pi * phase_of(freq, phase0))


def fm(freq, ratio, index, fb=0.0, phase0=0.0):
    """Par de operadores FM (fase-modulacion): portadora a `freq`, moduladora a
    `freq*ratio` con profundidad `index` (array o escalar). `fb` realimenta la
    moduladora sobre si misma (aproximado) para sumar aspereza."""
    pm = 2.0 * np.pi * phase_of(freq * ratio, phase0 * 0.37)
    mod = np.sin(pm + fb * np.sin(pm))
    return np.sin(2.0 * np.pi * phase_of(freq, phase0) + index * mod)


def midi_hz(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=np.float64) - 69.0) / 12.0)


# -------------------------------------------------------------------- filtros

@njit(cache=True)
def svf(x, cutoff, q, mode):
    """Filtro de estado variable TPT (topologia de Zavalishin / Cytomic):
    estable con el corte modulado a velocidad de audio.
    mode: 0 pasabajos, 1 pasabanda, 2 pasaaltos, 3 notch."""
    n = x.shape[0]
    out = np.empty(n)
    ic1 = 0.0
    ic2 = 0.0
    k = 1.0 / q
    for i in range(n):
        fc = cutoff[i]
        if fc < 10.0:
            fc = 10.0
        if fc > SR * 0.45:
            fc = SR * 0.45
        g = np.tan(np.pi * fc / SR)
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
        v3 = x[i] - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if mode == 0:
            out[i] = v2
        elif mode == 1:
            out[i] = v1
        elif mode == 2:
            out[i] = x[i] - k * v1 - v2
        else:
            out[i] = x[i] - k * v1
    return out


def lowpass(x, cutoff, q=0.707):
    return svf(x, _arr(cutoff, len(x)), q, 0)


def bandpass(x, cutoff, q=1.0):
    return svf(x, _arr(cutoff, len(x)), q, 1)


def highpass(x, cutoff, q=0.707):
    return svf(x, _arr(cutoff, len(x)), q, 2)


def ladder(x, cutoff, q=0.9, drive=1.0):
    """Pasabajos de 24 dB/oct: dos SVF en cascada con saturacion entre medio
    (el caracter "analogico" sale de la tanh)."""
    c = _arr(cutoff, len(x))
    y = svf(np.tanh(x * drive), c, q, 0)
    return svf(np.tanh(y), c, 0.6, 0)


@njit(cache=True)
def onepole(x, coef):
    # Pasabajos de un polo; coef = exp(-2*pi*fc/SR).
    out = np.empty_like(x)
    z = 0.0
    for i in range(x.shape[0]):
        z = x[i] + coef * (z - x[i])
        out[i] = z
    return out


def onepole_lp(x, fc):
    return onepole(x, np.exp(-2.0 * np.pi * fc / SR))


def onepole_hp(x, fc):
    return x - onepole_lp(x, fc)


def _arr(v, n):
    if np.isscalar(v):
        return np.full(n, float(v))
    return np.ascontiguousarray(v, dtype=np.float64)


# ---------------------------------------------------------------- envolventes

def adsr(n_hold, a, d, s, r, curve=4.0):
    """Envolvente ADSR con segmentos exponenciales. `n_hold` es la duracion de
    la nota (muestras) hasta el note-off; devuelve n_hold + release muestras."""
    na, nd, nr = max(1, int(a * SR)), max(1, int(d * SR)), max(1, int(r * SR))
    env = np.empty(n_hold + nr)
    t = np.arange(n_hold, dtype=np.float64)
    att = 1.0 - np.exp(-curve * t / na)
    att /= (1.0 - np.exp(-curve))
    dec = s + (1.0 - s) * np.exp(-curve * (t - na) / nd)
    body = np.where(t < na, np.minimum(att, 1.0), dec)
    env[:n_hold] = body
    last = body[-1] if n_hold > 0 else 0.0
    env[n_hold:] = last * np.exp(-curve * np.arange(nr) / nr)
    return env


def perc(n, decay, curve=1.0, attack=0.002):
    """Envolvente percusiva: ataque corto y caida exponencial de `decay` s."""
    t = np.arange(n) / SR
    a = np.minimum(t / attack, 1.0)
    return a * np.exp(-t / decay) ** curve


def automation(points, n):
    """Curva de automatizacion: [(segundos, valor), ...] interpolada lineal."""
    ts = np.array([p[0] for p in points]) * SR
    vs = np.array([p[1] for p in points], dtype=np.float64)
    return np.interp(np.arange(n), ts, vs)


# --------------------------------------------------------------- ruido / lfo

def white(n, rng):
    return rng.standard_normal(n)


def pink(n, rng):
    """Ruido rosa (-3 dB/oct) por filtrado espectral del blanco."""
    w = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = f[1]
    w /= np.sqrt(f)
    p = np.fft.irfft(w, n)
    return p / (np.std(p) + 1e-12)


def lfo(n, rate, phase=0.0, shape="sine"):
    t = np.arange(n) / SR
    ph = rate * t + phase
    if shape == "tri":
        return 4.0 * np.abs(ph - np.floor(ph + 0.5)) - 1.0
    return np.sin(2.0 * np.pi * ph)


def smooth_random(n, rate, rng):
    """Deriva aleatoria suave (ruido de valor interpolado coseno) en [-1, 1]."""
    k = int(n * rate / SR) + 3
    pts = rng.uniform(-1.0, 1.0, k)
    x = np.arange(n) * rate / SR
    i = np.floor(x).astype(np.int64)
    f = x - i
    f = (1.0 - np.cos(np.pi * f)) * 0.5
    return pts[i] * (1.0 - f) + pts[i + 1] * f


# --------------------------------------------------------------- distorsiones

def bitcrush(x, bits=10, hold=2):
    """Reduce resolucion y frecuencia de muestreo (sample & hold)."""
    q = 2.0 ** (bits - 1)
    y = np.round(x * q) / q
    if hold > 1:
        idx = (np.arange(len(y)) // hold) * hold
        y = y[idx]
    return y


def saturate(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


# ----------------------------------------------------------------- retardos

@njit(cache=True)
def _frac_delay(x, delay_samples):
    # Linea de retardo de lectura fraccionaria (interpolacion cubica Hermite).
    n = x.shape[0]
    out = np.zeros(n)
    for i in range(n):
        d = delay_samples[i]
        pos = i - d
        j = int(np.floor(pos))
        f = pos - j
        if j - 1 < 0 or j + 2 >= n:
            continue
        y0, y1, y2, y3 = x[j - 1], x[j], x[j + 1], x[j + 2]
        c1 = 0.5 * (y2 - y0)
        c2 = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3
        c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
        out[i] = ((c3 * f + c2) * f + c1) * f + y1
    return out


def chorus(x, depth_ms=6.0, rate=0.35, base_ms=14.0, voices=3, mix=0.5):
    """Chorus estereo: varias copias con retardo modulado. Devuelve (L, R)."""
    n = len(x)
    L = np.zeros(n)
    R = np.zeros(n)
    for v in range(voices):
        for ch, out in ((0, L), (1, R)):
            ph = v / voices + ch * 0.25
            d = (base_ms + depth_ms * 0.5 * (1 + lfo(n, rate * (1 + 0.13 * v), ph))) * SR / 1000.0
            out += _frac_delay(x, d)
    wet = 1.0 / voices
    return x * (1 - mix) + L * wet * mix, x * (1 - mix) + R * wet * mix


@njit(cache=True)
def _pingpong(L, R, d, fb, coef):
    n = L.shape[0]
    bl = np.zeros(n)
    br = np.zeros(n)
    zl = 0.0
    zr = 0.0
    for i in range(n):
        il = L[i]
        ir = R[i]
        if i >= d:
            # El eco de la izquierda vuelve por la derecha y viceversa,
            # oscureciendose en cada pasada.
            zl = br[i - d] + coef * (zl - br[i - d])
            zr = bl[i - d] + coef * (zr - bl[i - d])
            bl[i] = (il + ir) * 0.5 + fb * zl
            br[i] = fb * zr
        else:
            bl[i] = (il + ir) * 0.5
            br[i] = 0.0
    return bl, br


def pingpong(L, R, delay_s, fb=0.45, damp_hz=3500.0):
    d = int(delay_s * SR)
    coef = np.exp(-2.0 * np.pi * damp_hz / SR)
    bl, br = _pingpong(np.ascontiguousarray(L), np.ascontiguousarray(R), d, fb, coef)
    # La salida es el buffer retrasado (solo el eco).
    wl = np.zeros_like(bl)
    wr = np.zeros_like(br)
    wl[d:] = bl[:-d]
    wr[d:] = br[:-d]
    return wl, wr


# ------------------------------------------------------------------- reverb

@njit(cache=True)
def _fdn(x, lengths, g, coef, mod_depth):
    # Red de retardos realimentada (FDN) de 8 lineas con matriz de Hadamard:
    # cada linea mezcla con todas sin perder energia; un pasabajos en cada
    # realimentacion hace que los agudos mueran antes (aire de nave grande).
    n = x.shape[0]
    N = 8
    maxlen = 0
    for k in range(N):
        if lengths[k] > maxlen:
            maxlen = lengths[k]
    size = maxlen + 64
    buf = np.zeros((N, size))
    w = np.zeros(N)
    lp = np.zeros(N)
    outL = np.zeros(n)
    outR = np.zeros(n)
    pos = 0
    for i in range(n):
        # Lectura (dos lineas con modulacion lenta para que no suene metalico).
        for k in range(N):
            L = lengths[k]
            if k < 2:
                L = L + int(mod_depth * np.sin(2.0 * np.pi * (0.31 + 0.17 * k) * i / SR))
            idx = pos - L
            if idx < 0:
                idx += size
            v = buf[k, idx]
            lp[k] = v + coef * (lp[k] - v)
            w[k] = lp[k]
        # Hadamard 8x8 rapido (normalizado).
        h = 1
        while h < N:
            for a in range(0, N, h * 2):
                for b in range(a, a + h):
                    u = w[b]
                    v = w[b + h]
                    w[b] = u + v
                    w[b + h] = u - v
            h *= 2
        s = 0.35355339059327373 * g
        for k in range(N):
            buf[k, pos] = x[i] + w[k] * s
        outL[i] = lp[0] - lp[2] + lp[4] - lp[6]
        outR[i] = lp[1] - lp[3] + lp[5] - lp[7]
        pos += 1
        if pos >= size:
            pos = 0
    return outL, outR


def reverb(L, R, size=1.0, decay=0.86, damp_hz=5000.0, predelay=0.02, mod=8.0):
    """Reverb FDN estereo. Devuelve solo la senal humeda (L, R)."""
    base = np.array([1123, 1361, 1559, 1747, 1949, 2129, 2357, 2557])
    lengths = (base * size).astype(np.int64)
    coef = np.exp(-2.0 * np.pi * damp_hz / SR)
    mono = (np.asarray(L) + np.asarray(R)) * 0.5
    pd = int(predelay * SR)
    x = np.zeros(len(mono))
    x[pd:] = mono[:len(mono) - pd]
    wl, wr = _fdn(x, lengths, decay, coef, mod)
    return wl * 0.3, wr * 0.3


# ---------------------------------------------------------------- dinamica

@njit(cache=True)
def _follow(x, att, rel):
    n = x.shape[0]
    out = np.empty(n)
    e = 0.0
    for i in range(n):
        v = abs(x[i])
        c = att if v > e else rel
        e = v + c * (e - v)
        out[i] = e
    return out


def envelope_follower(x, attack=0.005, release=0.12):
    return _follow(np.ascontiguousarray(x), np.exp(-1.0 / (attack * SR)),
                   np.exp(-1.0 / (release * SR)))


def compressor(L, R, threshold_db=-18.0, ratio=3.0, attack=0.01, release=0.2,
               knee_db=6.0, makeup_db=0.0, key=None):
    """Compresor estereo enlazado. `key` permite sidechain externo."""
    det = np.maximum(np.abs(L), np.abs(R)) if key is None else np.abs(key)
    env = envelope_follower(det, attack, release)
    lvl = 20.0 * np.log10(env + 1e-9)
    over = lvl - threshold_db
    # Rodilla suave.
    gr = np.where(over <= -knee_db / 2, 0.0,
                  np.where(over >= knee_db / 2, over * (1 - 1 / ratio),
                           (1 - 1 / ratio) * (over + knee_db / 2) ** 2 / (2 * knee_db)))
    g = 10.0 ** ((makeup_db - gr) / 20.0)
    return L * g, R * g


@njit(cache=True)
def _limit(peak, look, rel):
    n = peak.shape[0]
    g = np.ones(n)
    # Ganancia necesaria con anticipacion: el minimo en la ventana futura.
    need = np.empty(n)
    for i in range(n):
        need[i] = 1.0 / peak[i] if peak[i] > 1.0 else 1.0
    cur = 1.0
    for i in range(n):
        m = 1.0
        j_end = i + look
        if j_end > n:
            j_end = n
        for j in range(i, j_end):
            if need[j] < m:
                m = need[j]
        if m < cur:
            cur = m
        else:
            cur = m + rel * (cur - m)
        g[i] = cur
    return g


def limiter(L, R, ceiling_db=-1.0, lookahead=0.004, release=0.08):
    c = 10.0 ** (ceiling_db / 20.0)
    peak = np.maximum(np.abs(L), np.abs(R)) / c
    look = int(lookahead * SR)
    g = _limit(np.ascontiguousarray(peak), look, np.exp(-1.0 / (release * SR)))
    # Suaviza la curva de ganancia para que no module en audio.
    g = np.minimum(g, onepole(g, np.exp(-1.0 / (0.001 * SR))))
    return L * g, R * g


# ------------------------------------------------------------------- estereo

def pan(x, p):
    """Paneo de potencia constante, p en [-1, 1] (escalar o array)."""
    a = (np.asarray(p) + 1.0) * np.pi / 4.0
    return x * np.cos(a), x * np.sin(a)


# ------------------------------------------------------------ edicion glitch

def _fade_edges(x, k):
    k = min(k, len(x) // 2)
    if k > 0:
        r = np.linspace(0, 1, k)
        x[:k] *= r
        x[-k:] *= r[::-1]
    return x


def beat_repeat(L, R, t, slice_s, total_s, roll=True):
    """Repetidor de compas (el "tartamudeo" del secuenciador de Portal 2):
    toma `slice_s` desde `t` y lo repite hasta llenar `total_s`. Con `roll`,
    la segunda mitad repite trozos cada vez mas cortos (se acelera)."""
    i0 = int(t * SR)
    end = min(len(L), i0 + int(total_s * SR))
    s = int(slice_s * SR)
    srcL = L[i0:i0 + s].copy()
    srcR = R[i0:i0 + s].copy()
    i = i0
    k = 0
    while i < end:
        cur = s
        if roll and i - i0 > (end - i0) * 0.5:
            cur = max(int(s / 2 ** (1 + k // 2)), int(0.012 * SR))
            k += 1
        a = _fade_edges(srcL[:cur].copy(), 64)
        b = _fade_edges(srcR[:cur].copy(), 64)
        m = min(cur, end - i)
        L[i:i + m] = a[:m]
        R[i:i + m] = b[:m]
        i += cur
    return L, R


def tape_stop(L, R, t0, dur, curve=1.6):
    """Freno de cinta: la velocidad cae a cero en `dur` segundos (todo baja de
    altura y se arrastra) y despues silencio."""
    i0 = int(t0 * SR)
    n = min(int(dur * SR), len(L) - i0)
    rate = (1.0 - np.linspace(0, 1, n)) ** curve
    pos = i0 + np.cumsum(rate)
    idx = np.arange(len(L))
    outL, outR = L.copy(), R.copy()
    fade = np.linspace(1, 0, n) ** 0.5
    outL[i0:i0 + n] = np.interp(pos, idx, L) * fade
    outR[i0:i0 + n] = np.interp(pos, idx, R) * fade
    outL[i0 + n:] = 0.0
    outR[i0 + n:] = 0.0
    return outL, outR


def gate_curve(n, t0, step_s, pattern, depth, smooth_ms=4.0):
    """Compuerta ritmica (trance gate): 1/0 por paso, suavizada."""
    g = np.ones(n)
    i = int(t0 * SR)
    s = step_s * SR
    k = 0
    while i < n:
        j = int(int(t0 * SR) + (k + 1) * s)
        if not pattern[k % len(pattern)]:
            g[i:min(j, n)] = 1.0 - depth
        i = j
        k += 1
    return onepole(g, np.exp(-1.0 / (smooth_ms * 0.001 * SR)))
