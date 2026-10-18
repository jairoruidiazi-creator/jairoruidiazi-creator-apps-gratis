#!/usr/bin/env python3
"""Genera la fuente de respaldo «Simbolos» que usan las apps.

Roboto (la letra de Android y de las capturas de Android) y Lexend no traen
flechas, marcas de verificación ni signos musicales. En el teléfono los pone la
fuente de respaldo del sistema, que cambia según el fabricante, y en las
pruebas de capturas no hay ninguna (salía un cuadro vacío). Con este
subconjunto de DejaVu Sans, declarado como `fontFamilyFallback` en el tema de
cada app, los signos se ven igual en todos los teléfonos y en las capturas.

DejaVu Sans usa la licencia de Bitstream Vera (los cambios de DejaVu son de
dominio público): se puede modificar y redistribuir dentro de las apps si el
resultado no se llama "Bitstream" ni "Vera" y lleva el aviso de copyright y la
licencia (assets/legal/LICENSE-DejaVu.txt, registrada en Licencias).

Uso: python3 tools/gen_symbols_font.py [DejaVuSans.ttf] [DejaVuSans-Bold.ttf]
(por defecto, las del sistema en /usr/share/fonts/truetype/dejavu/).
"""
import shutil
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
APPS = ["clave", "pilas", "plata", "sello"]
FAMILY = "Simbolos"

# Signos que usan las apps y que faltan en Roboto o Lexend.
CODEPOINTS = (
    list(range(0x2190, 0x219A))  # ← ↑ → ↓ ↔ ↕ ↖ ↗ ↘ ↙
    + [0x21C4, 0x21C6]  # ⇄ ⇆
    + list(range(0x2713, 0x2719))  # ✓ ✔ ✕ ✖ ✗ ✘
    + list(range(0x2669, 0x2670))  # ♩ ♪ ♫ ♬ ♭ ♮ ♯
    + [0x2605, 0x2606, 0x26A0]  # ★ ☆ ⚠
    + [0x2248, 0x2260]  # ≈ ≠
)


def build(src: Path, style: str, out: Path) -> None:
    font = TTFont(str(src))
    options = subset.Options()
    options.name_IDs = [0, 13, 14]  # copyright y licencia; el resto se reescribe abajo
    options.name_languages = [0x409]
    options.notdef_outline = True
    options.hinting = False
    options.layout_features = []
    sub = subset.Subsetter(options)
    sub.populate(unicodes=CODEPOINTS)
    sub.subset(font)
    missing = [hex(c) for c in CODEPOINTS if c not in font.getBestCmap()]
    if missing:
        raise SystemExit(f"{src.name} no tiene: {', '.join(missing)}")
    name = font["name"]
    full = f"{FAMILY} {style}" if style != "Regular" else FAMILY
    for nid, value in ((1, FAMILY), (2, style), (3, f"{FAMILY}-{style};subset of DejaVu Sans"), (4, full), (5, "Version 1.0"), (6, f"{FAMILY}-{style}")):
        name.setName(value, nid, 3, 1, 0x409)
        name.setName(value, nid, 1, 0, 0)
    font["OS/2"].usWeightClass = 700 if style == "Bold" else 400
    out.parent.mkdir(parents=True, exist_ok=True)
    font.save(str(out))


def main() -> int:
    regular = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    bold = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
    tmp = ROOT / "build" / "simbolos"
    build(regular, "Regular", tmp / f"{FAMILY}-Regular.ttf")
    build(bold, "Bold", tmp / f"{FAMILY}-Bold.ttf")
    for app in APPS:
        dest = ROOT / "apps" / app / "assets" / "fonts"
        dest.mkdir(parents=True, exist_ok=True)
        for f in tmp.iterdir():
            shutil.copyfile(f, dest / f.name)
        print(f"{app}: {', '.join(sorted(p.name for p in dest.glob(FAMILY + '-*.ttf')))}")
    shutil.rmtree(tmp)
    return 0


if __name__ == "__main__":
    sys.exit(main())
