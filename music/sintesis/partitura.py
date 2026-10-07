"""Capa 4: la composicion. Forma, armonia y donde suena cada leitmotiv.

100 BPM, 4/4, La menor armonica. Un compas = 2.4 s; 24 compases + 1 de cola
= 60 s. Las tres capas pedidas salen en buses separados:

    textura        zumbido del reactor, ventilacion, nube granular, reles,
                   barridos del horizonte
    acompanamiento colchon, secuenciador (arpegio), bajo, bombo
    melodia        leitmotiv I (cristal FM) y leitmotiv II (sierras legato)

Forma (compases):
    A  1-4   ARRANQUE        solo textura sobre el pedal de A; el leitmotiv II
                             asoma lejos y apagado (presagio).
    B  5-8   PROTOCOLO       entra el secuenciador; leitmotiv I y su respuesta.
    C  9-12  REGIMEN         bajo y bombo; I completo y secuenciado a C.
    D  13-16 HORIZONTE       bajo cromatico descendente (lamento); leitmotiv II
                             en aumentacion; el arpegio se dilata (tiempo que
                             se estira) y se corre al rojo.
    E  17-20 COLISION        los dos leitmotivs a la vez: I arriba, II abajo.
    F  21-24 DISOLUCION      I en aumentacion; su ultima nota nunca llega: el
                             agujero negro la arrastra hacia abajo. Queda el
                             pedal y una campana lejana en A (el ciclo vuelve).
"""
import numpy as np

from . import dsp, instrumentos as ins
from .dsp import SR
from .leitmotivs import Motif, INSTALACION, INSTALACION_RESP, AGUJERO, n

BPM = 100.0
S16 = 60.0 / BPM / 4.0          # semicorchea = 0.15 s
BAR = 16 * S16                  # compas = 2.4 s
TOTAL = 60.0


def bar_t(b, step=0):
    """Tiempo (s) del compas `b` (1..24) mas `step` semicorcheas."""
    return (b - 1) * BAR + step * S16


# ------------------------------------------------------------------ armonia

# Acordes: (arpegio ascendente, voicing del colchon, raiz del bajo)
CH = {
    "Am9":    ([57, 60, 64, 71, 72, 76], [57, 60, 64, 71], n("A1")),
    "Fmaj7":  ([53, 60, 64, 69, 71, 76], [53, 57, 64, 71], n("F1")),   # con #11 (B)
    "Dm6":    ([62, 65, 69, 71, 74, 77], [50, 57, 65, 71], n("D2")),
    "E7b9":   ([52, 56, 62, 65, 68, 71], [52, 56, 62, 65], n("E1")),
    "E/G#":   ([56, 59, 64, 68, 71, 76], [56, 59, 64, 71], n("G#1")),
    "Am/G":   ([55, 60, 64, 69, 72, 76], [55, 60, 64, 69], n("G1")),
    "F#o":    ([54, 60, 64, 69, 72, 78], [54, 60, 64, 69], n("F#1")),
}

PROG = (["Am9"] * 4 +                                   # A
        ["Am9", "Fmaj7", "Dm6", "E7b9"] +               # B
        ["Am9", "Fmaj7", "Fmaj7", "E7b9"] +             # C
        ["Am9", "E/G#", "Am/G", "F#o"] +                # D  lamento A-G#-G-F#
        ["Fmaj7", "Dm6", "Am9", "E7b9"] +               # E
        ["Fmaj7", "Dm6", "Am9", "Am9"])                 # F

# Patron del secuenciador (indices sobre las 6 notas del acorde) y acentos.
ARP = [0, 2, 4, 1, 3, 5, 2, 4, 1, 3, 5, 2, 4, 3, 2, 1]
ACC = [1, .4, .7, .4, 1, .4, .6, .4, .9, .4, .7, .4, 1, .5, .6, .5]


def section(b):
    return "AAAABBBBCCCCDDDDEEEEFFFF"[b - 1]


# ------------------------------------------------------------------ capas

