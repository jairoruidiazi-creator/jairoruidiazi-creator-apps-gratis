#!/usr/bin/env python3
"""Revisa las fichas de tienda de una app antes de publicarlas.

Qué comprueba (todo sale de apps/<app>/):

- fastlane/metadata/android/<idioma>/: título (30), descripción corta (80),
  descripción completa (4000) y notas de versión (500) presentes y dentro de
  los límites de Google Play; sin emojis, saltos de línea ni signos repetidos
  en el título y la descripción corta.
- fastlane/metadata/ios/<idioma>/: nombre (30), subtítulo (30), palabras clave
  (100, separadas por comas sin espacios, sin repetir ni copiar el nombre),
  texto promocional (170), descripción (4000) y URL de privacidad y de soporte
  válidas que apunten a archivos que existen en el repositorio.
- Las mismas idiomas en las dos tiendas que en store/screenshots.json.
- Palabras que las tiendas no permiten en títulos, subtítulos, palabras clave,
  titulares de capturas y gráfico de funciones: precio ("gratis", "free"),
  rankings ("mejor", "top", "#1") y llamados a la acción ("descarga ya").
- Que la ficha de una tienda no hable de la otra plataforma (Android en la
  App Store o iPhone en Google Play).
- Que la versión visible en la app (lib/core/app_info.dart) coincida con la de
  pubspec.yaml.
- Que las copias de los archivos compartidos sean idénticas al original:
  tools/shared/dart/legal_document.dart -> lib/ui/legal/legal_document.dart y
  tools/store/dart/store_shots.dart -> test/store/store_shots.dart.

Uso: check_metadata.py <app> [<app>...]   (código de salida 1 si algo falla)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO_URL = "https://github.com/jairoruidiazi-creator/jairoruidiazi-creator-apps-gratis"

PLAY_LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}
PLAY_REQUIRED = tuple(PLAY_LIMITS)
CHANGELOG_LIMIT = 500
IOS_LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "keywords.txt": 100,
    "promotional_text.txt": 170,
    "description.txt": 4000,
    "release_notes.txt": 4000,
}
IOS_REQUIRED = ("name.txt", "subtitle.txt", "keywords.txt", "description.txt", "privacy_url.txt", "support_url.txt")
LOCALES = {"android": {"es": "es-419", "en": "en-US"}, "ios": {"es": "es-MX", "en": "en-US"}}

# Palabras de precio, ranking o promoción que Google Play prohíbe en el título,
# el ícono, las capturas y el gráfico de funciones, y que Apple considera
# metadatos irrelevantes en nombre, subtítulo y palabras clave (2.3.7).
BANNED_COMMON = [r"#\s*1", r"top", r"ad-free"]
BANNED_ES = [
    r"gratis", r"gratuit[oa]s?", r"mejor(es)?", r"n[uú]mero\s+1", r"nuev[oa]s?", r"descuentos?", r"ofertas?",
    r"rebajas?", r"promoci[oó]n", r"descarga(lo|la)?\s+(ya|ahora)", r"instala(lo|la)?\s+(ya|ahora)",
    r"pru[eé]ba(lo|la)?\s+(ya|ahora)", r"millones", r"sin\s+anuncios",
]
BANNED_EN = [
    r"free", r"best", r"number\s+one", r"new", r"discount", r"sale", r"download\s+now", r"install\s+now",
    r"try\s+now", r"million", r"no\s+ads",
]


def banned_re(lang: str) -> re.Pattern[str]:
    words = BANNED_COMMON + (BANNED_ES if lang.startswith("es") else BANNED_EN)
    return re.compile(r"(?<![\w#])(" + "|".join(words) + r")(?![\w])", re.IGNORECASE)


EMOJI_RE = re.compile("[\U0001F000-\U0001FAFF☀-➿️]")
OTHER_PLATFORM = {
    "android": re.compile(r"\b(iPhone|iPad|iOS|App Store|Apple|Face ID|Touch ID)\b"),
    "ios": re.compile(r"\b(Android|Google Play|Play Store)\b"),
}

SHARED_COPIES = [
    ("tools/shared/dart/legal_document.dart", "lib/ui/legal/legal_document.dart"),
    ("tools/store/dart/store_shots.dart", "test/store/store_shots.dart"),
]


class Report:
    def __init__(self, app: str) -> None:
        self.app = app
        self.problems: list[str] = []
        self.notes: list[str] = []

    def fail(self, msg: str) -> None:
        self.problems.append(msg)

    def ok(self, msg: str) -> None:
        self.notes.append(msg)


def read(path: Path) -> str:
    # Las tiendas cuentan caracteres, no bytes; el salto final no cuenta.
    return path.read_text(encoding="utf-8").rstrip("\n")


def check_banned(r: Report, where: str, text: str, lang: str) -> None:
    m = banned_re(lang).search(text)
    if m:
        r.fail(f"{where}: «{m.group(0)}» no se permite en este campo (precio, ranking o promoción)")


def check_play(r: Report, base: Path, locale: str) -> None:
    d = base / "android" / locale
    if not d.is_dir():
        r.fail(f"falta la ficha de Google Play en {locale}")
        return
    for name in PLAY_REQUIRED:
        f = d / name
        if not f.exists():
            r.fail(f"play/{locale}: falta {name}")
            continue
        text = read(f)
        if not text.strip():
            r.fail(f"play/{locale}/{name}: está vacío")
        if len(text) > PLAY_LIMITS[name]:
            r.fail(f"play/{locale}/{name}: {len(text)} caracteres (máximo {PLAY_LIMITS[name]})")
        m = OTHER_PLATFORM["android"].search(text)
        if m:
            r.fail(f"play/{locale}/{name}: menciona «{m.group(0)}», que es de la otra plataforma")
        if name in ("title.txt", "short_description.txt"):
            check_banned(r, f"play/{locale}/{name}", text, locale)
            if "\n" in text:
                r.fail(f"play/{locale}/{name}: no puede tener saltos de línea")
            if EMOJI_RE.search(text):
                r.fail(f"play/{locale}/{name}: no puede llevar emojis")
            if re.search(r"([!?.¡¿])\1", text):
                r.fail(f"play/{locale}/{name}: signos repetidos")
            if name == "title.txt" and re.search(r"\b[A-ZÁÉÍÓÚÑ]{4,}\b", text):
                r.fail(f"play/{locale}/{name}: no se escribe en mayúsculas sostenidas")
    changelogs = sorted((d / "changelogs").glob("*.txt")) if (d / "changelogs").is_dir() else []
    if not changelogs:
        r.fail(f"play/{locale}: faltan las notas de versión (changelogs/<versionCode>.txt)")
    for f in changelogs:
        if not f.stem.isdigit():
            r.fail(f"play/{locale}/changelogs/{f.name}: el nombre debe ser el versionCode")
        if len(read(f)) > CHANGELOG_LIMIT:
            r.fail(f"play/{locale}/changelogs/{f.name}: {len(read(f))} caracteres (máximo {CHANGELOG_LIMIT})")
    r.ok(f"play/{locale}: título «{read(d / 'title.txt')}»" if (d / "title.txt").exists() else f"play/{locale}")


def check_url(r: Report, where: str, url: str) -> None:
    if not re.fullmatch(r"https://\S+", url):
        r.fail(f"{where}: «{url}» no es una URL https")
        return
    prefix = REPO_URL + "/blob/main/"
    if url.startswith(prefix):
        target = ROOT / url[len(prefix):]
        if not target.exists():
            r.fail(f"{where}: apunta a {url[len(prefix):]}, que no existe en el repositorio")


def check_ios(r: Report, base: Path, locale: str) -> None:
    d = base / "ios" / locale
    if not d.is_dir():
        r.fail(f"falta la ficha de la App Store en {locale}")
        return
    for name in IOS_REQUIRED:
        if not (d / name).exists() or not read(d / name).strip():
            r.fail(f"ios/{locale}: falta {name}")
    for name, limit in IOS_LIMITS.items():
        f = d / name
        if not f.exists():
            continue
        text = read(f)
        if len(text) > limit:
            r.fail(f"ios/{locale}/{name}: {len(text)} caracteres (máximo {limit})")
        m = OTHER_PLATFORM["ios"].search(text)
        if m:
            r.fail(f"ios/{locale}/{name}: menciona «{m.group(0)}», que es de la otra plataforma")
        if name in ("name.txt", "subtitle.txt", "keywords.txt"):
            check_banned(r, f"ios/{locale}/{name}", text, locale)
            if "\n" in text:
                r.fail(f"ios/{locale}/{name}: no puede tener saltos de línea")
    kw_file = d / "keywords.txt"
    if kw_file.exists():
        kw = read(kw_file)
        words = kw.split(",")
        if any(w != w.strip() or not w for w in words):
            r.fail(f"ios/{locale}/keywords.txt: sin espacios alrededor de las comas ni palabras vacías")
        lowered = [w.strip().lower() for w in words]
        dup = sorted({w for w in lowered if lowered.count(w) > 1})
        if dup:
            r.fail(f"ios/{locale}/keywords.txt: palabras repetidas {dup}")
        indexed = set()
        for name in ("name.txt", "subtitle.txt"):
            if (d / name).exists():
                indexed |= {t.lower() for t in re.findall(r"[\wÁÉÍÓÚÑáéíóúñ]+", read(d / name))}
        wasted = sorted(w for w in lowered if w in indexed)
        if wasted:
            r.fail(f"ios/{locale}/keywords.txt: {wasted} ya están en el nombre o el subtítulo (la App Store ya las indexa)")
    for name in ("privacy_url.txt", "support_url.txt", "marketing_url.txt"):
        if (d / name).exists():
            check_url(r, f"ios/{locale}/{name}", read(d / name))
    r.ok(f"ios/{locale}: nombre «{read(d / 'name.txt')}»" if (d / "name.txt").exists() else f"ios/{locale}")


def check_screenshots_spec(r: Report, app_dir: Path) -> list[str]:
    f = app_dir / "store" / "screenshots.json"
    if not f.exists():
        r.fail("falta store/screenshots.json (titulares de capturas y gráfico de funciones)")
        return ["es"]
    spec = json.loads(f.read_text(encoding="utf-8"))
    langs = spec.get("languages", ["es", "en"])
    for key in ("name", "brand", "feature", "shots"):
        if key not in spec:
            r.fail(f"store/screenshots.json: falta «{key}»")
    for lang in langs:
        tag = spec.get("feature", {}).get(lang)
        if not tag:
            r.fail(f"store/screenshots.json: falta el lema del gráfico de funciones en {lang}")
        else:
            check_banned(r, f"gráfico de funciones ({lang})", tag, lang)
            if len(tag) > 60:
                r.fail(f"gráfico de funciones ({lang}): {len(tag)} caracteres (máximo 60 para que quepa en dos líneas)")
    ids = [s.get("id", "") for s in spec.get("shots", [])]
    if len(set(ids)) != len(ids):
        r.fail("store/screenshots.json: hay capturas con el mismo id")
    # Hora de la barra de estado (la de la escena de demostración), en formato 24 h.
    for where, value in [("status_time", spec.get("status_time"))] + [(f"{s.get('id')}.status_time", s.get("status_time")) for s in spec.get("shots", [])]:
        if value is not None and not re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", str(value)):
            r.fail(f"store/screenshots.json: {where} debe ser HH:MM en 24 horas (es «{value}»)")
    android = [s for s in spec.get("shots", []) if "android" in s.get("platforms", ["android", "ios"])]
    ios = [s for s in spec.get("shots", []) if "ios" in s.get("platforms", ["android", "ios"])]
    if not 2 <= len(android) <= 8:
        r.fail(f"Google Play pide entre 2 y 8 capturas por tipo de dispositivo; hay {len(android)}")
    if not 1 <= len(ios) <= 10:
        r.fail(f"la App Store pide entre 1 y 10 capturas por tamaño; hay {len(ios)}")
    for s in spec.get("shots", []):
        for lang in langs:
            cap = s.get(lang)
            if not cap:
                r.fail(f"captura {s.get('id')}: falta el titular en {lang}")
                continue
            check_banned(r, f"titular de {s.get('id')} ({lang})", cap, lang)
            if len(cap) > 52:
                r.fail(f"titular de {s.get('id')} ({lang}): {len(cap)} caracteres (máximo 52 para dos líneas)")
            if EMOJI_RE.search(cap):
                r.fail(f"titular de {s.get('id')} ({lang}): sin emojis")
    r.ok(f"capturas: {len(android)} en Android y {len(ios)} en iOS, idiomas {', '.join(langs)}")
    return langs


def check_version(r: Report, app_dir: Path) -> None:
    pub = (app_dir / "pubspec.yaml").read_text(encoding="utf-8")
    m = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$", pub, re.M)
    if not m:
        r.fail("pubspec.yaml: la versión debe tener la forma 1.2.3+4")
        return
    info = app_dir / "lib" / "core" / "app_info.dart"
    if not info.exists():
        r.fail("falta lib/core/app_info.dart con kAppVersion")
        return
    v = re.search(r"kAppVersion\s*=\s*'([^']+)'", info.read_text(encoding="utf-8"))
    if not v or v.group(1) != m.group(1):
        r.fail(f"lib/core/app_info.dart dice {v.group(1) if v else '?'} y pubspec.yaml {m.group(1)}")
    else:
        r.ok(f"versión {m.group(1)} (build {m.group(2)})")
    for f in sorted((app_dir / "fastlane" / "metadata" / "android").glob("*/changelogs/*.txt")):
        if f.stem.isdigit() and int(f.stem) > int(m.group(2)):
            r.fail(f"{f.relative_to(app_dir)}: notas para el versionCode {f.stem}, pero pubspec.yaml va en {m.group(2)}")


def check_shared(r: Report, app_dir: Path) -> None:
    for original, copy in SHARED_COPIES:
        dest = app_dir / copy
        if not dest.exists():
            continue
        if dest.read_bytes() != (ROOT / original).read_bytes():
            r.fail(f"{copy} no es idéntico a {original}; copia de nuevo el original")
        else:
            r.ok(f"{copy} idéntico al original")


def check_app(app: str) -> Report:
    r = Report(app)
    app_dir = ROOT / "apps" / app
    base = app_dir / "fastlane" / "metadata"
    langs = check_screenshots_spec(r, app_dir)
    if not base.is_dir():
        r.fail("falta fastlane/metadata")
    else:
        for lang in langs:
            check_play(r, base, LOCALES["android"][lang])
            check_ios(r, base, LOCALES["ios"][lang])
        extra_play = {p.name for p in (base / "android").iterdir() if p.is_dir()} - {LOCALES["android"][l] for l in langs}
        extra_ios = {p.name for p in (base / "ios").iterdir() if p.is_dir() and p.name != "review_information"} - {LOCALES["ios"][l] for l in langs}
        if extra_play or extra_ios:
            r.fail(f"fichas en idiomas que la app no declara: {sorted(extra_play | extra_ios)}")
        for name in ("copyright.txt", "primary_category.txt"):
            if not (base / "ios" / name).exists():
                r.fail(f"ios: falta {name}")
    check_version(r, app_dir)
    check_shared(r, app_dir)
    return r


def main() -> int:
    apps = sys.argv[1:]
    if not apps:
        print(__doc__)
        return 2
    failed = False
    for app in apps:
        r = check_app(app)
        print(f"== {app}")
        for n in r.notes:
            print("  ok  " + n)
        for p in r.problems:
            print("  ERROR  " + p)
        failed = failed or bool(r.problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
