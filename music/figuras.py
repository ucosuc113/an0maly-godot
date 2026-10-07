"""Figuras de la documentacion: los dos leitmotivs en piano roll y el mapa
de la forma sobre el espectrograma del tema.  python3 music/figuras.py"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sintesis.leitmotivs import INSTALACION, INSTALACION_RESP, AGUJERO, NOTE  # noqa: E402
from sintesis import partitura as P  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "musica")
NAMES = list(NOTE)


def roll(ax, motif, color, title, glide=False):
    t = 0
    pts = []
    for m, d in motif.notes:
        ax.add_patch(plt.Rectangle((t, m - 0.4), d, 0.8, color=color, alpha=0.85))
        ax.text(t + 0.15, m + 0.55, f"{NAMES[m % 12]}{m // 12 - 1}", fontsize=9)
        pts.append((t, m, d))
        t += d
    if glide:
        for (t0, m0, d0), (t1, m1, _) in zip(pts, pts[1:]):
            ax.annotate("", xy=(t1, m1), xytext=(t0 + d0 - 0.3, m0),
                        arrowprops=dict(arrowstyle="->", color=color, lw=1, ls="--"))
    ivs = motif.intervals()
    ax.set_title(f"{title}   intervalos {' '.join(f'{i:+d}' for i in ivs)}", fontsize=10)
    lo = min(m for m, _ in motif.notes) - 2
    hi = max(m for m, _ in motif.notes) + 2
    ax.set_ylim(lo, hi)
    ax.set_xlim(0, max(t, 16))
    ax.set_yticks(range(lo, hi + 1))
    ax.set_yticklabels([f"{NAMES[m % 12]}{m // 12 - 1}" for m in range(lo, hi + 1)], fontsize=7)
    ax.set_xticks(range(0, int(max(t, 16)) + 1, 4))
    ax.set_xlabel("semicorcheas", fontsize=8)
    ax.grid(alpha=0.25)


def leitmotivs():
    fig, ax = plt.subplots(3, 1, figsize=(10, 9))
    roll(ax[0], INSTALACION, "#3aa0ff", "I  LA INSTALACION (antecedente)")
    roll(ax[1], INSTALACION_RESP, "#7cc4ff", "I'  LA INSTALACION (respuesta)")
    roll(ax[2], AGUJERO, "#ff5a3a", "II  EL AGUJERO NEGRO = inversion de I, aumentacion x2", glide=True)
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, "leitmotivs.png"), dpi=80)


def forma():
    import soundfile as sf
    x, sr = sf.read(os.path.join(ROOT, "assets", "Musica", "Anomaly_Tema.ogg"))
    y = x.mean(1)
    fig, ax = plt.subplots(figsize=(14, 4.5))
    ax.specgram(y, NFFT=4096, Fs=sr, noverlap=3072, cmap="magma", vmin=-110)
    ax.set_yscale("symlog", linthresh=200)
    ax.set_ylim(30, 12000)
    ax.set_xlim(0, len(y) / sr)
    cols = {"A": "#888", "B": "#3aa0ff", "C": "#3aa0ff", "D": "#ff5a3a", "E": "#c070ff", "F": "#888"}
    labels = {"A": "A ARRANQUE", "B": "B PROTOCOLO", "C": "C REGIMEN", "D": "D HORIZONTE",
              "E": "E COLISION", "F": "F DISOLUCION"}
    for k, s in enumerate("ABCDEF"):
        t0 = k * 4 * P.BAR
        ax.axvline(t0, color="w", lw=0.8)
        ax.text(t0 + 0.3, 9000, labels[s], color=cols[s], fontsize=9, weight="bold")
        for b in range(4):
            ax.text(t0 + b * P.BAR + 0.2, 40, P.PROG[k * 4 + b], color="w", fontsize=7)
    ax.set_xlabel("segundos")
    ax.set_ylabel("Hz")
    ax.set_title("Anomaly_Tema.ogg - forma, armonia por compas y espectro")
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, "forma.png"), dpi=75)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    leitmotivs()
    forma()