def melodia(rng):
    bus = ins.Bus(TOTAL, "melodia")

    def play_I(motif, b, step=0, vel=1.0, octave=0):
        t = bar_t(b, step)
        for m, d in motif.notes:
            L, R = ins.facility_lead(m + 12 * octave, d * S16, rng, vel=vel)
            bus.add(t, L, R)
            t += d * S16

    def play_II(motif, b, gain=1.0, bright=1.0, redshift=-0.8, octave=0):
        t, ev = 0.0, []
        for m, d in motif.notes:
            ev.append((t, m + 12 * octave))
            t += d * S16
        L, R = ins.singularity_lead(ev, t, rng, redshift=redshift, bright=bright)
        bus.add(bar_t(b), L, R, gain)

    # A: presagio. II dos octavas abajo, casi sin brillo, muy bajo.
    play_II(AGUJERO, 3, gain=0.35, bright=0.15, redshift=-0.5, octave=-1)

    # B: protocolo.
    play_I(INSTALACION, 5)
    # Eco: la resolucion G#-A, una octava abajo y lejos.
    play_I(Motif(INSTALACION.notes[3:]).octave(-1), 6, step=8, vel=0.35)
    play_I(INSTALACION_RESP, 7)
    frag = INSTALACION.head(4).with_rhythm([2, 2, 4, 8])        # ...D5 G#5 suspendido
    play_I(frag, 8, vel=0.8)

    # C: regimen. I, respuesta, I secuenciado a C (sobre Fmaj7#11), grieta.
    play_I(INSTALACION, 9)
    play_I(INSTALACION_RESP, 10)
    play_I(INSTALACION.transpose(3), 11)
    play_I(frag, 12, vel=0.85)

    # D: horizonte. II en aumentacion y luego un tono mas abajo (cae).
    play_II(AGUJERO, 13, gain=0.8)
    play_II(AGUJERO.transpose(-2), 15, gain=0.8, redshift=-1.2)

    # E: colision. I arriba, II una octava abajo y luego en A.
    play_I(INSTALACION.transpose(3), 17)
    play_I(INSTALACION_RESP, 18)
    play_I(INSTALACION, 19)
    play_I(frag, 20)
    play_II(AGUJERO.octave(-1), 17, gain=0.75, bright=0.8)
    play_II(AGUJERO.transpose(-7), 19, gain=0.75, bright=0.8, redshift=-1.5)

    # F: disolucion. I en aumentacion; G#5 nunca resuelve en A5: cae.
    t = bar_t(21)
    slow = INSTALACION.head(4).augment(2)
    for k, (m, d) in enumerate(slow.notes):
        dur = d * S16
        if k == len(slow.notes) - 1:
            L, R = ins.facility_lead(m, 3.2, rng, glide_to=n("E4"), glide_time=2.6, vel=0.9)
        else:
            L, R = ins.facility_lead(m, dur, rng, vel=0.9)
        bus.add(t, L, R)
        t += dur
    # La campana lejana: el ciclo vuelve a empezar.
    L, R = ins.facility_lead(n("A5"), 1.6, rng, vel=0.45)
    bus.add(bar_t(24, 4), L, R)
    return bus


def acompanamiento(rng):
    bus = ins.Bus(TOTAL, "acompanamiento")
    kick_env = np.zeros(bus.n)

    # Colchon: desde el compas 3, un acorde por compas (ligado si se repite).
    b = 3
    while b <= 24:
        c = PROG[b - 1]
        e = b
        while e + 1 <= 24 and PROG[e] == c and section(e + 1) == section(b):
            e += 1
        dur = (e - b + 1) * BAR
        dark = 0.5 if section(b) == "D" else 0.0
        cut = {"A": 700.0, "B": 1200.0, "C": 1500.0, "D": 1300.0, "E": 1900.0, "F": 1000.0}[section(b)]
        L, R = ins.pad_chord(CH[c][1], dur, rng, cutoff=cut, dark=dark)
        bus.add(bar_t(b), L, R, 0.9 if b > 4 else 0.6)
        b = e + 1

    # Secuenciador.
    seq = ins.Bus(TOTAL, "seq")
    for b in range(5, 25):
        sec = section(b)
        notes = [m + 12 for m in CH[PROG[b - 1]][0]]
        if sec == "D":
            continue
        if sec == "F":
            vel = [0.8, 0.55, 0.3, 0.12][b - 21]
        else:
            vel = 1.0
        for s in range(16):
            # Portal: al final de cada frase, el reloj se traba (ratchet).
            if b in (8, 12, 20) and s >= 12:
                for r in range(2):
                    x = ins.arp_note(notes[ARP[s]], S16 / 2, rng, accent=0.8)
                    seq.add(bar_t(b, s) + r * S16 / 2, *ins.dsp.pan(x, (-1) ** r * 0.6), gain=vel)
                continue
            x = ins.arp_note(notes[ARP[s]], S16, rng, accent=ACC[s])
            seq.add(bar_t(b, s), *ins.dsp.pan(x, -0.35 if s % 2 else 0.35), gain=vel)

    # D: dilatacion temporal. Cada paso dura un 4.7% mas que el anterior
    # (de 0.15 s a 0.6 s en 4 compases) y la afinacion cae medio tono.
    t, k = bar_t(13), 0
    d = S16
    while t < bar_t(17) - 0.05:
        b = 13 + int((t - bar_t(13)) / BAR)
        notes = [m + 12 for m in CH[PROG[b - 1]][0]]
        u = (t - bar_t(13)) / (4 * BAR)
        x = ins.arp_note(notes[ARP[k % 16]], min(d, 0.5), rng, accent=ACC[k % 16] * (1 - 0.5 * u),
                         bend=-0.5 * u ** 1.5)
        seq.add(t, *ins.dsp.pan(x, -0.5 if k % 2 else 0.5), gain=0.85)
        t += d
        d *= 1.046875
        k += 1

    # Eco ping-pong a corchea con puntillo (lenguaje del secuenciador).
    wl, wr = dsp.pingpong(seq.L, seq.R, 3 * S16, fb=0.42, damp_hz=2800.0)
    bus.add(0, seq.L + wl * 0.45, seq.R + wr * 0.45, 0.85)

    # Bajo.
    low = ins.Bus(TOTAL, "bajo")
    for b in range(9, 25):
        sec = section(b)
        root = CH[PROG[b - 1]][2]
        if sec in ("C", "E"):
            pat = [0, 0, 12, 0, 0, 12, 0, 7] if sec == "E" else [0] * 8
            for s in range(8):
                x = ins.bass_note(root + pat[s], S16 * 2 * 0.9, rng)
                low.add(bar_t(b, 2 * s), x, x, 0.8 if s % 2 else 1.0)
    # D: lamento legato A-G#-G-F#, que se desliza al rojo.
    ev = [(k * BAR, CH[PROG[12 + k]][2]) for k in range(4)]
    x = ins.bass_legato(ev, 4 * BAR, rng, glide=0.6)
    low.add(bar_t(13), x, x, 1.1)
    # F: pedal final.
    x = ins.bass_legato([(0, n("A1"))], 3 * BAR, rng)
    low.add(bar_t(21), x, x, 0.8)

    # Bombo.
    drums = ins.Bus(TOTAL, "bombo")
    for b in range(9, 21):
        sec = section(b)
        hits = {"C": [0, 8], "E": [0, 4, 8, 12], "D": [0]}[sec]
        for s in hits:
            k = ins.kick(rng, deep=(sec == "D"))
            t = bar_t(b, s)
            drums.add(t, *ins.dsp.pan(k, 0.0))
            i = int(t * SR)
            kick_env[i:i + len(k)] += np.abs(k)

    # Sidechain: el bombo hace "respirar" al colchon y al bajo.
    duck = ins.dsp.envelope_follower(kick_env, 0.002, 0.18)
    duck = 1.0 - 0.55 * np.clip(duck / (duck.max() + 1e-9), 0, 1)
    bus.L *= duck
    bus.R *= duck
    low.L *= duck
    low.R *= duck
    bus.add(0, low.L, low.R, 0.42)
    bus.add(0, drums.L, drums.R, 0.6)
    return bus


