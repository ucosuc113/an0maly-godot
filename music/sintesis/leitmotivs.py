"""Capa de teoria: los leitmotivs como datos y sus transformaciones.

Un motivo es una lista de (altura MIDI, duracion en semicorcheas). Las
transformaciones son las clasicas del contrapunto; la partitura no escribe
notas sueltas para los temas, siempre los deriva de aca.

Armonia: el ACORDE ANOMALIA {A, E, A#, D#} = dos tritonos entrelazados
(A-D#, E-A#). Los dos temas usan esas cuatro notas como esqueleto.

    I  LA INSTALACION   A4 E5 D#5 E5 A#4 A4   +7 -1 +1 -6 -1   un compas de 7/8
    II EL AGUJERO NEGRO E5 A#4 A4 D#4 D4      -6 -1 -6 -1      tres compases

II es la cola de I (tritono abajo + semitono) en aumentacion y secuenciada:
la caida con la que la instalacion se corrige, repetida hasta perder el
fondo. Revisado con mc-melody (saltos preparados, octava central) y
mc-development (II derivado de un fragmento de I).
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

ANOMALIA = [0, 7, 13, 18]            # A E A# D# relativo a la raiz (acorde)

# I. La instalacion. Un compas de 7/8 (14 semicorcheas), octava central A4-A5.
#
#     A4  E5  D#5 E5  A#4 A4        intervalos +7 -1 +1 -6 -1
#     2   2   1   1   3   5         (4+2+3+5: el acento cae en 2+2+3)
#
#   a1 = A4 -> E5   la quinta: orden, estructura (salto con "rebote" despues)
#   a2 = D#5-E5     bordado de semitono: el temblor de la maquina, el tritono
#                   contra A metido como nota de paso
#   a3 = E5 -> A#4 -> A4   cae un tritono y amortigua medio tono: la maquina
#                   se corrige sola y aterriza en casa.
#
# Cumple mc-melody §3.1: nunca dos saltos seguidos (cada salto tiene rebote o
# amortiguacion por grado conjunto) y los cuatro sonidos del acorde ANOMALIA
# aparecen igual, como esqueleto.
INSTALACION = Motif([(n("A4"), 2), (n("E5"), 2), (n("D#5"), 1), (n("E5"), 1),
                     (n("A#4"), 3), (n("A4"), 5)], "I")

# I? (pregunta, cambio de final): la cola sube en vez de caer y se queda en
# A#5, el tritono de D#, sin resolver (mc-melody §2.1: final ascendente =
# pregunta).
INSTALACION_Q = Motif(INSTALACION.notes[:4] + [(n("A5"), 3), (n("A#5"), 5)], "I?")

# a2 suelto: el temblor, para fragmentar.
TEMBLOR = Motif(INSTALACION.notes[2:4], "a2")

# II. El agujero negro: la cola de I (a3: tritono abajo + semitono) en
# aumentacion y secuenciada una quinta abajo. Es la misma caida que usa la
# instalacion para corregirse, pero sin fondo: cada amortiguacion es el
# comienzo de la caida siguiente, y termina en D4, fuera del acorde ANOMALIA
# (la gravedad la saco del sistema).
#
#     E5  A#4 A4  D#4 D4            intervalos -6 -1 -6 -1
#     6   4   8   6   18            = 42 semicorcheas = tres compases
_cola = Motif(INSTALACION.notes[3:6], "a3")               # E5 A#4 A4
AGUJERO = Motif(_cola.notes + _cola.transpose(-7).notes[1:], "II").rhythm([6, 4, 8, 6, 18])
AGUJERO.name = "II"


def rotacion(k):
    """I rotado k terceras menores (0..3): A, C, D#, F#."""
    return INSTALACION.transpose(3 * k)


def describe():
    for m in (INSTALACION, INSTALACION_Q, TEMBLOR, AGUJERO):
        print(f"{m.name:8s} {' '.join(name(p) for p, _ in m.notes):20s} "
              f"int {m.intervals()}  dur {[d for _, d in m.notes]}")


if __name__ == "__main__":
    describe()
