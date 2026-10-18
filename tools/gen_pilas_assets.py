#!/usr/bin/env python3
"""Genera los recursos propios de Pilas: ícono, sonidos y copia de pictogramas
y tipografías con licencia libre.

Uso (desde la raíz del repositorio):
    python3 tools/gen_pilas_assets.py --twemoji /ruta/twemoji/assets/svg \
        --lexend /ruta/lexend/fonts/lexend/ttf --andika /ruta/font-andika/references/v7000

Sin argumentos solo genera el ícono y los sonidos.
"""
import argparse
import math
import re
import shutil
import struct
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps" / "pilas"
ASSETS = APP / "assets"

YELLOW = (255, 209, 102, 255)
NAVY = (31, 41, 84, 255)
WHITE = (255, 255, 255, 255)


# ---------------------------------------------------------------- ícono

def draw_bolt(draw: ImageDraw.ImageDraw, size: int, offset: float = 0.0) -> None:
    """Rayo amigable: polígono blanco con cara."""
    s = size
    pts = [
        (0.56, 0.08), (0.30, 0.52), (0.47, 0.52), (0.40, 0.92),
        (0.72, 0.44), (0.54, 0.44), (0.62, 0.08),
    ]
    poly = [((x - 0.5) * (1 - offset) * s + 0.5 * s, (y - 0.5) * (1 - offset) * s + 0.5 * s) for x, y in pts]
    draw.polygon(poly, fill=WHITE)
    # ojos y sonrisa
    k = (1 - offset)
    cx, cy = 0.5 * s, 0.5 * s

    def p(x, y):
        return (cx + (x - 0.5) * k * s, cy + (y - 0.5) * k * s)

    r = 0.028 * k * s
    for ex in (0.47, 0.57):
        x, y = p(ex, 0.33)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=NAVY)
    x0, y0 = p(0.455, 0.37)
    x1, y1 = p(0.585, 0.44)
    draw.arc([x0, y0, x1, y1], start=10, end=170, fill=NAVY, width=max(2, int(0.012 * k * s)))


def gen_icon() -> None:
    out = ASSETS / "icon"
    out.mkdir(parents=True, exist_ok=True)
    size = 1024
    # Cuadrado completo y opaco: iOS y Google Play recortan las esquinas ellos mismos.
    img = Image.new("RGBA", (size, size), YELLOW)
    d = ImageDraw.Draw(img)
    draw_bolt(d, size)
    img.convert("RGB").save(out / "icon-1024.png")

    fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(fg)
    draw_bolt(d2, size, offset=0.34)
    fg.save(out / "icon-foreground-1024.png")
    print("ícono generado")


# ---------------------------------------------------------------- sonidos

SR = 22050


def tone(freq: float, dur: float, vol: float = 0.5, attack: float = 0.01, decay: float = 0.25, harmonics=(1.0, 0.35, 0.15)) -> np.ndarray:
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    sig = np.zeros_like(t)
    for i, h in enumerate(harmonics):
        sig += h * np.sin(2 * math.pi * freq * (i + 1) * t)
    env = np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-t / max(decay, 1e-4))
    return vol * sig * env


