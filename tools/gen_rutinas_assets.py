#!/usr/bin/env python3
"""Genera el ícono de Rutinas (1024×1024 y el primer plano adaptativo).

Dibujo propio: un anillo de progreso coral (tres cuartos de vuelta, como un
hábito que se va cumpliendo o un temporizador que corre) sobre su pista, con
una marca de hecho blanca en el centro, sobre índigo profundo. Se dibuja a
cuatro veces el tamaño y se reduce para que los bordes queden suaves.

Uso: python3 tools/gen_rutinas_assets.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "apps" / "rutinas" / "assets" / "icon"
INDIGO_TOP = (43, 44, 120)
INDIGO_BOTTOM = (30, 31, 90)
PISTA = (61, 63, 148)
CORAL = (255, 138, 101)
BLANCO = (255, 255, 255)
SS = 4  # supermuestreo


def dot(d: ImageDraw.ImageDraw, x: float, y: float, width: float, color: tuple) -> None:
    d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=color)


def round_arc(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, start: float, end: float, width: float, color: tuple) -> None:
    """Arco grueso con puntas redondas, trazado con un pincel redondo (ángulos
    en grados, en sentido horario desde las 3; `r` es el radio del centro del trazo)."""
    steps = max(2, int(math.radians(end - start) * r / (width * 0.04)))
    for i in range(steps + 1):
        a = math.radians(start + (end - start) * i / steps)
        dot(d, cx + r * math.cos(a), cy + r * math.sin(a), width, color)


def round_line(d: ImageDraw.ImageDraw, pts: list, width: float, color: tuple) -> None:
    """Trazo grueso con puntas y uniones redondas (pincel redondo)."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        steps = max(2, int(math.hypot(x1 - x0, y1 - y0) / (width * 0.04)))
        for i in range(steps + 1):
            t = i / steps
            dot(d, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, width, color)


def draw_mark(d: ImageDraw.ImageDraw, s: int, scale: float, track: bool) -> None:
    cx = cy = s / 2
    stroke = s * 0.085 * scale
    # Radio del centro del trazo del anillo.
    r = s * 0.30 * scale
    if track:
        outer = r + stroke / 2
        d.ellipse([cx - outer, cy - outer, cx + outer, cy + outer], outline=PISTA, width=int(stroke))
    # Progreso: desde arriba (-90°) tres cuartos de vuelta en sentido horario.
    round_arc(d, cx, cy, r, -90, 180, stroke, CORAL)
    # Marca de hecho.
    k = s * scale
    pts = [(cx - 0.135 * k, cy + 0.005 * k), (cx - 0.04 * k, cy + 0.10 * k), (cx + 0.145 * k, cy - 0.095 * k)]
    round_line(d, pts, s * 0.078 * scale, BLANCO)


def gradient(s: int) -> Image.Image:
    img = Image.new("RGB", (s, s), INDIGO_TOP)
    d = ImageDraw.Draw(img)
    for y in range(s):
        t = y / (s - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(INDIGO_TOP, INDIGO_BOTTOM))
        d.line([(0, y), (s, y)], fill=c)
    return img


def render(size: int, scale: float, background: bool) -> Image.Image:
    s = size * SS
    if background:
        img = gradient(s).convert("RGBA")
    else:
        img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw_mark(ImageDraw.Draw(img), s, scale, track=True)
    img = img.resize((size, size), Image.LANCZOS)
    # Con fondo, el ícono es opaco: iOS y Google Play no aceptan transparencia.
    return img.convert("RGB") if background else img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    render(1024, 1.0, True).save(OUT / "icon-1024.png", optimize=True)
    # Primer plano adaptativo: flutter_launcher_icons lo mete con un margen del
    # 16 % (queda en 73 de los 108 dp) y Android muestra el círculo central de
    # 66 dp. A 1,15 el anillo mide unos 58 dp: tan grande como el de las demás
    # apps y sin que la máscara lo recorte.
    render(1024, 1.15, False).save(OUT / "icon-foreground-1024.png", optimize=True)
    print(f"Íconos escritos en {OUT}")


if __name__ == "__main__":
    main()
