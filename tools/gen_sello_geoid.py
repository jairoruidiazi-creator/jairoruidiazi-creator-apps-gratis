#!/usr/bin/env python3
"""Genera las rejillas del geoide EGM96 que usa Sello para convertir la altura
elipsoidal del GPS (lo que entrega Android) en altura sobre el nivel del mar.

Fuente: rejilla EGM96 de 5' de la NGA (dominio público), tomada del paquete
Python `egm96` (MIT, https://github.com/xneural-org/egm96). Se escriben dos
archivos binarios de enteros de 16 bits (little-endian) en centímetros:

- assets/geoid/egm96_30m.bin: mundo entero a 30' (361 filas de latitud de −90°
  a 90°, 721 columnas de longitud de −180° a 180°). Error bilineal máximo
  ≈ 1,5 m, típico < 0,3 m.
- assets/geoid/egm96_co_5m.bin: Colombia y vecinos a 5' (latitud −5° a 17°,
  longitud −83° a −66°; 265 × 205 puntos). Exacto respecto al modelo.

Uso: pip install egm96 && python3 tools/gen_sello_geoid.py
"""
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "apps" / "sello" / "assets" / "geoid"


def load_full():
    import importlib.resources

    import egm96.data  # noqa: F401

    resource = importlib.resources.files("egm96.data").joinpath("egm96-5.npz")
    with importlib.resources.as_file(resource) as path:
        d = np.load(path)
        lat = d["latitudes"]
        lon = d["longitudes"]
        cm = np.cumsum(d["undulation_d2"].astype(np.int32), axis=0)
        np.cumsum(cm, axis=1, out=cm)
    return lat, lon, cm


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    lat, lon, cm = load_full()
    assert cm.shape == (2161, 4321)
    # Mundo a 30' (cada 6 puntos de 5').
    world = cm[::6, ::6].astype("<i2")
    assert world.shape == (361, 721)
    (OUT / "egm96_30m.bin").write_bytes(world.tobytes())
    # Colombia a 5'.
    i0 = int(round((-5 + 90) * 12))
    i1 = int(round((17 + 90) * 12))
    j0 = int(round((-83 + 180) * 12))
    j1 = int(round((-66 + 180) * 12))
    co = cm[i0 : i1 + 1, j0 : j1 + 1].astype("<i2")
    assert co.shape == (265, 205), co.shape
    (OUT / "egm96_co_5m.bin").write_bytes(co.tobytes())
    print("mundo:", world.shape, world.nbytes // 1024, "KB; Colombia:", co.shape, co.nbytes // 1024, "KB")
    # Valores de control para las pruebas (Bogotá, Leticia, Cartagena, Múnich).
    for name, la, lo in [("Bogotá", 4.711, -74.0721), ("Leticia", -4.2153, -69.9406), ("Cartagena", 10.39, -75.51), ("Múnich", 48.14, 11.58), ("Sídney", -33.8688, 151.2093)]:
        fi = (la + 90) * 12
        fj = (lo + 180) * 12
        a = int(np.floor(fi))
        b = int(np.floor(fj))
        di = fi - a
        dj = fj - b
        v = (cm[a, b] * (1 - di) * (1 - dj) + cm[a, b + 1] * (1 - di) * dj + cm[a + 1, b] * di * (1 - dj) + cm[a + 1, b + 1] * di * dj) / 100
        print(f"  {name}: N = {v:.2f} m")


if __name__ == "__main__":
    main()
