#!/usr/bin/env python3
"""Genera las láminas para colorear de Pilas como JSON con paths SVG.

Las láminas son dibujos propios (CC BY 4.0 del proyecto). Cada zona lleva un
número y un color sugerido para el modo "por números".

Uso: python3 tools/gen_pilas_coloring.py
"""
import json
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "apps" / "pilas" / "assets" / "coloring"

K = 0.5522847498  # constante de Bézier para cuartos de círculo


def fmt(v: float) -> str:
    s = f"{v:.2f}"
    s = s.rstrip("0").rstrip(".") if "." in s else s
    return s if s != "-0" else "0"


def ellipse(cx, cy, rx, ry):
    kx, ky = rx * K, ry * K
    return (
        f"M{fmt(cx + rx)} {fmt(cy)}"
        f"C{fmt(cx + rx)} {fmt(cy + ky)} {fmt(cx + kx)} {fmt(cy + ry)} {fmt(cx)} {fmt(cy + ry)}"
        f"C{fmt(cx - kx)} {fmt(cy + ry)} {fmt(cx - rx)} {fmt(cy + ky)} {fmt(cx - rx)} {fmt(cy)}"
        f"C{fmt(cx - rx)} {fmt(cy - ky)} {fmt(cx - kx)} {fmt(cy - ry)} {fmt(cx)} {fmt(cy - ry)}"
        f"C{fmt(cx + kx)} {fmt(cy - ry)} {fmt(cx + rx)} {fmt(cy - ky)} {fmt(cx + rx)} {fmt(cy)}Z"
    )


def circle(cx, cy, r):
    return ellipse(cx, cy, r, r)


def poly(points):
    d = f"M{fmt(points[0][0])} {fmt(points[0][1])}"
    for x, y in points[1:]:
        d += f"L{fmt(x)} {fmt(y)}"
    return d + "Z"


def rect(x, y, w, h):
    return poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)])


def rrect(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    k = r * K
    return (
        f"M{fmt(x + r)} {fmt(y)}L{fmt(x + w - r)} {fmt(y)}"
        f"C{fmt(x + w - r + k)} {fmt(y)} {fmt(x + w)} {fmt(y + r - k)} {fmt(x + w)} {fmt(y + r)}"
        f"L{fmt(x + w)} {fmt(y + h - r)}"
        f"C{fmt(x + w)} {fmt(y + h - r + k)} {fmt(x + w - r + k)} {fmt(y + h)} {fmt(x + w - r)} {fmt(y + h)}"
        f"L{fmt(x + r)} {fmt(y + h)}"
        f"C{fmt(x + r - k)} {fmt(y + h)} {fmt(x)} {fmt(y + h - r + k)} {fmt(x)} {fmt(y + h - r)}"
        f"L{fmt(x)} {fmt(y + r)}"
        f"C{fmt(x)} {fmt(y + r - k)} {fmt(x + r - k)} {fmt(y)} {fmt(x + r)} {fmt(y)}Z"
    )


def half_ellipse_top(cx, cy, rx, ry):
    """Semielipse superior cerrada con la base recta."""
    kx, ky = rx * K, ry * K
    return (
        f"M{fmt(cx - rx)} {fmt(cy)}"
        f"C{fmt(cx - rx)} {fmt(cy - ky)} {fmt(cx - kx)} {fmt(cy - ry)} {fmt(cx)} {fmt(cy - ry)}"
        f"C{fmt(cx + kx)} {fmt(cy - ry)} {fmt(cx + rx)} {fmt(cy - ky)} {fmt(cx + rx)} {fmt(cy)}Z"
    )


def arc_line(cx, cy, r, a0, a1, steps=8):
    """Trazo abierto de arco (para sonrisas), en grados."""
    pts = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d = f"M{fmt(pts[0][0])} {fmt(pts[0][1])}"
    for x, y in pts[1:]:
        d += f"L{fmt(x)} {fmt(y)}"
    return d


def line(points):
    d = f"M{fmt(points[0][0])} {fmt(points[0][1])}"
    for x, y in points[1:]:
        d += f"L{fmt(x)} {fmt(y)}"
    return d


def star(cx, cy, r_out, r_in, n=5, rot=-90):
    pts = []
    for i in range(2 * n):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot + 180 / n * i)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return poly(pts)


