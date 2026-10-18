#!/usr/bin/env python3
"""Genera las imágenes de la pantalla de arranque de cada app.

Flutter deja en iOS un marcador vacío de 1×1 sobre un fondo blanco fijo (la
compilación lo advierte y en modo oscuro se ve un destello blanco), y en Android
anterior a la 12 un fondo liso sin nada. Con este script cada app arranca con su
ícono centrado sobre el fondo del sistema (blanco o negro según el modo), igual
que la pantalla que Android 12 y posteriores dibujan con el ícono adaptativo.

Salida, por app (se versiona; `tools/patch_platforms.py` la copia a las carpetas
nativas, así que sobrevive a una regeneración con `flutter create`):
  apps/<app>/native/launch/ios/LaunchImage.png, @2x y @3x (120 pt)
  apps/<app>/native/launch/android/drawable-<densidad>/launch_image.png (96 dp)

Uso: python3 tools/gen_launch_assets.py [app ...]   (por defecto, todas)
Requiere Pillow y numpy.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
APPS = ["clave", "pilas", "plata", "rutinas", "sello"]
IOS_POINTS = 120
ANDROID_DP = 96
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
SUPERSAMPLE = 4
# Superelipse |x|^n + |y|^n = 1: con n = 5 se parece a la esquina continua de los
# íconos de iOS y a la máscara redondeada más común en Android.
SQUIRCLE_N = 5.0


def squircle_mask(size: int) -> Image.Image:
    big = size * SUPERSAMPLE
    c = (np.arange(big) + 0.5) / big * 2.0 - 1.0
    x, y = np.meshgrid(c, c)
    inside = (np.abs(x) ** SQUIRCLE_N + np.abs(y) ** SQUIRCLE_N) <= 1.0
    mask = Image.fromarray((inside * 255).astype(np.uint8), "L")
    return mask.resize((size, size), Image.LANCZOS)


def masked_icon(icon: Image.Image, size: int) -> Image.Image:
    rgb = icon.convert("RGB").resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(rgb, (0, 0), squircle_mask(size))
    return out


def build(app: str) -> None:
    app_dir = ROOT / "apps" / app
    icon = Image.open(app_dir / "assets" / "icon" / "icon-1024.png")
    ios = app_dir / "native" / "launch" / "ios"
    ios.mkdir(parents=True, exist_ok=True)
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        masked_icon(icon, IOS_POINTS * scale).save(ios / f"LaunchImage{suffix}.png", optimize=True)
    for name, factor in DENSITIES.items():
        folder = app_dir / "native" / "launch" / "android" / f"drawable-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        masked_icon(icon, round(ANDROID_DP * factor)).save(folder / "launch_image.png", optimize=True)
    print(f"{app}: pantalla de arranque lista")


def main() -> int:
    apps = sys.argv[1:] or APPS
    for app in apps:
        if app not in APPS:
            print(f"App desconocida: {app}")
            return 2
        build(app)
    return 0


if __name__ == "__main__":
    sys.exit(main())
