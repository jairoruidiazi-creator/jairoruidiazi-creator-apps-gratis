#!/usr/bin/env python3
"""Genera el ícono de Plata (1024×1024 y el primer plano adaptativo).

Dibujo propio: una moneda dorada con el signo de pesos sobre verde oscuro,
con una pequeña "alcancía" de barras (tres columnas que suben) a la derecha.
Uso: python3 tools/gen_plata_assets.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "apps" / "plata" / "assets" / "icon"
VERDE = (11, 61, 46, 255)
ORO = (242, 179, 61, 255)
ORO_OSCURO = (198, 134, 20, 255)
CREMA = (255, 244, 214, 255)
MENTA = (103, 200, 142, 255)


def _font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for name in ("DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def draw(d: ImageDraw.ImageDraw, s: int, scale: float = 1.0) -> None:
    cx, cy = s * 0.42, s * 0.52
    r = s * 0.30 * scale
    ring = int(s * 0.035 * scale)
    # Sombra de la moneda
    d.ellipse([cx - r + s * 0.015, cy - r + s * 0.025, cx + r + s * 0.015, cy + r + s * 0.025], fill=(0, 0, 0, 70))
    # Moneda
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ORO)
    d.ellipse([cx - r + ring, cy - r + ring, cx + r - ring, cy + r - ring], fill=ORO, outline=ORO_OSCURO, width=int(ring * 0.5))
    # Signo de pesos
    font = _font(int(r * 1.35))
    text = "$"
    bbox = d.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text((cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1]), text, font=font, fill=VERDE)
    # Barras que suben (ahorro) a la derecha
    bw = s * 0.075 * scale
    gap = s * 0.025 * scale
    base_y = cy + r * 0.95
    x0 = cx + r * 0.78
    heights = [0.32, 0.52, 0.74]
    for i, hf in enumerate(heights):
        x = x0 + i * (bw + gap)
        h = r * hf * 1.6
        d.rounded_rectangle([x, base_y - h, x + bw, base_y], radius=bw * 0.3, fill=MENTA if i < 2 else CREMA)


def render(size: int, scale: float, background: bool) -> Image.Image:
    img = Image.new("RGBA", (size, size), VERDE if background else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw(d, size, scale)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    render(1024, 1.0, True).save(OUT / "icon-1024.png")
    # El primer plano adaptativo deja margen: Android recorta el 18 % exterior.
    render(1024, 0.72, False).save(OUT / "icon-foreground-1024.png")
    print(f"Íconos escritos en {OUT}")


if __name__ == "__main__":
    main()