def petal(cx, cy, angle_deg, length, width):
    """Pétalo elíptico rotado alrededor del centro (cx, cy)."""
    a = math.radians(angle_deg)
    px = cx + math.cos(a) * length / 2
    py = cy + math.sin(a) * length / 2
    # Construye una elipse rotada muestreando puntos (polígono suave).
    pts = []
    for i in range(24):
        t = 2 * math.pi * i / 24
        ex, ey = math.cos(t) * length / 2, math.sin(t) * width / 2
        x = px + ex * math.cos(a) - ey * math.sin(a)
        y = py + ex * math.sin(a) + ey * math.cos(a)
        pts.append((x, y))
    return poly(pts)


# Paleta de colores sugeridos (nombre, hex)
C = {
    "rojo": "#E53935", "naranja": "#FB8C00", "amarillo": "#FDD835", "verde": "#43A047",
    "verdeclaro": "#9CCC65", "azul": "#1E88E5", "celeste": "#4FC3F7", "morado": "#8E24AA",
    "rosado": "#EC407A", "cafe": "#6D4C41", "gris": "#90A4AE", "piel": "#F5CBA7",
    "blanco": "#FFFFFF", "negro": "#263238", "crema": "#FFF3C4",
}


class Page:
    def __init__(self, pid, nombre, min_band=0):
        self.pid = pid
        self.nombre = nombre
        self.min_band = min_band
        self.regions = []
        self.lines = []
        self.colors = []

    def region(self, rid, d, color):
        if color not in self.colors:
            self.colors.append(color)
        self.regions.append({"id": rid, "d": d, "n": self.colors.index(color) + 1, "c": C[color]})

    def line(self, d, w=1.5):
        self.lines.append({"d": d, "w": w})

    def dump(self):
        return {"id": self.pid, "nombre": self.nombre, "vb": [0, 0, 100, 100], "minBand": self.min_band,
                "regions": self.regions, "lines": self.lines}


def page_pez():
    p = Page("pez", "Pez")
    p.region("agua", rect(0, 0, 100, 100), "celeste")
    p.region("cola", poly([(72, 50), (92, 32), (90, 50), (92, 68)]), "naranja")
    p.region("cuerpo", ellipse(48, 50, 30, 20), "amarillo")
    p.region("aleta_arriba", poly([(42, 31), (52, 18), (60, 32)]), "naranja")
    p.region("aleta_abajo", poly([(44, 69), (52, 80), (60, 68)]), "naranja")
    p.region("aleta_lado", ellipse(50, 54, 9, 5), "naranja")
    p.region("ojo", circle(31, 45, 4), "blanco")
    p.region("pupila", circle(30, 45, 1.8), "negro")
    for i, (bx, by, br) in enumerate([(22, 22, 3), (16, 14, 2), (26, 10, 1.5)]):
        p.region(f"burbuja{i}", circle(bx, by, br), "blanco")
    p.region("alga1", poly([(8, 100), (12, 80), (15, 90), (18, 70), (20, 100)]), "verde")
    p.region("alga2", poly([(84, 100), (87, 84), (90, 92), (94, 78), (96, 100)]), "verde")
    p.line(arc_line(27, 52, 5, 10, 80), 1.2)
    return p


def page_casa():
    p = Page("casa", "Casa")
    p.region("cielo", rect(0, 0, 100, 62), "celeste")
    p.region("pasto", rect(0, 62, 100, 38), "verdeclaro")
    p.region("sol", circle(84, 16, 9), "amarillo")
    p.region("pared", rect(22, 42, 56, 40), "crema")
    p.region("techo", poly([(16, 44), (50, 16), (84, 44)]), "rojo")
    p.region("chimenea", rect(62, 22, 8, 14), "cafe")
    p.region("puerta", rrect(44, 58, 12, 24, 2), "cafe")
    p.region("ventana1", rect(28, 50, 11, 11), "amarillo")
    p.region("ventana2", rect(61, 50, 11, 11), "amarillo")
    p.region("arbol_tronco", rect(8, 56, 5, 20), "cafe")
    p.region("arbol_copa", circle(10.5, 50, 9), "verde")
    p.region("nube", ellipse(28, 16, 12, 5), "blanco")
    p.line(line([(33.5, 50), (33.5, 61)]), 1)
    p.line(line([(28, 55.5), (39, 55.5)]), 1)
    p.line(line([(66.5, 50), (66.5, 61)]), 1)
    p.line(line([(61, 55.5), (72, 55.5)]), 1)
    p.line(circle(53, 70, 1), 1)
    return p


