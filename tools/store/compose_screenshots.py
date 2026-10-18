#!/usr/bin/env python3
"""Compone las imágenes de las fichas de tienda a partir de las capturas crudas.

Entrada: apps/<app>/build/store_shots/<dispositivo>/<idioma>/<id>.png (las
dibujan las pruebas con la etiqueta "screenshots"), los titulares y colores de
apps/<app>/store/screenshots.json y el ícono apps/<app>/assets/icon/icon-1024.png.

Salida (por defecto apps/<app>/build/store_listing/), lista para fastlane:
    android/<es-419|en-US>/images/phoneScreenshots/NN-id.png    1080 × 1920 (9:16)
    android/<es-419|en-US>/images/tenInchScreenshots/NN-id.png  1440 × 2560 (9:16)
    android/<es-419|en-US>/images/featureGraphic.png            1024 × 500
    android/<es-419|en-US>/images/icon.png                      512 × 512
    ios/<es-MX|en-US>/NN-id-iphone69.png                        1320 × 2868 (iPhone 6,9")
    ios/<es-MX|en-US>/NN-id-ipad13.png                          2064 × 2752 (iPad 13")

Requisitos que cumple: Google Play pide PNG o JPEG sin transparencia, 9:16 para
optar a los espacios destacados, titulares que no ocupen más del 20 % de la
imagen y nada de precios, rankings ni llamados a la acción (eso lo revisa
tools/store/check_metadata.py); el gráfico de funciones no lleva imágenes de
dispositivos. App Store Connect pide los tamaños exactos de arriba, sin alfa.

Uso: compose_screenshots.py <app> [--out carpeta] [--only es,en] [--graphics-only]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "tools" / "store" / "fonts"

TARGETS = {
    # dispositivo crudo: (plataforma, carpeta o sufijo, tamaño final, es tableta)
    "android_phone": ("android", "phoneScreenshots", (1080, 1920), False),
    "android_tablet": ("android", "tenInchScreenshots", (1440, 2560), True),
    "iphone": ("ios", "iphone69", (1320, 2868), False),
    "ipad": ("ios", "ipad13", (2064, 2752), True),
}
# Idioma de la app -> idioma de la ficha en cada tienda (español latino y
# español de México, que es el de Latinoamérica en la App Store).
LOCALES = {
    "android": {"es": "es-419", "en": "en-US"},
    "ios": {"es": "es-MX", "en": "en-US"},
}
# Los titulares no pueden ocupar más de esta fracción de la imagen (Google Play: 20 %).
MAX_CAPTION_SHARE = 0.18
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
    flat = getattr(small, "get_flattened_data", None)
    px = list(flat() if flat else small.getdata())
    return sum(px) / len(px)


def status_clock(hhmm: str) -> str:
    """Hora de la barra de estado como la muestran iOS y Android con reloj de
    12 horas (el habitual en Colombia y en EE. UU.): «18:40» → «6:40»."""
    h, m = (int(x) for x in hhmm.split(":"))
    return f"{h % 12 or 12}:{m:02d}"


def draw_status_bar(shot: Image.Image, device: str, clock: str = "9:41") -> None:
    """Hora, señal, wifi y batería en la franja superior de la captura cruda.

    [clock] es la hora de la escena (store/screenshots.json, «status_time»), para
    que la barra no diga 9:41 mientras la app muestra otra hora."""
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
    d.text((margin + (w * 0.03 if device == "iphone" else 0), cy), clock, font=f, fill=ink, anchor="lm")
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

    # Titular: a lo sumo dos líneas y nunca más del 18 % del alto.
    pad_x = int(W * 0.08)
    size = int(W * (0.052 if tablet else 0.066))
    # La franja del titular mide siempre dos líneas del tamaño base, aunque el
    # titular tenga una sola o haya que achicarlo: así el teléfono queda a la
    # misma altura en todas las capturas de la ficha.
    band_h = 2 * int(size * 1.22)
    f = font("Bold", size)
    lines = balanced_wrap(d, caption, f, W - 2 * pad_x)
    while (len(lines) > 2 or len(lines) * size * 1.22 > H * MAX_CAPTION_SHARE) and size > 20:
        size = int(size * 0.94)
        f = font("Bold", size)
        lines = balanced_wrap(d, caption, f, W - 2 * pad_x)
    if len(lines) > 2:
        raise SystemExit(f"El titular no cabe en dos líneas: {caption!r}")
    line_h = int(size * 1.22)
    caption_top = int(H * (0.04 if tablet else 0.045))
    y = caption_top + (band_h - len(lines) * line_h) // 2
    text_color = hex_color(brand.get("text", "#FFFFFF"))
    for line in lines:
        d.text((W / 2, y), line, font=f, fill=text_color, anchor="ma")
        y += line_h
    share = band_h / H
    if share > MAX_CAPTION_SHARE + 1e-6:
        raise SystemExit(f"El titular ocupa {share:.0%} de la imagen: {caption!r}")
    base = band_h / 2.44  # tamaño base del titular (la franja son dos líneas de 1,22)
    accent = brand.get("accent")
    if accent:
        # La raya va pegada al texto; el teléfono, siempre a la misma altura.
        bar_w = int(W * 0.09)
        d.rounded_rectangle((W / 2 - bar_w / 2, y + base * 0.25, W / 2 + bar_w / 2, y + base * 0.25 + max(6, base * 0.12)), radius=base * 0.06, fill=hex_color(accent))
    y = caption_top + band_h + int(base * 1.2)

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


def feature_graphic(app_name: str, tagline: str, icon: Image.Image, brand: dict) -> Image.Image:
    """Gráfico de funciones de Google Play: 1024 × 500, sin dispositivos ni promociones."""
    W, H = 1024, 500
    top_color = hex_color(brand["background"][0])
    bottom_color = hex_color(brand["background"][1])
    grad = Image.linear_gradient("L").rotate(90).resize((W, H))
    canvas = Image.composite(Image.new("RGB", (W, H), top_color), Image.new("RGB", (W, H), bottom_color), grad).convert("RGBA")
    # Ícono con esquinas redondeadas y sombra suave, centrado en vertical.
    side = 250
    ix, iy = 110, (H - side) // 2
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((ix + 6, iy + 12, ix + side + 6, iy + side + 12), radius=int(side * 0.22), fill=(0, 0, 0, 110))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(14)))
    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, side - 1, side - 1), radius=int(side * 0.22), fill=255)
    canvas.paste(icon.convert("RGB").resize((side, side), Image.LANCZOS), (ix, iy), mask)
    d = ImageDraw.Draw(canvas)
    text_color = hex_color(brand.get("text", "#FFFFFF"))
    tx = ix + side + 70
    max_w = W - tx - 60
    name_size = 104
    fn = font("Bold", name_size)
    while d.textlength(app_name, font=fn) > max_w and name_size > 40:
        name_size -= 4
        fn = font("Bold", name_size)
    tag_size = 40
    ft = font("Medium", tag_size)
    lines = balanced_wrap(d, tagline, ft, max_w)
    while len(lines) > 2 and tag_size > 22:
        tag_size -= 2
        ft = font("Medium", tag_size)
        lines = balanced_wrap(d, tagline, ft, max_w)
    if len(lines) > 2:
        raise SystemExit(f"El lema del gráfico de funciones no cabe en dos líneas: {tagline!r}")
    accent_h = 10
    block = name_size * 1.05 + 26 + accent_h + 24 + len(lines) * tag_size * 1.3
    y = (H - block) / 2
    d.text((tx, y), app_name, font=fn, fill=text_color, anchor="la")
    y += name_size * 1.05 + 26
    accent = brand.get("accent")
    if accent:
        d.rounded_rectangle((tx, y, tx + 90, y + accent_h), radius=accent_h / 2, fill=hex_color(accent))
    y += accent_h + 24
    for line in lines:
        d.text((tx, y), line, font=ft, fill=text_color, anchor="la")
        y += tag_size * 1.3
    return canvas.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("app")
    ap.add_argument("--raw", help="carpeta de capturas crudas (por defecto apps/<app>/build/store_shots)")
    ap.add_argument("--out", help="carpeta de salida (por defecto apps/<app>/build/store_listing)")
    ap.add_argument("--only", help="idiomas, separados por comas")
    ap.add_argument("--graphics-only", action="store_true", help="solo el gráfico de funciones y el ícono")
    args = ap.parse_args()
    app_dir = ROOT / "apps" / args.app
    raw = Path(args.raw) if args.raw else app_dir / "build" / "store_shots"
    out = Path(args.out) if args.out else app_dir / "build" / "store_listing"
    spec = json.loads((app_dir / "store" / "screenshots.json").read_text(encoding="utf-8"))
    langs = args.only.split(",") if args.only else spec.get("languages", ["es", "en"])
    icon = Image.open(app_dir / "assets" / "icon" / "icon-1024.png")
    made = 0
    for lang in langs:
        images = out / "android" / LOCALES["android"][lang] / "images"
        images.mkdir(parents=True, exist_ok=True)
        feature_graphic(spec["name"], spec["feature"][lang], icon, spec["brand"]).save(images / "featureGraphic.png", optimize=True)
        icon.convert("RGB").resize((512, 512), Image.LANCZOS).save(images / "icon.png", optimize=True)
        made += 2
    if args.graphics_only:
        print(f"{made} gráficos en {out}")
        return 0
    missing: list[str] = []
    for device, (platform, folder, _size, _tablet) in TARGETS.items():
        for lang in langs:
            n = 0
            locale = LOCALES[platform][lang]
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
                draw_status_bar(img, device, status_clock(shot.get("status_time", spec.get("status_time", "9:41"))))
                result = compose(img, device, shot[lang], spec["brand"])
                name = re.sub(r"^\d+-", "", shot["id"])
                if platform == "android":
                    dest = out / "android" / locale / "images" / folder / f"{n:02d}-{name}.png"
                else:
                    dest = out / "ios" / locale / f"{n:02d}-{name}-{folder}.png"
                dest.parent.mkdir(parents=True, exist_ok=True)
                result.save(dest, optimize=True)
                made += 1
    print(f"{made} imágenes compuestas en {out}")
    if missing:
        print("Faltan capturas crudas:")
        for m in missing:
            print("  - " + m)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