def textura(rng):
    bus = ins.Bus(TOTAL, "textura")
    N = bus.n
    T = N / SR

    lvl = dsp.automation([(0, 0.0), (3.0, 0.9), (28.8, 0.8), (31, 1.2), (38.4, 1.0),
                          (48, 0.9), (55, 0.7), (60, 0.0)], N)
    L, R = ins.drone(N, rng, lvl)
    bus.add(0, L, R)

    center = dsp.automation([(0, 500), (9.6, 900), (28.8, 1400), (38.4, 260),
                             (48, 1100), (57.6, 300), (60, 200)], N)
    alv = dsp.automation([(0, 0.0), (4, 1.0), (28.8, 0.8), (38.4, 1.4), (48, 1.0),
                          (60, 0.3)], N)
    L, R = ins.air(N, rng, alv, center)
    bus.add(0, L, R)

    # Nube granular: densidad por seccion; en el horizonte se corre al rojo.
    dens = dsp.automation([(0, 3), (9.6, 6), (28.8, 9), (38.4, 16), (48, 14),
                           (54, 4), (60, 1)], N)
    shift = dsp.automation([(0, 1), (28.8, 1), (38.4, 0.5), (38.41, 1), (48, 1),
                            (50, 1), (57.6, 0.5), (60, 0.5)], N)
    glen = dsp.automation([(0, 0.09), (28.8, 0.07), (38.4, 0.35), (38.41, 0.06),
                           (48, 0.08), (57.6, 0.4), (60, 0.4)], N)
    glv = dsp.automation([(0, 0.6), (9.6, 0.8), (38.4, 1.0), (60, 0.7)], N)
    pitches = [n("A5"), n("E6"), n("B5"), n("C6"), n("G#5"), n("A6"), n("E5")]
    L, R = ins.grains(N, rng, dens, pitches, shift, glen, glv)
    bus.add(0, L, R)

    # Reles: tics en semicorcheas con probabilidad (B, C, E).
    for b in range(5, 21):
        if section(b) == "D":
            continue
        p = {"B": 0.3, "C": 0.45, "E": 0.6}[section(b)]
        for s in range(16):
            if rng.uniform() < p or s % 4 == 2:
                x = ins.tick(rng, rng.integers(3))
                bus.add(bar_t(b, s) + rng.normal(0, 0.003),
                        *dsp.pan(x, rng.uniform(-0.7, 0.7)), gain=rng.uniform(0.15, 0.4))

    # Horizonte de sucesos: entrada (D), colision (E) y disolucion (F).
    L, R = ins.horizon_sweep(4.0, rng)
    bus.add(bar_t(13) - 2.4, L, R, 0.55)
    L, R = ins.horizon_sweep(3.0, rng, 3200.0, 60.0)
    bus.add(bar_t(17) - 1.2, L, R, 0.4)
    L, R = ins.horizon_sweep(6.0, rng, 1800.0, 30.0)
    bus.add(bar_t(21) + 2.4, L, R, 0.5)
    for t0 in (bar_t(13), bar_t(23)):
        x = ins.sub_fall(4.5)
        bus.add(t0, x, x, 0.5)
    return bus
