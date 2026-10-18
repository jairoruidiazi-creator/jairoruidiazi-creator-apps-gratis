#!/usr/bin/env python3
"""Busca fotos libres (dominio público o CC0) en Wikimedia Commons.

Sirve para elegir las fotos de ejemplo de las capturas de tienda de Sello.
Solo acepta licencias que no exigen atribución ni compartir igual, y guarda
autor, licencia y página de origen de cada archivo en candidates.json.

Uso: fetch_commons.py <carpeta_salida> [--max 48] [--width 1800]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://commons.wikimedia.org/w/api.php"
UA = "apps-gratis-store-assets/1.0 (https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis)"

CATEGORIES = [
    "Construction sites in Colombia",
    "Buildings under construction in Colombia",
    "Construction in Bogotá",
    "Road construction in Colombia",
    "Surveying",
    "Surveyors at work",
    "Land surveying",
    "Construction workers",
    "Building construction",
    "Road construction",
    "Bridge construction",
    "Construction sites",
    "Civil engineering",
    "Building inspections",
    "Fieldwork",
    "Coffee plantations in Colombia",
    "Agriculture in Colombia",
]
OK_LICENSES = re.compile(r"^(public domain|pd(-\S+)?|cc0( 1\.0)?|cc-zero)$", re.I)


def api(params: dict) -> dict:
    params = {**params, "format": "json", "formatversion": "2"}
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def strip_html(s: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", s or "")).strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--max", type=int, default=48)
    ap.add_argument("--width", type=int, default=1800)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    found: list[dict] = []
    seen: set[str] = set()
    for cat in CATEGORIES:
        if len(found) >= args.max:
            break
        try:
            data = api({
                "action": "query",
                "generator": "categorymembers",
                "gcmtitle": "Category:" + cat,
                "gcmtype": "file",
                "gcmlimit": "200",
                "prop": "imageinfo",
                "iiprop": "url|size|mime|extmetadata",
                "iiurlwidth": str(args.width),
                "iiextmetadatafilter": "LicenseShortName|Artist|ImageDescription|DateTimeOriginal|UsageTerms",
            })
        except Exception as e:  # noqa: BLE001 - se informa y se sigue
            print(f"[{cat}] error: {e}")
            continue
        pages = data.get("query", {}).get("pages", [])
        print(f"[{cat}] {len(pages)} archivos")
        for p in pages:
            title = p.get("title", "")
            if title in seen or not p.get("imageinfo"):
                continue
            seen.add(title)
            ii = p["imageinfo"][0]
            if ii.get("mime") not in ("image/jpeg", "image/png"):
                continue
            meta = ii.get("extmetadata", {})
            lic = strip_html(meta.get("LicenseShortName", {}).get("value", ""))
            if not OK_LICENSES.match(lic):
                continue
            w, h = ii.get("width", 0), ii.get("height", 0)
            if min(w, h) < 1200:
                continue
            found.append({
                "title": title,
                "category": cat,
                "license": lic,
                "usage_terms": strip_html(meta.get("UsageTerms", {}).get("value", "")),
                "artist": strip_html(meta.get("Artist", {}).get("value", "")),
                "description": strip_html(meta.get("ImageDescription", {}).get("value", ""))[:300],
                "date": strip_html(meta.get("DateTimeOriginal", {}).get("value", "")),
                "page": ii.get("descriptionurl", ""),
                "original": ii.get("url", ""),
                "thumb": ii.get("thumburl", ""),
                "size": [w, h],
            })
            if len(found) >= args.max:
                break
        time.sleep(1)
    for i, f in enumerate(found):
        name = f"{i:02d}.jpg"
        try:
            req = urllib.request.Request(f["thumb"], headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=120) as r:
                (out / name).write_bytes(r.read())
            f["file"] = name
            print(f"descargada {name}: {f['title']} ({f['license']})")
        except Exception as e:  # noqa: BLE001
            print(f"no se pudo descargar {f['title']}: {e}")
        time.sleep(0.5)
    (out / "candidates.json").write_text(json.dumps(found, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(found)} candidatas en {out}")
    return 0 if found else 1


if __name__ == "__main__":
    sys.exit(main())
