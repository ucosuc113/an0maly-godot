"""Figuras de la documentacion: los dos leitmotivs en piano roll y el mapa
de la forma sobre el espectrograma del tema.  python3 music/figuras.py"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sintesis.leitmotivs import INSTALACION, AGUJERO, NOTE, rotacion  # noqa: E402
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
    ax.set_xlim(0, max(t, 14))
    ax.set_yticks(range(lo, hi + 1))
    ax.set_yticklabels([f"{NAMES[m % 12]}{m // 12 - 1}" for m in range(lo, hi + 1)], fontsize=7)
    ax.set_xticks(range(0, int(max(t, 14)) + 1, 2))
    ax.set_xlabel("semicorcheas", fontsize=8)
    ax.grid(alpha=0.25)


def leitmotivs():
    fig, ax = plt.subplots(3, 1, figsize=(10, 9))
    roll(ax[0], INSTALACION, "#3aa0ff", "I  LA INSTALACION  (celula de 7/16: medio compas de 7/8)")
    esc = rotacion(0) + rotacion(1) + rotacion(2) + rotacion(3)
    roll(ax[1], esc, "#7cc4ff", "I en sus 4 rotaciones octatonicas (ESCALADA: A, C, D#, F#)")
    roll(ax[2], AGUJERO, "#ff5a3a", "II  EL AGUJERO NEGRO = I retrogradado, 8va abajo, tiempo dilatado",
         glide=True)
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
    cols = {"1": "#aaa", "2": "#3aa0ff", "3": "#3aa0ff", "4": "#ff5a3a", "5": "#c070ff", "6": "#aaa"}
    prev = None
    for b in range(1, P.NBARS + 1):
        sec = P.section(b)
        t0 = P.bar_t(b)
        if sec != prev:
            ax.axvline(t0, color="w", lw=0.8)
            ax.text(t0 + 0.3, 9000, f"{sec} {P.SEC_NAMES[sec]}", color=cols[sec], fontsize=8,
                    weight="bold")
        if b == 1 or P.PROG[b - 1] != P.PROG[b - 2] or sec != prev:
            ax.text(t0 + 0.1, 40, P.PROG[b - 1], color="w", fontsize=7, rotation=90)
        prev = sec
    ax.axvline(P.STOP_T, color="#ff5a3a", lw=0.8, ls="--")
    ax.set_xlabel("segundos")
    ax.set_ylabel("Hz")
    ax.set_title("Anomaly_Tema.ogg - forma, armonia por compas y espectro")
    plt.tight_layout()
    plt.savefig(os.path.join(OUT, "forma.png"), dpi=75)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    leitmotivs()
    forma()
