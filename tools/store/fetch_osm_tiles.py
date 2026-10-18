#!/usr/bin/env python3
"""Descarga, una sola vez, las teselas de OpenStreetMap de las capturas de Sello.

La pantalla del mapa de Sello se dibuja en las pruebas de capturas con teselas
guardadas en apps/sello/test/store/tiles/<z>/<x>/<y>.png, para no pedir teselas
a los servidores de OpenStreetMap en cada ejecución de la CI. Este script baja
solo el bloque pequeño que se ve en las capturas (un nivel de zoom alrededor
del punto de los datos de ejemplo), con un User-Agent propio y una pausa entre
pedidos, como pide la política de uso de teselas:
https://operations.osmfoundation.org/policies/tiles/

Uso: fetch_osm_tiles.py <carpeta> --lat 4.861 --lon -74.059 [--zoom 17] [--rx 3] [--ry 4]
"""
from __future__ import annotations

import argparse
import math
import sys
import time
import urllib.request
from pathlib import Path

UA = "Sello-store-screenshots/1.0 (co.appsgratis.sello; +https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis)"
URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"


def tile_of(lat: float, lon: float, z: int) -> tuple[int, int]:
    n = 2 ** z
    x = int((lon + 180.0) / 360.0 * n)
    lat_r = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_r)) / math.pi) / 2.0 * n)
    return x, y


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--lat", type=float, required=True)
    ap.add_argument("--lon", type=float, required=True)
    ap.add_argument("--zoom", type=int, default=17)
    ap.add_argument("--rx", type=int, default=3)
    ap.add_argument("--ry", type=int, default=4)
    args = ap.parse_args()
    out = Path(args.out)
    cx, cy = tile_of(args.lat, args.lon, args.zoom)
    count = 0
    for x in range(cx - args.rx, cx + args.rx + 1):
        for y in range(cy - args.ry, cy + args.ry + 1):
            dest = out / str(args.zoom) / str(x) / f"{y}.png"
            if dest.exists():
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            req = urllib.request.Request(URL.format(z=args.zoom, x=x, y=y), headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                data = r.read()
            if not data.startswith(b"\x89PNG"):
                print(f"respuesta inesperada para {x},{y}", file=sys.stderr)
                return 1
            dest.write_bytes(data)
            count += 1
            time.sleep(0.4)
    (out / "CREDITOS.md").write_text(
        "# Teselas del mapa de las capturas de Sello\n\n"
        "Teselas de OpenStreetMap descargadas una vez con `tools/store/fetch_osm_tiles.py` "
        f"(zoom {args.zoom}, alrededor de {args.lat}, {args.lon}).\n\n"
        "Datos del mapa © colaboradores de OpenStreetMap, con licencia ODbL; cartografía de "
        "las teselas con licencia CC BY-SA 2.0. https://www.openstreetmap.org/copyright\n\n"
        "Solo se usan para dibujar la pantalla del mapa en las capturas de tienda, que muestran "
        "la atribución de OpenStreetMap igual que la app.\n",
        encoding="utf-8",
    )
    print(f"{count} teselas nuevas en {out} (centro {cx},{cy}, zoom {args.zoom})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
