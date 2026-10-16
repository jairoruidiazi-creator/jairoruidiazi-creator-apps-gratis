#!/usr/bin/env python3
"""Genera el ícono de Clave (1024×1024 y el primer plano adaptativo).

El dibujo es propio: un diapasón ámbar sobre azul noche con un pequeño
indicador de afinación. Uso: python3 tools/gen_clave_assets.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "apps" / "clave" / "assets" / "icon"
NOCHE = (20, 33, 61, 255)
AMBAR = (252, 163, 17, 255)
VERDE = (46, 204, 113, 255)
PLATA = (229, 229, 229, 255)


def draw_fork(d: ImageDraw.ImageDraw, s: int, scale: float = 1.0) -> None:
    """Diapasón centrado; `scale` reduce el dibujo para el ícono adaptativo."""
    cx = s / 2
    w = int(s * 0.075 * scale)  # grosor de las barras
    top = s * (0.5 - 0.34 * scale)
    bottom = s * (0.5 + 0.36 * scale)
    arm_gap = s * 0.14 * scale
    arm_bottom = s * (0.5 + 0.02 * scale)
    # Brazos
    for sign in (-1, 1):
        x = cx + sign * arm_gap
        d.rounded_rectangle([x - w / 2, top, x + w / 2, arm_bottom], radius=w / 2, fill=AMBAR)
    # Arco que une los brazos
    d.pieslice([cx - arm_gap - w / 2, arm_bottom - arm_gap - w / 2, cx + arm_gap + w / 2, arm_bottom + arm_gap + w / 2], 0, 180, fill=AMBAR)
    d.pieslice([cx - arm_gap + w / 2, arm_bottom - arm_gap + w / 2, cx + arm_gap - w / 2, arm_bottom + arm_gap - w / 2], 0, 180, fill=NOCHE)
    # Mango
    d.rounded_rectangle([cx - w / 2, arm_bottom + arm_gap * 0.8, cx + w / 2, bottom], radius=w / 2, fill=AMBAR)
    # Indicador de afinación: tres puntos (rojo-verde-rojo) bajo el diapasón.
    r = s * 0.028 * scale
    y = bottom + s * 0.02 * scale
    for i, color in enumerate((PLATA, VERDE, PLATA)):
        x = cx + (i - 1) * s * 0.1 * scale
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    s = 1024
    img = Image.new("RGBA", (s, s), NOCHE)
    d = ImageDraw.Draw(img)
    draw_fork(d, s, 0.92)
    img.save(OUT / "icon-1024.png")
    fg = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(fg)
    draw_fork(d2, s, 0.62)
    fg.save(OUT / "icon-foreground-1024.png")
    print("ícono de Clave generado en", OUT)


if __name__ == "__main__":
    main()
