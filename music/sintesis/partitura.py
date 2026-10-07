"""Capa 4: la composicion. Forma, armonia y donde suena cada leitmotiv.

Lenguaje Portal 2: celulas cortas en ostinato, compas de 7/8 (2+2+3), proceso
aditivo, armonia octatonica sin cadencias, cortes glitch y un final por
colapso (freno de cinta), no por resolucion.

Semicorchea = 0.125 s (negra = 120). Compas de 7/8 = 14 semicorcheas =
1.75 s. 32 compases = 56 s + 4 s de reinicio y cola = 60 s.

Armonia: solo triadas menores sobre A, C, D#, F# (las cuatro rotaciones por
terceras menores de la escala octatonica) y el acorde ANOMALIA {A E A# D#}.
Nada de IV-V-I ni de bajos de lamento: el movimiento es por terceras menores
y tritonos, que no "resuelven" nunca.

Forma (compases):
    1  1-4    ARRANQUE    proceso aditivo: la celula I se arma nota por nota.
    2  5-12   PRUEBA      bateria en 2+2+3; I como frase; sombra de tritono.
    3  13-20  ESCALADA    el bajo sube por terceras menores A-C-D#-F#; I en
                          cada rotacion, respondido por su reflejo (II latente).
    4  21-26  HORIZONTE   todo se curva hacia abajo (un semitono en 6 compases);
                          II en espiral; el secuenciador se dilata.
    5  27-30  COLAPSO     Am <-> D#m cada compas; I en disminucion (panico)
                          sobre II grave; tartamudeos.
    6  31-32  APAGADO     freno de cinta, silencio, reinicio: A E A#... y la
                          D# no llega.
"""
import numpy as np

from . import dsp, instrumentos as ins
from .dsp import SR
from .leitmotivs import INSTALACION, AGUJERO, ANOMALIA, Motif, n

S16 = 0.125
BAR = 14 * S16
NBARS = 32
TOTAL = 60.0
SECS = "1111" + "22222222" + "33333333" + "444444" + "5555" + "66"
SEC_NAMES = {"1": "ARRANQUE", "2": "PRUEBA", "3": "ESCALADA", "4": "HORIZONTE",
             "5": "COLAPSO", "6": "APAGADO"}


def bar_t(b, step=0):
    return (b - 1) * BAR + step * S16


def section(b):
    return SECS[min(b, NBARS) - 1]


# Freno de cinta a mitad del compas 31; el reinicio llega despues del silencio.
STOP_T = bar_t(31, 7)
STOP_DUR = 1.7
REBOOT_T = STOP_T + STOP_DUR + 1.0

# ------------------------------------------------------------------ armonia

ROOT = {"A": 57, "C": 60, "D#": 51, "F#": 54}          # registro del colchon
BASS = {"A": n("A1"), "C": n("C2"), "D#": n("D#2"), "F#": n("F#2")}

# (raiz, calidad, raiz del bajo) por compas. "m" triada menor, "X" anomalia.
HARM = ([("A", "m", "A")] * 4 +
        [("A", "m", "A"), ("A", "m", "A"), ("C", "m", "A"), ("A", "m", "A"),
         ("A", "m", "A"), ("A", "m", "A"), ("C", "m", "A"), ("D#", "m", "A")] +
        [("A", "m", "A"), ("A", "m", "A"), ("C", "m", "C"), ("C", "m", "C"),
         ("D#", "m", "D#"), ("D#", "m", "D#"), ("F#", "m", "F#"), ("F#", "m", "F#")] +
        [("A", "X", "A")] * 6 +
        [("A", "m", "A"), ("D#", "m", "A"), ("A", "m", "A"), ("D#", "m", "A")] +
        [("A", "X", "A")] * 2)

PROG = [(f"{r}m" if q == "m" else f"{r}*") + (f"/{b}" if b != r else "") for r, q, b in HARM]


def pad_voicing(b):
    r, q, _ = HARM[b - 1]
    rm = ROOT[r]
    if q == "X":
        return [rm + i for i in ANOMALIA]
    return [rm, rm + 7, rm + 12, rm + 15]


