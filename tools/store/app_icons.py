#!/usr/bin/env python3
"""Revisa el ícono de una app y regenera sus derivados.

Fuente: apps/<app>/assets/icon/icon-1024.png (ícono completo) e
icon-foreground-1024.png (primer plano del ícono adaptativo de Android).

Comprueba que el ícono completo sea cuadrado, de 1024 px y opaco: la App Store
rechaza íconos con canal alfa y tanto iOS como Google Play recortan las
esquinas por su cuenta, así que el dibujo debe llenar todo el cuadrado.

Con --write vuelve a dibujar, al tamaño que ya tiene cada archivo:
  - ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png (RGB, sin alfa)
  - android/app/src/main/res/mipmap-*/ic_launcher.png (ícono heredado)
  - android/app/src/main/res/drawable-*/ic_launcher_foreground.png
Con --play-icon <archivo> escribe el ícono de 512 × 512 de la ficha de Google Play.

Uso: app_icons.py <app> [--write] [--play-icon salida.png]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def check_icon(path: Path) -> list[str]:
    problems: list[str] = []
    im = Image.open(path)
    if im.size != (1024, 1024):
        problems.append(f"{path.name}: mide {im.size[0]}×{im.size[1]}, debe medir 1024×1024")
    if im.mode in ("RGBA", "LA", "PA") or (im.mode == "P" and "transparency" in im.info):
        alpha = im.convert("RGBA").getchannel("A")
        lo, _hi = alpha.getextrema()
        if lo < 255:
            problems.append(f"{path.name}: tiene píxeles transparentes (alfa mínimo {lo}); el ícono debe ser opaco y llenar el cuadrado")
    return problems


def redraw(src: Image.Image, target: Path, mode: str) -> None:
    size = Image.open(target).size
    out = src.convert("RGBA").resize(size, Image.LANCZOS)
    if mode == "RGB":
        out = out.convert("RGB")
    out.save(target, optimize=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("app")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--play-icon")
    args = ap.parse_args()
    app = ROOT / "apps" / args.app
    full = app / "assets" / "icon" / "icon-1024.png"
    fg = app / "assets" / "icon" / "icon-foreground-1024.png"
    problems = check_icon(full)
    if problems:
        for p in problems:
            print("PROBLEMA: " + p)
        return 1
    src = Image.open(full).convert("RGB")
    if args.write:
        n = 0
        for target in sorted((app / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset").glob("*.png")):
            redraw(src, target, "RGB")
            n += 1
        for target in sorted((app / "android" / "app" / "src" / "main" / "res").glob("mipmap-*/ic_launcher.png")):
            redraw(src, target, "RGB")
            n += 1
        if fg.exists():
            fsrc = Image.open(fg).convert("RGBA")
            for target in sorted((app / "android" / "app" / "src" / "main" / "res").glob("drawable-*/ic_launcher_foreground.png")):
                redraw(fsrc, target, "RGBA")
                n += 1
        print(f"{args.app}: {n} íconos redibujados")
    if args.play_icon:
        out = Path(args.play_icon)
        out.parent.mkdir(parents=True, exist_ok=True)
        src.resize((512, 512), Image.LANCZOS).save(out, optimize=True)
        print(f"{args.app}: ícono de Google Play en {out}")
    if not args.write and not args.play_icon:
        print(f"{args.app}: ícono correcto (1024 × 1024, opaco)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
