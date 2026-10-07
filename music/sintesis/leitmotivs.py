"""Capa de teoria: los leitmotivs como datos y sus transformaciones.

Un motivo es una lista de (altura MIDI, duracion en semicorcheas). Las
transformaciones son las clasicas del contrapunto; la partitura no escribe
notas sueltas para los temas, siempre los deriva de aca.

    I  LA INSTALACION   A4 E5 D5 G#5 A5      intervalos  +7 -2 +6 +1
    II EL AGUJERO NEGRO E5 A4 B4 F4  E4      intervalos  -7 +2 -6 -1

II es la inversion exacta de I (el mismo gesto visto en un espejo) y se toca
en aumentacion x2: el agujero negro es la instalacion reflejada y con el
tiempo dilatado.
"""
from dataclasses import dataclass, field

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
        "G#": 8, "A": 9, "A#": 10, "B": 11}


def n(name):
    """'G#5' -> 80 (MIDI)."""
    pc, octv = name[:-1], int(name[-1])
    return 12 * (octv + 1) + NOTE[pc]


@dataclass
class Motif:
    notes: list                      # [(midi, dur_16), ...]
    name: str = ""
    glide: list = field(default_factory=list)   # glissando opcional por nota

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
        return Motif([(m, int(round(d * k))) for m, d in self.notes], self.name + f"x{k}")

    def head(self, count):
        return Motif(self.notes[:count], self.name + f"[:{count}]")

    def with_rhythm(self, durs):
        return Motif([(m, d) for (m, _), d in zip(self.notes, durs)], self.name)

    def octave(self, k):
        return self.transpose(12 * k)


# ------------------------------------------------------------------ temas

# I. La instalacion: arranca en la tonica, sube una quinta (orden, estructura),
# baja un tono y salta un tritono a la sensible G# que resuelve medio tono
# arriba en A. El tritono D-G# es la grieta dentro de la maquina: todo es
# preciso, pero hay algo inestable que la propia instalacion "resuelve".
# Ritmo: 2-2-4-3-5 semicorcheas = un compas exacto de 4/4 (un ciclo).
INSTALACION = Motif([(n("A4"), 2), (n("E5"), 2), (n("D5"), 4), (n("G#5"), 3), (n("A5"), 5)],
                    "I")

# Respuesta (consecuente) de la instalacion: baja de vuelta a casa.
INSTALACION_RESP = Motif([(n("F5"), 2), (n("E5"), 2), (n("B4"), 4), (n("C5"), 3), (n("A4"), 5)],
                         "I'")

# II. El agujero negro: inversion de I desde E5 y en aumentacion x2.
# Cae una quinta, sube un tono, cae un tritono y se hunde medio tono.
# En el render cada transicion es un glissando hacia abajo y la ultima nota
# se "corre al rojo" (deriva de afinacion descendente).
AGUJERO = INSTALACION.invert(start=n("E5")).augment(2)
AGUJERO.name = "II"


def describe():
    def fmt(m):
        names = list(NOTE)
        return " ".join(f"{names[p % 12]}{p // 12 - 1}" for p, _ in m.notes)
    for m in (INSTALACION, INSTALACION_RESP, AGUJERO):
        print(f"{m.name:3s} {fmt(m):24s} int {m.intervals()}  dur {[d for _, d in m.notes]}")


if __name__ == "__main__":
    describe()