def page_gato():
    p = Page("gato", "Gato")
    p.region("fondo", rect(0, 0, 100, 100), "crema")
    p.region("cola", poly([(70, 78), (88, 70), (92, 58), (86, 56), (84, 66), (70, 72)]), "naranja")
    p.region("cuerpo", ellipse(50, 74, 24, 18), "naranja")
    p.region("pata1", ellipse(38, 90, 7, 4), "naranja")
    p.region("pata2", ellipse(62, 90, 7, 4), "naranja")
    p.region("oreja1", poly([(28, 36), (30, 16), (44, 30)]), "naranja")
    p.region("oreja2", poly([(72, 36), (70, 16), (56, 30)]), "naranja")
    p.region("oreja_in1", poly([(32, 34), (33, 22), (41, 31)]), "rosado")
    p.region("oreja_in2", poly([(68, 34), (67, 22), (59, 31)]), "rosado")
    p.region("cabeza", ellipse(50, 42, 24, 20), "naranja")
    p.region("ojo1", ellipse(41, 40, 4, 5), "blanco")
    p.region("ojo2", ellipse(59, 40, 4, 5), "blanco")
    p.region("pupila1", ellipse(41, 41, 1.5, 3), "negro")
    p.region("pupila2", ellipse(59, 41, 1.5, 3), "negro")
    p.region("nariz", poly([(47, 48), (53, 48), (50, 52)]), "rosado")
    p.region("collar", rrect(38, 58, 24, 5, 2), "rojo")
    p.line(line([(50, 52), (50, 56)]), 1)
    p.line(arc_line(46, 55, 4, 10, 170), 1)
    p.line(arc_line(54, 55, 4, 10, 170), 1)
    for y in (46, 50, 54):
        p.line(line([(26, y), (38, y + (50 - y) * 0.2)]), 0.8)
        p.line(line([(74, y), (62, y + (50 - y) * 0.2)]), 0.8)
    return p


def page_carro():
    p = Page("carro", "Carro")
    p.region("cielo", rect(0, 0, 100, 70), "celeste")
    p.region("calle", rect(0, 70, 100, 30), "gris")
    p.region("sol", circle(14, 14, 7), "amarillo")
    p.region("cuerpo", rrect(10, 46, 80, 22, 6), "rojo")
    p.region("cabina", poly([(28, 46), (36, 30), (66, 30), (74, 46)]), "rojo")
    p.region("ventana1", poly([(31, 45), (37, 33), (49, 33), (49, 45)]), "celeste")
    p.region("ventana2", poly([(52, 45), (52, 33), (64, 33), (70, 45)]), "celeste")
    p.region("rueda1", circle(28, 70, 9), "negro")
    p.region("rueda2", circle(72, 70, 9), "negro")
    p.region("rin1", circle(28, 70, 4), "gris")
    p.region("rin2", circle(72, 70, 4), "gris")
    p.region("faro", circle(86, 58, 3), "amarillo")
    p.region("faro_tras", rect(10, 55, 4, 5), "naranja")
    for x in (6, 30, 54, 78):
        p.region(f"linea{x}", rect(x, 88, 14, 3), "blanco")
    p.line(line([(10, 56), (90, 56)]), 1)
    return p


def page_flor():
    p = Page("flor", "Flor")
    p.region("fondo", rect(0, 0, 100, 100), "celeste")
    p.region("pasto", rect(0, 84, 100, 16), "verdeclaro")
    p.region("tallo", rect(48, 50, 4, 36), "verde")
    p.region("hoja1", ellipse(38, 70, 10, 4), "verde")
    p.region("hoja2", ellipse(62, 62, 10, 4), "verde")
    for i in range(6):
        p.region(f"petalo{i}", petal(50, 36, i * 60, 28, 14), ["rosado", "amarillo", "rosado", "amarillo", "rosado", "amarillo"][i % 2 and 1 or 0] if False else "rosado")
    p.region("centro", circle(50, 36, 9), "amarillo")
    p.region("sol", circle(86, 14, 8), "amarillo")
    p.region("mariposa1", ellipse(20, 26, 5, 3.5), "morado")
    p.region("mariposa2", ellipse(28, 26, 5, 3.5), "morado")
    p.region("mariposa_cuerpo", ellipse(24, 26, 1.2, 4), "negro")
    p.line(circle(50, 36, 4), 0.8)
    return p


