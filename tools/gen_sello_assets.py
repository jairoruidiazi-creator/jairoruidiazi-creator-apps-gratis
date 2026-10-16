#!/usr/bin/env python3
"""Genera el ícono de Sello (1024×1024 y el primer plano adaptativo).

Dibujo propio: una cámara de trazo blanco sobre verde selva cuyo lente es un
marcador de ubicación naranja. Uso: python3 tools/gen_sello_assets.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "apps" / "sello" / "assets" / "icon"
SELVA = (27, 67, 50, 255)
ARENA = (244, 231, 195, 255)
NARANJA = (255, 112, 67, 255)
MUSGO = (64, 145, 108, 255)


def draw_camera(d: ImageDraw.ImageDraw, s: int, scale: float = 1.0) -> None:
    """Cámara centrada; `scale` reduce el dibujo para el ícono adaptativo."""
    cx, cy = s / 2, s / 2
    w = s * 0.66 * scale
    h = s * 0.46 * scale
    stroke = int(s * 0.045 * scale)
    r = s * 0.07 * scale
    body = [cx - w / 2, cy - h / 2 + s * 0.04 * scale, cx + w / 2, cy + h / 2 + s * 0.04 * scale]
    # Visor (joroba superior)
    hump_w = w * 0.34
    hump_h = s * 0.1 * scale
    hump = [cx - hump_w / 2, body[1] - hump_h + stroke, cx + hump_w / 2, body[1] + stroke * 2]
    d.rounded_rectangle(hump, radius=r * 0.6, outline=ARENA, width=stroke, fill=SELVA)
    d.rounded_rectangle(body, radius=r, outline=ARENA, width=stroke, fill=SELVA)
    # Tapa la unión visor/cuerpo
    d.rectangle([hump[0] + stroke, body[1] - stroke / 2, hump[2] - stroke, body[1] + stroke * 1.5], fill=SELVA)
    # Flash
    fr = s * 0.022 * scale
    fx, fy = body[2] - w * 0.13, body[1] + h * 0.18
    d.ellipse([fx - fr, fy - fr, fx + fr, fy + fr], fill=ARENA)
    # Lente: marcador de ubicación naranja
    lens_cy = cy + s * 0.02 * scale
    pr = s * 0.13 * scale  # radio de la cabeza del marcador
    tip = lens_cy + pr * 1.55
    d.ellipse([cx - pr, lens_cy - pr, cx + pr, lens_cy + pr], fill=NARANJA)
    d.polygon([(cx - pr * 0.72, lens_cy + pr * 0.69), (cx + pr * 0.72, lens_cy + pr * 0.69), (cx, tip)], fill=NARANJA)
    inner = pr * 0.42
    d.ellipse([cx - inner, lens_cy - inner, cx + inner, lens_cy + inner], fill=SELVA)
    # Sello: tres rayitas (hora, coordenadas, rumbo) abajo a la izquierda
    y0 = body[3] - h * 0.3
    for i, length in enumerate((0.16, 0.22, 0.12)):
        y = y0 + i * s * 0.045 * scale
        d.rounded_rectangle([body[0] + w * 0.08, y, body[0] + w * (0.08 + length), y + s * 0.022 * scale], radius=s * 0.011 * scale, fill=MUSGO if i != 1 else ARENA)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    s = 1024
    img = Image.new("RGBA", (s, s), SELVA)
    d = ImageDraw.Draw(img)
    draw_camera(d, s, 0.95)
    img.save(OUT / "icon-1024.png")
    fg = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(fg)
    draw_camera(d2, s, 0.62)
    fg.save(OUT / "icon-foreground-1024.png")
    print("ícono de Sello generado en", OUT)


if __name__ == "__main__":
    main()
