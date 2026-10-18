#!/usr/bin/env python3
"""Revisa un APK o AAB antes de publicarlo en Google Play.

Comprueba, sin dependencias externas:

1. Páginas de 16 KB: cada biblioteca nativa de 64 bits (arm64-v8a y x86_64)
   debe tener todos sus segmentos PT_LOAD alineados a 16 KB o más. Es un
   requisito de Google Play para las apps que apuntan a Android 15 o superior.
   https://developer.android.com/guide/practices/page-sizes
2. Alineación dentro del ZIP (solo APK): las bibliotecas guardadas sin
   comprimir deben empezar en un múltiplo de 16 KB para poder mapearse
   directamente (equivale a `zipalign -c -P 16 4`).
3. Opcionalmente, con --badging <archivo>, lee la salida de
   `aapt2 dump badging` y exige un targetSdkVersion mínimo y que no se
   declaren permisos prohibidos (por ejemplo AD_ID en apps para niños).
4. Opcionalmente, con --manifest-tree <archivo> (salida de
   `aapt2 dump xmltree --file AndroidManifest.xml`), exige atributos de
   <application> como android:allowBackup=false (config "application").

Uso:
    check_android_package.py app-release.apk [--badging badging.txt]
        [--min-target-sdk 36] [--forbid-permission android.permission.X]...
        [--allow-permission ...]...

Termina con código 1 si algo falla y escribe un informe legible.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import zipfile

PAGE = 16384
PT_LOAD = 1
ABIS_64 = ("arm64-v8a", "x86_64")


def elf_load_alignments(data: bytes) -> list[int]:
    """Alineaciones (p_align) de los segmentos PT_LOAD de un ELF."""
    if data[:4] != b"\x7fELF":
        raise ValueError("no es un ELF")
    ei_class = data[4]
    endian = "<" if data[5] == 1 else ">"
    if ei_class == 2:  # ELF64
        e_phoff = struct.unpack_from(endian + "Q", data, 0x20)[0]
        e_phentsize, e_phnum = struct.unpack_from(endian + "HH", data, 0x36)
        out = []
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            p_type = struct.unpack_from(endian + "I", data, off)[0]
            if p_type == PT_LOAD:
                p_align = struct.unpack_from(endian + "Q", data, off + 0x30)[0]
                out.append(p_align)
        return out
    if ei_class == 1:  # ELF32
        e_phoff = struct.unpack_from(endian + "I", data, 0x1C)[0]
        e_phentsize, e_phnum = struct.unpack_from(endian + "HH", data, 0x2A)
        out = []
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            p_type = struct.unpack_from(endian + "I", data, off)[0]
            if p_type == PT_LOAD:
                p_align = struct.unpack_from(endian + "I", data, off + 0x1C)[0]
                out.append(p_align)
        return out
    raise ValueError(f"clase ELF desconocida {ei_class}")


def local_header_data_offset(zf: zipfile.ZipFile, info: zipfile.ZipInfo) -> int:
    """Desplazamiento real de los datos de una entrada dentro del ZIP."""
    fp = zf.fp
    assert fp is not None
    fp.seek(info.header_offset)
    header = fp.read(30)
    if header[:4] != b"PK\x03\x04":
        raise ValueError(f"cabecera local inválida en {info.filename}")
    name_len, extra_len = struct.unpack_from("<HH", header, 26)
    return info.header_offset + 30 + name_len + extra_len


def check_archive(path: str) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    report: list[str] = []
    is_aab = path.endswith(".aab")
    with zipfile.ZipFile(path) as zf:
        libs = [i for i in zf.infolist() if i.filename.endswith(".so") and "/lib/" in "/" + i.filename]
        if not libs:
            report.append("Sin bibliotecas nativas.")
        for info in libs:
            parts = info.filename.split("/")
            abi = parts[-2] if len(parts) >= 2 else "?"
            data = zf.read(info)
            try:
                aligns = elf_load_alignments(data)
            except ValueError as e:
                problems.append(f"{info.filename}: {e}")
                continue
            worst = min(aligns) if aligns else 0
            ok_elf = abi not in ABIS_64 or worst >= PAGE
            line = f"{info.filename}: PT_LOAD min 2**{worst.bit_length() - 1 if worst else 0}"
            if not is_aab and info.compress_type == zipfile.ZIP_STORED:
                offset = local_header_data_offset(zf, info)
                zip_ok = abi not in ABIS_64 or offset % PAGE == 0
                line += f", sin comprimir, desplazamiento {offset} ({'alineado' if zip_ok else 'NO alineado'} a 16 KB)"
                if not zip_ok:
                    problems.append(f"{info.filename}: datos sin comprimir no alineados a 16 KB (desplazamiento {offset})")
            elif not is_aab:
                line += ", comprimida (se extrae al instalar)"
            report.append(line + ("" if ok_elf else "  <-- NO cumple 16 KB"))
            if not ok_elf:
                problems.append(f"{info.filename}: segmentos PT_LOAD alineados a {worst} bytes (< 16384)")
    return problems, report


def check_badging(path: str, min_target: int | None, forbid: list[str], allow: list[str] | None, max_sdk: dict[str, int] | None = None) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    report: list[str] = []
    text = open(path, encoding="utf-8", errors="replace").read()
    pkg = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'", text)
    if pkg:
        report.append(f"Paquete {pkg.group(1)}, versionCode {pkg.group(2)}, versionName {pkg.group(3)}")
    target = re.search(r"targetSdkVersion:'(\d+)'", text)
    min_sdk = re.search(r"(?:minSdkVersion|sdkVersion):'(\d+)'", text)
    if min_sdk:
        report.append(f"minSdk {min_sdk.group(1)}")
    if target:
        report.append(f"targetSdk {target.group(1)}")
        if min_target is not None and int(target.group(1)) < min_target:
            problems.append(f"targetSdkVersion {target.group(1)} < {min_target} (requisito de Google Play)")
    elif min_target is not None:
        problems.append("no se encontró targetSdkVersion en el badging")
    perms = sorted(set(re.findall(r"uses-permission: name='([^']+)'", text)))
    report.append("Permisos: " + (", ".join(perms) if perms else "ninguno"))
    for p in forbid:
        if p in perms:
            problems.append(f"permiso prohibido presente: {p}")
    if allow is not None:
        extra = [p for p in perms if p not in allow and not p.endswith(".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION")]
        if extra:
            problems.append("permisos no previstos: " + ", ".join(extra))
    # Permisos que solo se piden en versiones viejas de Android: deben llevar
    # maxSdkVersion y no pasar del tope (si no están, mejor).
    for name, limit in sorted((max_sdk or {}).items()):
        decl = re.findall(r"uses-permission: name='" + re.escape(name) + r"'(?: maxSdkVersion='(\d+)')?", text)
        for found in decl:
            if not found or int(found) > limit:
                problems.append(f"{name} debe llevar maxSdkVersion <= {limit} (tiene {found or 'ninguno'})")
            else:
                report.append(f"{name} solo hasta API {found}")
    return problems, report


def check_manifest_tree(path: str, required: dict[str, str]) -> tuple[list[str], list[str]]:
    """Atributos de <application> en el manifiesto compilado.

    Valores en la config: "false"/"true" para booleanos, "@ref" para exigir
    que el atributo apunte a un recurso, o un texto literal.
    """
    problems: list[str] = []
    report: list[str] = []
    text = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"^(\s*)E: application\b.*$", text, re.M)
    if not m:
        return ["no se encontró <application> en el manifiesto"], report
    indent = len(m.group(1))
    attrs: dict[str, str] = {}
    for line in text[m.end():].splitlines()[1:]:
        stripped = line.lstrip()
        depth = len(line) - len(stripped)
        if depth <= indent or stripped.startswith("E: "):
            break
        a = re.match(r'A: (?:http://schemas\.android\.com/apk/res/android:|android:)(\w+)\(0x[0-9a-f]+\)=(.*)$', stripped)
        if a:
            # aapt2 escribe `=false`; aapt (v1) escribe `=(type 0x12)0x0`.
            attrs[a.group(1)] = re.sub(r"^\(type 0x[0-9a-f]+\)", "", a.group(2).strip())
    for name, want in required.items():
        got = attrs.get(name)
        if got is None:
            problems.append(f"<application> no declara android:{name}")
            continue
        if want in ("false", "true"):
            ok = got.lower() in ((want, "0x0", "0") if want == "false" else (want, "0xffffffff", "-1", "1"))
        elif want == "@ref":
            ok = got.startswith("@")
        else:
            ok = got.strip('"').split('" (Raw')[0] == want
        report.append(f"application android:{name} = {got}")
        if not ok:
            problems.append(f"android:{name} vale {got}, se esperaba {want}")
    return problems, report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("package", help="APK o AAB")
    ap.add_argument("--badging", help="salida de `aapt2 dump badging` del APK")
    ap.add_argument("--min-target-sdk", type=int)
    ap.add_argument("--forbid-permission", action="append", default=[])
    ap.add_argument("--allow-permission", action="append", default=None, help="si se da, todo permiso fuera de la lista falla")
    ap.add_argument("--manifest-tree", help="salida de `aapt2 dump xmltree --file AndroidManifest.xml` del APK")
    ap.add_argument("--config", help="JSON con min_target_sdk, forbid, allow, max_sdk y application por app (tools/store/android.json)")
    ap.add_argument("--app", help="app dentro del JSON de --config")
    args = ap.parse_args()
    if args.config:
        conf = json.load(open(args.config, encoding="utf-8"))
        common = conf.get("*", {})
        app = conf.get(args.app or "", {})
        if args.min_target_sdk is None:
            args.min_target_sdk = app.get("min_target_sdk", common.get("min_target_sdk"))
        # Lo que una app permite de forma explícita sale de la lista común de
        # prohibidos (por ejemplo, las alarmas exactas del temporizador de Rutinas).
        allowed = set(app.get("allow", []))
        args.forbid_permission += [p for p in common.get("forbid", []) if p not in allowed] + app.get("forbid", [])
        if args.allow_permission is None and "allow" in app:
            args.allow_permission = app["allow"]
        application = app.get("application", {})
        max_sdk = {k: int(v) for k, v in app.get("max_sdk", {}).items()}
    else:
        application = {}
        max_sdk = {}

    problems, report = check_archive(args.package)
    if args.badging:
        p2, r2 = check_badging(args.badging, args.min_target_sdk, args.forbid_permission, args.allow_permission, max_sdk)
        problems += p2
        report = r2 + report
    if args.manifest_tree and application:
        p3, r3 = check_manifest_tree(args.manifest_tree, application)
        problems += p3
        report = r3 + report
    elif application:
        problems.append("la config exige atributos de <application> pero falta --manifest-tree")
    print(f"== {args.package}")
    for line in report:
        print("  " + line)
    if problems:
        print("PROBLEMAS:")
        for p in problems:
            print("  - " + p)
        return 1
    print("OK: cumple 16 KB" + (" y los requisitos del badging" if args.badging else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