def page_mariposa():
    p = Page("mariposa", "Mariposa", min_band=1)
    p.region("fondo", rect(0, 0, 100, 100), "crema")
    p.region("ala_sup_izq", ellipse(30, 38, 22, 20), "morado")
    p.region("ala_sup_der", ellipse(70, 38, 22, 20), "morado")
    p.region("ala_inf_izq", ellipse(34, 68, 16, 14), "rosado")
    p.region("ala_inf_der", ellipse(66, 68, 16, 14), "rosado")
    p.region("mancha1", circle(26, 38, 7), "amarillo")
    p.region("mancha2", circle(74, 38, 7), "amarillo")
    p.region("mancha3", circle(32, 68, 5), "celeste")
    p.region("mancha4", circle(68, 68, 5), "celeste")
    p.region("cuerpo", ellipse(50, 52, 5, 24), "negro")
    p.region("cabeza", circle(50, 26, 5), "negro")
    p.line(line([(47, 22), (40, 12)]), 1)
    p.line(line([(53, 22), (60, 12)]), 1)
    p.line(circle(40, 12, 1.5), 1)
    p.line(circle(60, 12, 1.5), 1)
    return p


def page_globos():
    p = Page("globos", "Globos")
    p.region("fondo", rect(0, 0, 100, 100), "celeste")
    globos = [(28, 30, "rojo"), (52, 22, "amarillo"), (74, 32, "verde")]
    for i, (gx, gy, col) in enumerate(globos):
        p.region(f"globo{i}", ellipse(gx, gy, 13, 16), col)
        p.region(f"nudo{i}", poly([(gx - 2, gy + 16), (gx + 2, gy + 16), (gx, gy + 19)]), col)
        p.line(line([(gx, gy + 19), (50, 86)]), 0.8)
    p.region("nube1", ellipse(18, 70, 12, 5), "blanco")
    p.region("nube2", ellipse(82, 64, 10, 4), "blanco")
    p.region("mano", circle(50, 90, 5), "piel")
    return p


def page_helado():
    p = Page("helado", "Helado")
    p.region("fondo", rect(0, 0, 100, 100), "crema")
    p.region("cono", poly([(32, 56), (68, 56), (50, 96)]), "naranja")
    p.region("bola1", circle(50, 44, 18), "rosado")
    p.region("bola2", circle(38, 30, 12), "amarillo")
    p.region("bola3", circle(62, 30, 12), "verdeclaro")
    p.region("cereza", circle(50, 18, 5), "rojo")
    for i, (sx, sy) in enumerate([(44, 48), (56, 40), (50, 56), (40, 38), (60, 50)]):
        p.region(f"chispa{i}", ellipse(sx, sy, 2, 1), "azul")
    for y in (64, 72, 80):
        p.line(line([(32 + (y - 56) * 0.45, y), (68 - (y - 56) * 0.45, y)]), 0.8)
    p.line(line([(50, 13), (53, 6)]), 1)
    return p


def page_cohete():
    p = Page("cohete", "Cohete", min_band=1)
    p.region("espacio", rect(0, 0, 100, 100), "azul")
    p.region("luna", circle(80, 18, 10), "crema")
    for i, (sx, sy) in enumerate([(14, 14), (24, 40), (88, 50), (12, 70), (90, 84), (70, 92)]):
        p.region(f"estrella{i}", star(sx, sy, 3.5, 1.5), "amarillo")
    p.region("fuego", poly([(42, 78), (50, 96), (58, 78)]), "naranja")
    p.region("fuego_in", poly([(46, 78), (50, 88), (54, 78)]), "amarillo")
    p.region("aleta1", poly([(36, 60), (26, 78), (38, 78)]), "rojo")
    p.region("aleta2", poly([(64, 60), (74, 78), (62, 78)]), "rojo")
    p.region("cuerpo", rrect(36, 30, 28, 48, 10), "gris")
    p.region("punta", half_ellipse_top(50, 32, 14, 16), "rojo")
    p.region("ventana", circle(50, 48, 7), "celeste")
    p.region("ventana_marco", circle(50, 48, 3), "blanco")
    p.line(line([(36, 66), (64, 66)]), 1)
    return p