def cell_notes(b, octave=1):
    """Las 4 notas de la celula I sobre la raiz del compas."""
    r = HARM[b - 1][0]
    return [ROOT[r] + 12 * octave + i for i in ANOMALIA]


def global_bend(t):
    """El horizonte: todo se curva un semitono hacia abajo en la seccion 4."""
    t = np.asarray(t, dtype=np.float64)
    a, b = bar_t(21), bar_t(27)
    u = np.clip((t - a) / (b - a), 0.0, 1.0)
    return np.where((t >= a) & (t < b), -1.0 * u ** 1.4, 0.0)


def bend_curve(t0, dur):
    return global_bend(t0 + np.arange(int((dur + 4.0) * SR)) / SR)


# Ostinato de 14 pasos: celula, celula, celula + vuelta (4+4+6 = 2+2+3).
ARP = [0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 2, 1]
ACC = [1, .4, .6, .5, .9, .4, .6, .5, 1, .4, .6, .5, .7, .5]
GATE = [1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1]


# ------------------------------------------------------------------ melodia

def melodia(rng):
    bus = ins.Bus(TOTAL, "melodia")

    def play_I(motif, t, vel=1.0, bits=7, bright=1.0):
        for m, d in motif.notes:
            L, R = ins.aperture_lead(m, d * S16 * 0.95, rng, vel=vel, bits=bits,
                                     bend=float(global_bend(t)), bright=bright)
            bus.add(t, L, R)
            t += d * S16
        return t

    def play_II(motif, b, gain=1.0, bright=1.0, redshift=-0.8):
        t, ev = 0.0, []
        for m, d in motif.notes:
            ev.append((t, m))
            t += d * S16
        L, R = ins.singularity_lead(ev, t, rng, redshift=redshift, bright=bright,
                                    bend=bend_curve(bar_t(b), t))
        bus.add(bar_t(b), L, R, gain)

    # 2 PRUEBA. Frase A (c.9-10): I, I rotado a C, y la D#6 que se traba y cae
    # un tritono a A#5. Frase B (c.11-12): I y su sombra a un tritono (D#).
    traba = Motif([(n("D#6"), 1)] * 3 + [(n("A#5"), 11)])
    play_I(INSTALACION + INSTALACION.transpose(3) + traba, bar_t(9))
    traba2 = Motif([(n("A6"), 1)] * 3 + [(n("D#6"), 11)])
    play_I(INSTALACION + INSTALACION.transpose(6) + traba2, bar_t(11))

    # 3 ESCALADA. Cada dos compases: I dos veces sobre la raiz nueva y su
    # reflejo descendente (la retrogradacion: II asomando dentro de la maquina).
    for k, b in enumerate((13, 15, 17, 19)):
        r = HARM[b - 1][0]
        cell = INSTALACION.transpose(ROOT[r] + 12 - n("A4"))
        refl = cell.retrograde().rhythm([2, 2, 1, 2])
        t = play_I(cell + cell, bar_t(b), vel=0.9 + 0.05 * k)
        t = play_I(refl, t, vel=0.75, bright=0.7)
        play_I(Motif([(refl.notes[-1][0], 7)]), t, vel=0.5, bright=0.5)

    # 4 HORIZONTE. II en espiral: dos veces, la segunda un semitono abajo.
    play_II(AGUJERO, 21, gain=0.9)
    play_II(AGUJERO.transpose(-1), 24, gain=0.9, redshift=-1.3)

    # 5 COLAPSO. I en disminucion (semicorcheas parejas), alternando A y D#,
    # sobre II una octava abajo.
    for b in range(27, 31):
        cell = INSTALACION.rhythm([1, 1, 1, 1]).transpose(ROOT[HARM[b - 1][0]] + 12 - n("A4"))
        pat = cell + cell + cell + Motif([(cell.notes[-1][0], 1)] * 2)
        play_I(pat, bar_t(b), vel=0.85, bits=6)
    play_II(AGUJERO.octave(-1), 27, gain=0.85, bright=0.8, redshift=-2.0)

    # 6 APAGADO: la D#6 sostenida hasta que la cinta frena.
    play_I(Motif([(n("A5"), 3), (n("A#5"), 3), (n("D#6"), 20)]), bar_t(31), vel=0.9, bits=6)
    return bus


