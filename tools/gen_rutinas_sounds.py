#!/usr/bin/env python3
"""Sintetiza los sonidos de Rutinas: pitidos, campana, bocina y gong.

Todos los sonidos son propios: se calculan aquí con sumas de senos, envolventes
y un poco de ruido filtrado, sin muestras de terceros. Salen en WAV PCM de
16 bits, mono, 44,1 kHz, que sirve tanto para reproducir dentro de la app
(assets/sounds/) como para las notificaciones de Android (res/raw, lo copia
tools/patch_platforms.py) y de iOS (la app los copia a Library/Sounds).

- rutinas_pip.wav   pitido corto de la cuenta atrás (3, 2, 1)
- rutinas_beep.wav  pitido largo de cambio de intervalo
- rutinas_bell.wav  campana pequeña
- rutinas_horn.wav  bocina de dos tonos
- rutinas_gong.wav  gong grave para el final

Uso: python3 tools/gen_rutinas_sounds.py
"""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "apps" / "rutinas" / "assets" / "sounds"
RATE = 44100
# Semilla fija: los archivos salen idénticos cada vez que se generan.
RNG = np.random.default_rng(20261018)


def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * RATE)) / RATE


def fade(signal: np.ndarray, attack: float, release: float) -> np.ndarray:
    """Rampa de entrada y salida (coseno) para que no haya chasquidos."""
    out = signal.copy()
    a = max(1, int(attack * RATE))
    r = max(1, int(release * RATE))
    out[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    out[-r:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, r))
    return out


def normalize(signal: np.ndarray, peak: float) -> np.ndarray:
    signal = signal - np.mean(signal)
    m = np.max(np.abs(signal))
    return signal if m == 0 else signal * (peak / m)


def lowpass(signal: np.ndarray, cutoff: float) -> np.ndarray:
    """Filtro pasabajos de un polo (suaviza el ruido del golpe)."""
    alpha = 1 - np.exp(-2 * np.pi * cutoff / RATE)
    out = np.empty_like(signal)
    acc = 0.0
    for i, x in enumerate(signal):
        acc += alpha * (x - acc)
        out[i] = acc
    return out


def pip() -> np.ndarray:
    t = t_axis(0.11)
    f = 1568.0  # Sol6
    s = np.sin(2 * np.pi * f * t) + 0.18 * np.sin(2 * np.pi * 2 * f * t)
    s *= np.exp(-t / 0.06)
    return normalize(fade(s, 0.003, 0.012), 0.80)


def beep() -> np.ndarray:
    t = t_axis(0.42)
    f = 987.8  # Si5
    s = np.sin(2 * np.pi * f * t) + 0.12 * np.sin(2 * np.pi * 2 * f * t) + 0.05 * np.sin(2 * np.pi * 3 * f * t)
    return normalize(fade(s, 0.006, 0.07), 0.75)


def bell() -> np.ndarray:
    t = t_axis(2.4)
    f0 = 784.0  # Sol5
    # Parciales inarmónicos de una campana pequeña: (proporción, amplitud, caída en s).
    partials = [(1.0, 1.0, 2.0), (2.0, 0.5, 1.3), (2.756, 0.42, 0.95), (3.0, 0.18, 1.1), (4.07, 0.22, 0.55), (5.40, 0.15, 0.42), (6.79, 0.08, 0.28)]
    s = np.zeros_like(t)
    for ratio, amp, decay in partials:
        s += amp * np.sin(2 * np.pi * f0 * ratio * t) * np.exp(-t / decay)
    # Un gemelo apenas desafinado del fundamental da el batido de una campana real.
    s += 0.28 * np.sin(2 * np.pi * (f0 + 1.3) * t + 0.4) * np.exp(-t / 2.0)
    # Golpe del badajo: ruido muy corto y filtrado.
    click = lowpass(RNG.standard_normal(len(t)), 6000) * np.exp(-t / 0.004)
    s += 0.35 * click
    return normalize(fade(s, 0.001, 0.25), 0.82)


def horn() -> np.ndarray:
    t = t_axis(0.9)
    vibrato = 1 + 0.003 * np.sin(2 * np.pi * 5.5 * t)
    s = np.zeros_like(t)
    for f in (349.2, 440.0):  # Fa4 y La4: la tercera de una bocina de dos tonos
        phase = 2 * np.pi * np.cumsum(f * vibrato) / RATE
        for n in range(1, 16):
            rolloff = 1 / (1 + (n * f / 2400) ** 2)
            s += (1 / n) * rolloff * np.sin(n * phase)
    # Un poco de saturación le da cuerpo de metal.
    s = np.tanh(1.6 * s / np.max(np.abs(s)))
    return normalize(fade(s, 0.025, 0.09), 0.70)


def gong() -> np.ndarray:
    t = t_axis(4.5)
    f0 = 98.0  # Sol2
    partials = [(1.0, 1.0, 3.6), (1.52, 0.7, 3.0), (1.95, 0.55, 2.6), (2.41, 0.5, 2.2), (2.84, 0.38, 1.9), (3.36, 0.3, 1.6), (4.05, 0.24, 1.3), (4.78, 0.18, 1.05), (5.53, 0.12, 0.85), (6.31, 0.08, 0.7)]
    # El tono baja un poco al principio, como un gong grande al golpearlo.
    glide = 1 + 0.012 * np.exp(-t / 0.35)
    s = np.zeros_like(t)
    for i, (ratio, amp, decay) in enumerate(partials):
        for detune, weight in ((0.0, 1.0), (0.7 + 0.15 * i, 0.55)):
            phase = 2 * np.pi * np.cumsum((f0 * ratio + detune) * glide) / RATE
            s += weight * amp * np.sin(phase + 0.3 * i) * np.exp(-t / decay)
    # Golpe de la maza: ruido grave y corto.
    thump = lowpass(RNG.standard_normal(len(t)), 400) * np.exp(-t / 0.05)
    s += 2.5 * thump
    # El brillo crece un instante después del golpe.
    s *= 1 - 0.35 * np.exp(-t / 0.02)
    return normalize(fade(s, 0.004, 0.6), 0.85)


def write(name: str, signal: np.ndarray) -> None:
    pcm = np.clip(np.round(signal * 32767), -32768, 32767).astype("<i2")
    path = OUT / name
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(f"{path.relative_to(ROOT)}: {len(signal) / RATE:.2f} s, {path.stat().st_size // 1024} KB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    write("rutinas_pip.wav", pip())
    write("rutinas_beep.wav", beep())
    write("rutinas_bell.wav", bell())
    write("rutinas_horn.wav", horn())
    write("rutinas_gong.wav", gong())


if __name__ == "__main__":
    main()