def page_arbol():
    p = Page("arbol", "Árbol")
    p.region("cielo", rect(0, 0, 100, 72), "celeste")
    p.region("pasto", rect(0, 72, 100, 28), "verdeclaro")
    p.region("tronco", rect(44, 52, 12, 30), "cafe")
    p.region("copa1", circle(50, 36, 22), "verde")
    p.region("copa2", circle(32, 46, 14), "verde")
    p.region("copa3", circle(68, 46, 14), "verde")
    for i, (ax, ay) in enumerate([(40, 30), (58, 26), (50, 46), (30, 44), (70, 44)]):
        p.region(f"manzana{i}", circle(ax, ay, 3.2), "rojo")
    p.region("sol", circle(14, 14, 8), "amarillo")
    p.region("flor1", circle(20, 86, 2.5), "rosado")
    p.region("flor2", circle(80, 88, 2.5), "amarillo")
    p.line(line([(50, 60), (50, 80)]), 0.8)
    p.line(line([(50, 68), (46, 62)]), 0.8)
    return p


def page_tortuga():
    p = Page("tortuga", "Tortuga", min_band=1)
    p.region("fondo", rect(0, 0, 100, 100), "crema")
    p.region("pasto", rect(0, 76, 100, 24), "verdeclaro")
    p.region("pata1", ellipse(30, 74, 7, 5), "verde")
    p.region("pata2", ellipse(68, 74, 7, 5), "verde")
    p.region("cola", poly([(20, 64), (10, 70), (22, 70)]), "verde")
    p.region("cabeza", circle(82, 58, 9), "verde")
    p.region("caparazon", half_ellipse_top(50, 70, 32, 30), "cafe")
    for i, (hx, hy, r) in enumerate([(50, 52, 8), (36, 60, 6), (64, 60, 6), (46, 66, 4), (56, 66, 4)]):
        p.region(f"placa{i}", circle(hx, hy, r), "amarillo")
    p.region("borde", rect(18, 68, 64, 4), "naranja")
    p.region("ojo", circle(85, 55, 2), "blanco")
    p.region("pupila", circle(85.5, 55, 1), "negro")
    p.line(arc_line(84, 60, 3, 20, 160), 1)
    return p


def page_bus():
    p = Page("bus", "Bus escolar", min_band=1)
    p.region("cielo", rect(0, 0, 100, 68), "celeste")
    p.region("calle", rect(0, 68, 100, 32), "gris")
    p.region("cuerpo", rrect(6, 28, 88, 40, 6), "amarillo")
    for i in range(4):
        p.region(f"ventana{i}", rect(14 + i * 18, 34, 13, 12), "celeste")
    p.region("puerta", rect(80, 40, 10, 26), "naranja")
    p.region("franja", rect(6, 50, 74, 5), "negro")
    p.region("rueda1", circle(24, 68, 8), "negro")
    p.region("rueda2", circle(70, 68, 8), "negro")
    p.region("rin1", circle(24, 68, 3.5), "gris")
    p.region("rin2", circle(70, 68, 3.5), "gris")
    p.region("faro", circle(91, 60, 2.5), "blanco")
    p.region("letrero", rrect(30, 20, 40, 8, 2), "blanco")
    p.region("nube", ellipse(20, 14, 10, 4), "blanco")
    p.line(line([(80, 53), (90, 53)]), 0.8)
    return p


PAGES = [page_pez, page_casa, page_gato, page_carro, page_flor, page_globos, page_helado, page_arbol, page_mariposa, page_cohete, page_tortuga, page_bus]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    names = []
    for fn in PAGES:
        page = fn()
        data = page.dump()
        fname = f"{page.pid}.json"
        (OUT / fname).write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        names.append(fname)
        print(f"{fname}: {len(page.regions)} zonas, {len(page.colors)} colores")
    (OUT / "index.json").write_text(json.dumps({"pages": names}, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