def reinicio(rng):
    """Despues del freno: la celula intenta arrancar y no llega a la D#."""
    bus = ins.Bus(TOTAL, "reinicio")
    t = REBOOT_T
    for m, d in INSTALACION.head(3).augment(2).notes:
        L, R = ins.aperture_lead(m, d * S16 * 0.9, rng, vel=0.55, bits=5, bright=0.6)
        bus.add(t, L, R)
        t += d * S16
    x = ins.bleep(n("D#7"), 0.05, rng)
    bus.add(t + 0.35, x, x, 0.12)
    return bus


# ------------------------------------------------------------ acompanamiento

def acompanamiento(rng):
    bus = ins.Bus(TOTAL, "acompanamiento")
    N = bus.n
    kick_env = np.zeros(N)

    # Colchon: ligado mientras el acorde no cambia.
    pad = ins.Bus(TOTAL, "pad")
    b = 3
    while b <= NBARS:
        e = b
        while e + 1 <= NBARS and HARM[e] == HARM[b - 1] and section(e + 1) == section(b):
            e += 1
        dur = (e - b + 1) * BAR
        sec = section(b)
        cut = {"1": 600.0, "2": 1300.0, "3": 1900.0, "4": 900.0, "5": 2200.0, "6": 1600.0}[sec]
        L, R = ins.pad_chord(pad_voicing(b), dur, rng, cutoff=cut,
                             bend=bend_curve(bar_t(b), dur))
        pad.add(bar_t(b), L, R, 0.55 if sec == "1" else 0.8)
        b = e + 1
    # Compuerta ritmica en PRUEBA, ESCALADA y COLAPSO.
    g = np.ones(N)
    for b in range(5, 31):
        if section(b) in "235":
            i0, i1 = int(bar_t(b) * SR), int(bar_t(b + 1) * SR)
            depth = {"2": 0.55, "3": 0.75, "5": 0.85}[section(b)]
            g[i0:i1] = dsp.gate_curve(N, bar_t(b), S16, GATE, depth)[i0:i1]
    bus.add(0, pad.L * g, pad.R * g)

    # Secuenciador.
    seq = ins.Bus(TOTAL, "seq")
    for b in range(1, 31):
        sec = section(b)
        if sec == "4":
            continue
        notes = cell_notes(b, octave=0 if sec == "1" else 1)
        for s in range(14):
            idx = ARP[s]
            if sec == "1" and idx > b - 1:          # proceso aditivo
                continue
            if (b in (12, 20) and s >= 10) or (sec == "5" and s >= 12):
                for r in range(2):                  # ratchet
                    x = ins.arp_note(notes[idx], S16 / 2, rng, accent=0.8, bits=7)
                    seq.add(bar_t(b, s) + r * S16 / 2, *dsp.pan(x, (-1) ** r * 0.6))
                continue
            x = ins.arp_note(notes[idx], S16, rng, accent=ACC[s], bits=8 if sec == "5" else 9)
            seq.add(bar_t(b, s), *dsp.pan(x, -0.3 if s % 2 else 0.3),
                    gain=0.8 if sec == "1" else 1.0)

    # 4 HORIZONTE: dilatacion. Cada paso dura un 4% mas que el anterior y
    # todo se curva hacia abajo con el resto.
    t, k, d = bar_t(21), 0, S16
    while t < bar_t(27) - 0.1:
        b = 21 + int((t - bar_t(21)) / BAR)
        u = (t - bar_t(21)) / (6 * BAR)
        notes = cell_notes(b, octave=1)
        x = ins.arp_note(notes[ARP[k % 14]], min(d, 0.45), rng,
                         accent=ACC[k % 14] * (1 - 0.6 * u), bend=float(global_bend(t)))
        seq.add(t, *dsp.pan(x, -0.5 if k % 2 else 0.5), gain=0.8)
        t += d
        d *= 1.04
        k += 1

    wl, wr = dsp.pingpong(seq.L, seq.R, 3 * S16, fb=0.38, damp_hz=3000.0)
    bus.add(0, seq.L + wl * 0.4, seq.R + wr * 0.4, 0.95)

    # Pitidos en polimetro: periodo de 5 contra el compas de 14 (se desfasan).
    for b in range(13, 31):
        if section(b) not in "35":
            continue
        for s in range(14):
            step = (b - 13) * 14 + s
            if step % 5 == 0:
                m = cell_notes(b, octave=2)[(step // 5) % 4]
                x = ins.bleep(m, 0.08, rng)
                bus.add(bar_t(b, s), *dsp.pan(x, 0.6 if (step // 5) % 2 else -0.6), gain=0.12)

    # Bajo.
    low = ins.Bus(TOTAL, "bajo")
    PAT2 = [(0, 0), (2, 0), (4, 12), (6, 0), (8, 7), (10, 0), (12, 13)]
    PAT5 = [0, 0, 12, 0, 0, 12, 0, 13, 0, 0, 12, 0, 18, 12]
    for b in range(7, 31):
        sec = section(b)
        root = BASS[HARM[b - 1][2]]
        if sec in "23":
            for s, st in PAT2:
                x = ins.dist_bass(root + st, S16 * 1.8, rng)
                low.add(bar_t(b, s), x, x, 0.9 if s % 4 else 1.0)
        elif sec == "5":
            for s in range(14):
                x = ins.dist_bass(root + PAT5[s], S16 * 0.9, rng)
                low.add(bar_t(b, s), x, x, 0.85)
    # HORIZONTE: un solo A grave que se curva con todo lo demas.
    dur = 6 * BAR
    env = dsp.adsr(int(dur * SR), 0.6, 1.0, 0.9, 1.5)
    f = dsp.midi_hz(n("A1") + ins.fit(bend_curve(bar_t(21), dur), len(env)))
    sub = dsp.sine(f) + 0.3 * dsp.lowpass(dsp.saw(f, 0.0), 240.0, 1.2)
    low.add(bar_t(21), sub * env, sub * env, 0.9)

    # Bateria (2+2+3).
    drums = ins.Bus(TOTAL, "bateria")

    def hit(sig, t, p=0.0, gain=1.0, kick=False):
        drums.add(t, *dsp.pan(sig, p), gain=gain)
        if kick:
            i = int(t * SR)
            k = min(len(sig), N - i)
            kick_env[i:i + k] += np.abs(sig[:k])

    for b in range(5, 31):
        sec = section(b)
        if sec == "4":
            if b % 2 == 1:
                hit(ins.kick(rng, deep=True), bar_t(b), kick=True)
            continue
        if sec == "2" and b < 7:
            for s in range(0, 14, 2):
                hit(ins.hat(rng, vel=0.6), bar_t(b, s), 0.3)
            continue
        kicks = {"2": [0, 8], "3": [0, 8, 10], "5": [0, 3, 8, 10]}[sec]
        snares = {"2": [4, 11], "3": [4, 11], "5": [4, 11, 13]}[sec]
        for s in kicks:
            hit(ins.kick(rng), bar_t(b, s), kick=True)
        for s in snares:
            hit(ins.snare(rng, vel=0.6 if s == 13 else 1.0), bar_t(b, s), -0.05)
        for s in range(14):
            if sec == "5" or s % 2 == 0:
                hit(ins.hat(rng, open_=(s == 6), vel=1.0 if s % 2 == 0 else 0.55),
                    bar_t(b, s), 0.35)
            if rng.uniform() < (0.12 if sec != "5" else 0.25) and s % 2 == 1:
                hit(ins.clank(rng), bar_t(b, s), rng.uniform(-0.7, 0.7), 0.5)

    # Sidechain: el bombo hace bombear colchon, bajo y secuenciador.
    duck = dsp.envelope_follower(kick_env, 0.002, 0.16)
    duck = 1.0 - 0.6 * np.clip(duck / (duck.max() + 1e-9), 0, 1)
    bus.L *= duck
    bus.R *= duck
    bus.add(0, low.L * duck, low.R * duck, 0.34)
    bus.add(0, drums.L, drums.R, 0.5)
    return bus


# ------------------------------------------------------------------ textura

def textura(rng):
    bus = ins.Bus(TOTAL, "textura")
    N = bus.n
    bend = global_bend(np.arange(N) / SR)

    lvl = dsp.automation([(0, 0.0), (2.5, 0.9), (bar_t(21), 0.8), (bar_t(22), 1.3),
                          (bar_t(27), 1.0), (60, 1.0)], N)
    L, R = ins.drone(N, rng, lvl, bend=bend)
    bus.add(0, L, R)

    center = dsp.automation([(0, 400), (bar_t(5), 900), (bar_t(13), 1500), (bar_t(21), 1800),
                             (bar_t(27), 250), (bar_t(27) + 0.01, 1600), (60, 1600)], N)
    alv = dsp.automation([(0, 0.0), (3, 1.0), (bar_t(21), 0.9), (bar_t(26), 1.5),
                          (bar_t(27), 1.0), (60, 1.0)], N)
    L, R = ins.air(N, rng, alv, center)
    bus.add(0, L, R)

    dens = dsp.automation([(0, 2), (bar_t(5), 5), (bar_t(13), 8), (bar_t(21), 16),
                           (bar_t(27), 18), (60, 18)], N)
    shift = 2.0 ** (bend / 12.0) * dsp.automation([(0, 1), (bar_t(21), 1), (bar_t(27), 0.5),
                                                   (bar_t(27) + 0.01, 1), (60, 1)], N)
    glen = dsp.automation([(0, 0.06), (bar_t(21), 0.06), (bar_t(27), 0.35),
                           (bar_t(27) + 0.01, 0.04), (60, 0.04)], N)
    glv = dsp.automation([(0, 0.5), (bar_t(13), 0.8), (bar_t(21), 1.0), (60, 0.9)], N)
    pitches = [n("A5"), n("E6"), n("A#5"), n("D#6"), n("A6"), n("E5")]
    L, R = ins.grains(N, rng, dens, pitches, shift, glen, glv)
    bus.add(0, L, R)

    # Reles.
    for b in range(1, 31):
        if section(b) == "4":
            continue
        p = {"1": 0.12, "2": 0.3, "3": 0.4, "5": 0.6}[section(b)]
        for s in range(14):
            if rng.uniform() < p:
                x = ins.tick(rng, rng.integers(3))
                bus.add(bar_t(b, s) + rng.normal(0, 0.002),
                        *dsp.pan(x, rng.uniform(-0.8, 0.8)), gain=rng.uniform(0.12, 0.35))

    # Servos: la instalacion se mueve en cada cambio de seccion.
    for t0, f0, f1, d in ((bar_t(4, 6), 140, 380, 1.0), (bar_t(12, 4), 220, 520, 1.25),
                          (bar_t(16, 2), 300, 160, 0.9), (bar_t(18, 2), 180, 600, 0.9),
                          (bar_t(29, 0), 500, 120, 1.2)):
        L, R = dsp.pan(ins.servo(d, rng, f0, f1), rng.uniform(-0.6, 0.6))
        bus.add(t0, L, R, 0.35)

    # Remolinos invertidos que "aspiran" hacia ESCALADA y COLAPSO.
    for b in (13, 27):
        L, R = ins.reverse_swell(BAR, rng, pad_voicing(b))
        bus.add(bar_t(b) - BAR, L, R, 0.4)

    # Horizonte de sucesos y caida final.
    L, R = ins.horizon_sweep(3.5, rng)
    bus.add(bar_t(21) - 1.75, L, R, 0.5)
    x = ins.sub_fall(4.0, 110.0, 27.5)
    bus.add(bar_t(21), x, x, 0.5)
    x = ins.sub_fall(STOP_DUR + 0.6, 90.0, 20.0)
    bus.add(STOP_T, x, x, 0.6)
    return bus


def ediciones(L, R):
    """Cortes glitch y el freno final. Se aplican igual a cada capa, para que
    las tres sigan sincronizadas al exportarlas por separado."""
    L, R = L.copy(), R.copy()
    for t, sl, tot in ((bar_t(12, 10), S16, 4 * S16),
                       (bar_t(20, 8), S16 * 2, 6 * S16),
                       (bar_t(28, 10), S16 / 2, 4 * S16),
                       (bar_t(29, 7), S16, 3 * S16),
                       (bar_t(30, 8), S16, 6 * S16)):
        L, R = dsp.beat_repeat(L, R, t, sl, tot)
    return dsp.tape_stop(L, R, STOP_T, STOP_DUR)
