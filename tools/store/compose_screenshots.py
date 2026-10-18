#!/usr/bin/env python3
"""Compone las capturas de tienda a partir de las capturas crudas de la app.

Entrada: apps/<app>/build/store_shots/<dispositivo>/<idioma>/<id>.png (las
dibujan las pruebas con la etiqueta "screenshots") y los titulares de
apps/<app>/store/screenshots.json.

Salida (por defecto apps/<app>/build/store_listing/):
    play/<idioma>/phoneScreenshots/NN.png      1080 × 2160 (1:2)
    play/<idioma>/tenInchScreenshots/NN.png    1440 × 2560 (9:16, también sirve para 7")
    appstore/<idioma>/iphone69/NN.png          1320 × 2868 (iPhone 6,9")
    appstore/<idioma>/ipad13/NN.png            2064 × 2752 (iPad 13")

Requisitos que cumple: Google Play pide JPEG o PNG de 24 bits sin
transparencia, lados entre 320 y 3840 px y proporción de hasta 2:1 (tabletas
16:9 o 9:16 con lados ≥ 1080 px); App Store Connect pide los tamaños exactos de
arriba, sin canal alfa.

Uso: compose_screenshots.py <app> [--out carpeta] [--only es,en]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "tools" / "store" / "fonts"

TARGETS = {
    # dispositivo crudo: (tienda, carpeta, tamaño final, es tableta)
    "android_phone": ("play", "phoneScreenshots", (1080, 2160), False),
    "android_tablet": ("play", "tenInchScreenshots", (1440, 2560), True),
    "iphone": ("appstore", "iphone69", (1320, 2868), False),
    "ipad": ("appstore", "ipad13", (2064, 2752), True),
}
# Barra de estado y barra inferior de cada captura cruda, en píxeles.
SAFE = {
    "android_phone": (24 * 2.625, 16 * 2.625),
    "android_tablet": (24 * 2, 16 * 2),
    "iphone": (62 * 3, 34 * 3),
    "ipad": (24 * 2, 20 * 2),
}


def hex_color(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return tuple(int(s[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"Lexend-{weight}.ttf"), size)


def wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines: list[str] = []
    for paragraph in text.split("\n"):
        words = paragraph.split()
        line = ""
        for w in words:
            candidate = f"{line} {w}".strip()
            if draw.textlength(candidate, font=f) <= width or not line:
                line = candidate
            else:
                lines.append(line)
                line = w
        if line:
            lines.append(line)
    return lines


def balanced_wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    """Como wrap, pero reparte las palabras para que las líneas queden parejas."""
    lines = wrap(draw, text, f, width)
    if len(lines) < 2 or "\n" in text:
        return lines
    target = len(lines)
    lo, hi = 1, width
    best = lines
    while lo <= hi:
        mid = (lo + hi) // 2
        trial = wrap(draw, text, f, mid)
        if len(trial) <= target and all(draw.textlength(t, font=f) <= mid for t in trial):
            best = trial
            hi = mid - 1
        else:
            lo = mid + 1
    return best


def luminance(img: Image.Image) -> float:
    small = img.convert("L").resize((32, 4))
    px = list(small.getdata())
    return sum(px) / len(px)


def draw_status_bar(shot: Image.Image, device: str) -> None:
    """Hora, señal, wifi y batería en la franja superior de la captura cruda."""
    top, bottom = SAFE[device]
    w, h = shot.size
    strip = shot.crop((0, 0, w, int(top)))
    dark = luminance(strip) > 140
    ink = (20, 20, 20) if dark else (250, 250, 250)
    d = ImageDraw.Draw(shot)
    ios = device in ("iphone", "ipad")
    size = int(top * (0.30 if device == "iphone" else 0.58 if device == "android_phone" else 0.5))
    f = ImageFont.truetype(str(FONTS / ("Inter-SemiBold.ttf" if ios else "Roboto-Medium.ttf")), size)
    cy = top * (0.52 if device == "iphone" else 0.5)
    margin = w * {"iphone": 0.075, "android_phone": 0.085, "android_tablet": 0.04, "ipad": 0.035}[device]
    d.text((margin + (w * 0.03 if device == "iphone" else 0), cy), "9:41", font=f, fill=ink, anchor="lm")
    # Batería
    bh = size * 0.62
    bw = bh * 2.1
    x1 = w - margin - (w * 0.02 if device == "iphone" else 0)
    x0 = x1 - bw
    d.rounded_rectangle((x0, cy - bh / 2, x1, cy + bh / 2), radius=bh * 0.28, outline=ink, width=max(2, int(bh * 0.1)))
    inset = bh * 0.2
    d.rounded_rectangle((x0 + inset, cy - bh / 2 + inset, x1 - inset - bw * 0.15, cy + bh / 2 - inset), radius=bh * 0.15, fill=ink)
    d.rectangle((x1 + bh * 0.06, cy - bh * 0.18, x1 + bh * 0.16, cy + bh * 0.18), fill=ink)
    # Wifi (tres arcos y un punto)
    wx = x0 - bh * 1.4
    for i, r in enumerate((bh * 1.05, bh * 0.72, bh * 0.4)):
        d.arc((wx - r, cy + bh * 0.45 - r, wx + r, cy + bh * 0.45 + r), start=225, end=315, fill=ink, width=max(2, int(bh * 0.16)))
    d.ellipse((wx - bh * 0.1, cy + bh * 0.33, wx + bh * 0.1, cy + bh * 0.53), fill=ink)
    # Señal (cuatro barras)
    sx = wx - bh * 2.3
    for i in range(4):
        bar_h = bh * (0.35 + 0.22 * i)
        bx = sx + i * bh * 0.42
        d.rounded_rectangle((bx, cy + bh / 2 - bar_h, bx + bh * 0.28, cy + bh / 2), radius=bh * 0.06, fill=ink)
    # Indicador de inicio de iOS / barra de gestos de Android
    if bottom > 0:
        bstrip = shot.crop((0, int(h - bottom), w, h))
        bink = (20, 20, 20) if luminance(bstrip) > 140 else (245, 245, 245)
        iw = w * (0.36 if device == "iphone" else 0.12 if device == "ipad" else 0.25)
        ih = max(6, int(bottom * (0.14 if ios else 0.12)))
        by = h - bottom * 0.45
        d.rounded_rectangle((w / 2 - iw / 2, by - ih / 2, w / 2 + iw / 2, by + ih / 2), radius=ih / 2, fill=bink)


def compose(shot: Image.Image, device: str, caption: str, brand: dict) -> Image.Image:
    _store, _folder, (W, H), tablet = TARGETS[device]
    top_color = hex_color(brand["background"][0])
    bottom_color = hex_color(brand["background"][1])
    canvas = Image.new("RGB", (W, H), top_color)
    grad = Image.linear_gradient("L").resize((W, H))
    canvas = Image.composite(Image.new("RGB", (W, H), bottom_color), canvas, grad)
    d = ImageDraw.Draw(canvas)

    # Titular
    pad_x = int(W * 0.08)
    size = int(W * (0.056 if tablet else 0.07))
    f = font("Bold", size)
    lines = balanced_wrap(d, caption, f, W - 2 * pad_x)
    while len(lines) > 3 and size > 20:
        size = int(size * 0.92)
        f = font("Bold", size)
        lines = balanced_wrap(d, caption, f, W - 2 * pad_x)
    line_h = int(size * 1.22)
    y = int(H * (0.045 if tablet else 0.055))
    text_color = hex_color(brand.get("text", "#FFFFFF"))
    for line in lines:
        d.text((W / 2, y), line, font=f, fill=text_color, anchor="ma")
        y += line_h
    accent = brand.get("accent")
    if accent:
        bar_w = int(W * 0.09)
        d.rounded_rectangle((W / 2 - bar_w / 2, y + size * 0.25, W / 2 + bar_w / 2, y + size * 0.25 + max(6, size * 0.12)), radius=size * 0.06, fill=hex_color(accent))
    y += int(size * 1.3)

    # Teléfono o tableta: la captura con marco, sombra y esquinas redondeadas.
    sw, sh = shot.size
    max_w = W * (0.88 if tablet else 0.80)
    # El dispositivo entero cabe: la barra de navegación de la app es parte de lo que se muestra.
    avail_h = H - y - H * 0.035
    scale = min(max_w / sw, avail_h / sh)
    dw, dh = int(sw * scale), int(sh * scale)
    bezel = max(6, int(dw * (0.022 if tablet else 0.03)))
    radius = int(dw * (0.045 if tablet else 0.115))
    x = (W - dw) // 2
    top_y = y
    frame = Image.new("RGBA", (dw + 2 * bezel, dh + 2 * bezel), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle((0, 0, dw + 2 * bezel - 1, dh + 2 * bezel - 1), radius=radius + bezel, fill=(18, 18, 20, 255))
    screen = shot.convert("RGB").resize((dw, dh), Image.LANCZOS)
    mask = Image.new("L", (dw, dh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, dw - 1, dh - 1), radius=radius, fill=255)
    frame.paste(screen, (bezel, bezel), mask)
    # Sombra suave
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = int(dw * 0.02)
    sd.rounded_rectangle((x - bezel + off // 2, top_y - bezel + off, x + dw + bezel + off // 2, top_y + dh + bezel + off), radius=radius + bezel, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(dw * 0.03)))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    canvas.alpha_composite(frame, (x - bezel, top_y - bezel))
    return canvas.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("app")
    ap.add_argument("--raw", help="carpeta de capturas crudas (por defecto apps/<app>/build/store_shots)")
    ap.add_argument("--out", help="carpeta de salida (por defecto apps/<app>/build/store_listing)")
    ap.add_argument("--only", help="idiomas, separados por comas")
    args = ap.parse_args()
    app_dir = ROOT / "apps" / args.app
    raw = Path(args.raw) if args.raw else app_dir / "build" / "store_shots"
    out = Path(args.out) if args.out else app_dir / "build" / "store_listing"
    spec = json.loads((app_dir / "store" / "screenshots.json").read_text(encoding="utf-8"))
    langs = args.only.split(",") if args.only else ["es", "en"]
    made = 0
    missing: list[str] = []
    for device, (store, folder, _size, _tablet) in TARGETS.items():
        platform = "ios" if store == "appstore" else "android"
        for lang in langs:
            n = 0
            for shot in spec["shots"]:
                if platform not in shot.get("platforms", ["android", "ios"]):
                    continue
                if device in shot.get("skip_devices", []):
                    continue
                src = raw / device / lang / f"{shot['id']}.png"
                if not src.exists():
                    missing.append(str(src.relative_to(raw)))
                    continue
                n += 1
                img = Image.open(src).convert("RGB")
                draw_status_bar(img, device)
                result = compose(img, device, shot[lang], spec["brand"])
                dest = out / store / lang / folder / f"{n:02d}-{shot['id']}.png"
                dest.parent.mkdir(parents=True, exist_ok=True)
                result.save(dest, optimize=True)
                made += 1
    print(f"{made} capturas compuestas en {out}")
    if missing:
        print("Faltan capturas crudas:")
        for m in missing:
            print("  - " + m)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