def noise(dur: float, vol: float = 0.3, decay: float = 0.08) -> np.ndarray:
    n = int(SR * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    sig = np.random.default_rng(7).uniform(-1, 1, n)
    # filtro simple pasa bajos
    kernel = np.ones(8) / 8.0
    sig = np.convolve(sig, kernel, mode="same")
    env = np.exp(-t / decay)
    return vol * sig * env


def sequence(parts, gap: float = 0.0) -> np.ndarray:
    chunks = []
    for p in parts:
        chunks.append(p)
        if gap:
            chunks.append(np.zeros(int(SR * gap)))
    return np.concatenate(chunks)


def mix(a: np.ndarray, b: np.ndarray, offset: float) -> np.ndarray:
    o = int(SR * offset)
    n = max(len(a), o + len(b))
    out = np.zeros(n)
    out[: len(a)] += a
    out[o : o + len(b)] += b
    return out


def write_wav(path: Path, sig: np.ndarray) -> None:
    sig = np.clip(sig, -1, 1)
    data = (sig * 32767).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def gen_sounds() -> None:
    out = ASSETS / "sounds"
    out.mkdir(parents=True, exist_ok=True)
    c5, e5, g5, c6, a5, g4, e4, d5 = 523.25, 659.25, 783.99, 1046.5, 880.0, 392.0, 329.63, 587.33
    sounds = {
        "tap": noise(0.06, vol=0.25, decay=0.02) + tone(1200, 0.06, vol=0.15, decay=0.03),
        "ok": mix(tone(c5, 0.35, vol=0.4), tone(e5, 0.4, vol=0.4), 0.09),
        "great": sequence([tone(c5, 0.18, vol=0.4), tone(e5, 0.18, vol=0.4), tone(g5, 0.35, vol=0.45)]),
        "hint": mix(tone(g4, 0.3, vol=0.3), tone(e4, 0.35, vol=0.3), 0.14),
        "levelup": sequence([tone(c5, 0.16, vol=0.4), tone(e5, 0.16, vol=0.4), tone(g5, 0.16, vol=0.4), tone(c6, 0.5, vol=0.45)]),
        "sticker": sequence([tone(a5, 0.1, vol=0.35), tone(c6, 0.1, vol=0.35), tone(e5 * 2, 0.3, vol=0.35)]),
        "page": noise(0.18, vol=0.15, decay=0.1),
        "pop": tone(d5, 0.12, vol=0.35, decay=0.05, harmonics=(1.0, 0.2)),
    }
    for name, sig in sounds.items():
        write_wav(out / f"{name}.wav", sig)
    print(f"{len(sounds)} sonidos generados")


# ---------------------------------------------------------------- pictogramas

EMOJI_RE = re.compile(r"'([0-9a-f]{2,5}(?:-[0-9a-f]{3,5})*)'")


def scan_emoji_codes() -> set:
    codes = set()
    for dart in (APP / "lib").rglob("*.dart"):
        for m in EMOJI_RE.finditer(dart.read_text(encoding="utf-8")):
            codes.add(m.group(1))
    return codes


def copy_emoji(twemoji_svg: Path) -> None:
    out = ASSETS / "emoji"
    out.mkdir(parents=True, exist_ok=True)
    codes = scan_emoji_codes()
    missing = []
    copied = 0
    for code in sorted(codes):
        src = twemoji_svg / f"{code}.svg"
        if not src.exists():
            missing.append(code)
            continue
        shutil.copy2(src, out / f"{code}.svg")
        copied += 1
    print(f"{copied} pictogramas copiados")
    if missing:
        print("NO EXISTEN en Twemoji:", ", ".join(missing))


def copy_fonts(lexend: Path, andika: Path) -> None:
    out = ASSETS / "fonts"
    out.mkdir(parents=True, exist_ok=True)
    for w in ("Regular", "Medium", "SemiBold", "Bold"):
        shutil.copy2(lexend / f"Lexend-{w}.ttf", out / f"Lexend-{w}.ttf")
    for w in ("Regular", "Bold"):
        shutil.copy2(andika / f"Andika-{w}.ttf", out / f"Andika-{w}.ttf")
    print("tipografías copiadas")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--twemoji")
    ap.add_argument("--lexend")
    ap.add_argument("--andika")
    ap.add_argument("--only-emoji", action="store_true")
    args = ap.parse_args()
    if not args.only_emoji:
        gen_icon()
        gen_sounds()
    if args.twemoji:
        copy_emoji(Path(args.twemoji))
    if args.lexend and args.andika and not args.only_emoji:
        copy_fonts(Path(args.lexend), Path(args.andika))


if __name__ == "__main__":
    main()
