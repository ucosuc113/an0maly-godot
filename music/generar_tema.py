"""Capa 5: mezcla y master. Genera el tema de AN0MALY de punta a punta.

    python3 music/generar_tema.py            # -> assets/Musica/Anomaly_Tema.ogg
    python3 music/generar_tema.py --stems    # ademas, las 3 capas por separado

Requiere numpy y numba. ffmpeg para el .ogg (si no esta, deja el .wav).
Todo usa una semilla fija: el mismo codigo da siempre el mismo archivo.
"""
import argparse
import os
import shutil
import subprocess
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sintesis import dsp, partitura  # noqa: E402
from sintesis.dsp import SR  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = 1113


def space(L, R, send, size, decay, damp):
    """Envia una capa a su propia reverb y devuelve seco + humedo."""
    wl, wr = dsp.reverb(L * send, R * send, size=size, decay=decay, damp_hz=damp)
    return L + wl, R + wr


def mix(stems, reboot):
    tex, acc, mel = stems["textura"], stems["acompanamiento"], stems["melodia"]

    # Textura: nave enorme, reverb larga y oscura.
    tL, tR = space(tex.L, tex.R, 0.55, 1.9, 0.92, 3000.0)
    tL, tR = dsp.highpass(tL, 28.0), dsp.highpass(tR, 28.0)

    # Acompanamiento: sala media y seca (el secuenciador tiene que picar).
    aL, aR = space(acc.L, acc.R, 0.25, 1.0, 0.82, 4500.0)
    aL, aR = dsp.highpass(aL, 30.0), dsp.highpass(aR, 30.0)

    # Melodia: al frente, con eco y cola.
    dl, dr = dsp.pingpong(mel.L, mel.R, 0.375, fb=0.3, damp_hz=3200.0)
    mL, mR = mel.L + dl * 0.25, mel.R + dr * 0.25
    mL, mR = space(mL, mR, 0.35, 1.4, 0.88, 5000.0)

    out = {"textura": (tL * 0.85, tR * 0.85),
           "acompanamiento": (aL * 0.9, aR * 0.9),
           "melodia": (mL * 1.0, mR * 1.0)}
    # Cortes glitch y freno de cinta, identicos en las tres capas.
    out = {k: partitura.ediciones(*v) for k, v in out.items()}
    # El reinicio suena despues del freno, con su propio espacio.
    rL, rR = space(reboot.L, reboot.R, 0.6, 1.6, 0.9, 4000.0)
    mL, mR = out["melodia"]
    out["melodia"] = (mL + rL, mR + rR)
    return out


def master(L, R):
    # Pegamento: compresion suave del bus completo.
    L, R = dsp.compressor(L, R, threshold_db=-20.0, ratio=2.0, attack=0.02,
                          release=0.25, makeup_db=2.0)
    # Color "vintage" como la referencia: casi nada por encima de ~11 kHz.
    L, R = dsp.lowpass(L, 11000.0, 0.6), dsp.lowpass(R, 11000.0, 0.6)
    # Nivel: RMS objetivo -16 dBFS, luego limitador a -1 dBFS.
    rms = np.sqrt(np.mean((L ** 2 + R ** 2) / 2))
    g = 10 ** (-16.0 / 20.0) / (rms + 1e-12)
    L, R = dsp.limiter(L * g, R * g, ceiling_db=-1.0)
    # Fundidos de seguridad en los bordes.
    n = len(L)
    fi, fo = int(0.05 * SR), int(0.3 * SR)
    ramp = np.ones(n)
    ramp[:fi] = np.linspace(0, 1, fi)
    ramp[-fo:] = np.linspace(1, 0, fo) ** 2
    return L * ramp, R * ramp


def write_wav(path, L, R):
    x = np.stack([L, R], axis=1)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def to_ogg(wav, ogg, quality=6):
    if not shutil.which("ffmpeg"):
        return False
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis",
                    "-q:a", str(quality), ogg], check=True)
    return True


def render():
    rng = np.random.default_rng(SEED)
    print("melodia...", flush=True)
    mel = partitura.melodia(rng)
    print("acompanamiento...", flush=True)
    acc = partitura.acompanamiento(rng)
    print("textura...", flush=True)
    tex = partitura.textura(rng)
    reboot = partitura.reinicio(rng)
    stems = mix({"textura": tex, "acompanamiento": acc, "melodia": mel}, reboot)
    L = sum(s[0] for s in stems.values())
    R = sum(s[1] for s in stems.values())
    print("master...", flush=True)
    return stems, master(L, R)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "Musica", "Anomaly_Tema.ogg"))
    ap.add_argument("--stems", default="", help="carpeta donde dejar las 3 capas")
    ap.add_argument("--wav", action="store_true", help="conservar tambien el .wav")
    a = ap.parse_args()

    stems, (L, R) = render()
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    base, _ = os.path.splitext(a.out)
    wav = base + ".wav"
    write_wav(wav, L, R)
    if to_ogg(wav, base + ".ogg") and not a.wav:
        os.remove(wav)
    if a.stems:
        os.makedirs(a.stems, exist_ok=True)
        peak = max(np.abs(np.concatenate(s)).max() for s in stems.values())
        for name, (sl, sr_) in stems.items():
            p = os.path.join(a.stems, f"capa_{name}.wav")
            write_wav(p, sl / peak * 0.9, sr_ / peak * 0.9)
            if to_ogg(p, p[:-4] + ".ogg", 5):
                os.remove(p)
    pk = 20 * np.log10(max(np.abs(L).max(), np.abs(R).max()))
    rms = 20 * np.log10(np.sqrt(np.mean((L ** 2 + R ** 2) / 2)))
    print(f"listo: {base}.ogg  {len(L) / SR:.1f} s  pico {pk:.1f} dBFS  RMS {rms:.1f} dBFS")


if __name__ == "__main__":
    main()
