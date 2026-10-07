"""Capa de teoria: los leitmotivs como datos y sus transformaciones.

Un motivo es una lista de (altura MIDI, duracion en semicorcheas). Las
transformaciones son las clasicas del contrapunto; la partitura no escribe
notas sueltas para los temas, siempre los deriva de aca.

Los dos temas comparten las mismas cuatro notas: el ACORDE ANOMALIA

    {A, E, A#, D#}  =  dos tritonos entrelazados (A-D#, E-A#)

Es un conjunto simetrico: invertido o transportado un tritono da las mismas
notas. No es mayor ni menor; no tiene tonica clara ni cadencia posible. Es
el sonido de la instalacion y de la anomalia a la vez.

    I  LA INSTALACION   A4 E5 A#5 D#6    intervalos +7 +6 +5   2-2-1-2 semicorcheas
       sube con intervalos que se achican: una maquina que frena con precision.

    II EL AGUJERO NEGRO D#5 A#4 E4 A3    intervalos -5 -6 -7   6-8-12-16 semicorcheas
       es I al reves (retrogradacion una octava abajo): cae con intervalos que
       crecen -una caida que acelera- mientras cada nota dura mas que la
       anterior: el tiempo se dilata al acercarse al horizonte.
"""
from dataclasses import dataclass

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
        "G#": 8, "A": 9, "A#": 10, "B": 11}
NAMES = list(NOTE)


def n(name):
    """'G#5' -> 80 (MIDI)."""
    pc, octv = name[:-1], int(name[-1])
    return 12 * (octv + 1) + NOTE[pc]


def name(m):
    return f"{NAMES[m % 12]}{m // 12 - 1}"


@dataclass
class Motif:
    notes: list                      # [(midi, dur_16), ...]
    name: str = ""

    @property
    def length(self):
        return sum(d for _, d in self.notes)

    def intervals(self):
        p = [m for m, _ in self.notes]
        return [b - a for a, b in zip(p, p[1:])]

    def transpose(self, st):
        return Motif([(m + st, d) for m, d in self.notes], self.name + f"T{st:+d}")

    def invert(self, start=None):
        """Inversion: cada intervalo cambia de sentido."""
        p0 = self.notes[0][0] if start is None else start
        out, cur = [(p0, self.notes[0][1])], p0
        for iv, (_, d) in zip(self.intervals(), self.notes[1:]):
            cur -= iv
            out.append((cur, d))
        return Motif(out, self.name + "I")

    def retrograde(self):
        return Motif(list(reversed(self.notes)), self.name + "R")

    def augment(self, k):
        return Motif([(m, max(1, int(round(d * k)))) for m, d in self.notes], self.name + f"x{k}")

    def head(self, count):
        return Motif(self.notes[:count], self.name + f"[:{count}]")

    def rhythm(self, durs):
        return Motif([(m, d) for (m, _), d in zip(self.notes, durs)], self.name)

    def octave(self, k):
        return self.transpose(12 * k)

    def __add__(self, other):
        return Motif(self.notes + other.notes, self.name + "+" + other.name)


# ------------------------------------------------------------------ temas

ANOMALIA = [0, 7, 13, 18]            # A E A# D# relativo a la raiz

# I. La instalacion: la celula. Ritmo 2-2-1-2 = 7 semicorcheas: medio compas
# de 7/8. Dos celulas llenan un compas; la maquina nunca cae "a tierra" en un
# 4/4 comodo, siempre le sobra o le falta un pulso.
INSTALACION = Motif([(n("A4") + i, d) for i, d in zip(ANOMALIA, [2, 2, 1, 2])], "I")

# II. El agujero negro: retrogradacion de I una octava abajo, con el tiempo
# dilatado (cada nota mas larga que la anterior). 42 semicorcheas = 3 compases.
AGUJERO = INSTALACION.retrograde().octave(-1).rhythm([6, 8, 12, 16])
AGUJERO.name = "II"


def rotacion(k):
    """I rotado k terceras menores (0..3): A, C, D#, F#. Las cuatro rotaciones
    viven en la misma escala octatonica; la de un tritono (k=2) tiene las
    mismas notas que I en otro orden."""
    return INSTALACION.transpose(3 * k)


def describe():
    for m in (INSTALACION, AGUJERO, rotacion(1), rotacion(2)):
        print(f"{m.name:8s} {' '.join(name(p) for p, _ in m.notes):20s} "
              f"int {m.intervals()}  dur {[d for _, d in m.notes]}")


if __name__ == "__main__":
    describe()
