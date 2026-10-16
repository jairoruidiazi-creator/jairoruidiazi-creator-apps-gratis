#!/usr/bin/env python3
"""Ajusta las carpetas android/ e ios/ generadas por `flutter create`.

Uso: python3 tools/patch_platforms.py <app>   (se ejecuta dentro de apps/<app>)

Cada app declara aquí su nombre visible, permisos y claves de Info.plist. El
script es idempotente: se puede volver a correr sin duplicar nada.
"""
import plistlib
import re
import sys
from pathlib import Path

APPS = {
    "pilas": {
        "display_name": "Pilas",
        "min_sdk": 24,
        "android_permissions": [],
        # flutter_tts necesita consultar el servicio de voz en Android 11+.
        "android_queries": ["android.intent.action.TTS_SERVICE"],
        "ios_plist": {
            "CFBundleDisplayName": "Pilas",
            "ITSAppUsesNonExemptEncryption": False,
        },
        "ios_min": "13.0",
    },
    "clave": {
        "display_name": "Clave",
        "min_sdk": 24,
        "android_permissions": ["android.permission.RECORD_AUDIO", "android.permission.VIBRATE"],
        "android_queries": ["android.intent.action.TTS_SERVICE"],
        "ios_plist": {
            "CFBundleDisplayName": "Clave",
            "ITSAppUsesNonExemptEncryption": False,
            "NSMicrophoneUsageDescription": "Clave usa el micrófono para afinar tu instrumento y grabar tus tomas. El audio no sale del dispositivo.",
            "UIBackgroundModes": ["audio"],
        },
        "ios_min": "13.0",
    },
}


def patch_android(cfg: dict) -> None:
    manifest = Path("android/app/src/main/AndroidManifest.xml")
    text = manifest.read_text(encoding="utf-8")
    text = re.sub(r'android:label="[^"]*"', f'android:label="{cfg["display_name"]}"', text, count=1)
    for perm in cfg["android_permissions"]:
        tag = f'<uses-permission android:name="{perm}"/>'
        if perm not in text:
            text = text.replace("<application", f"    {tag}\n    <application", 1)
    queries = cfg["android_queries"]
    if queries:
        if "<queries>" not in text:
            text = text.replace("</manifest>", "    <queries>\n    </queries>\n</manifest>")
        for action in queries:
            if action not in text:
                intent = f'        <intent>\n            <action android:name="{action}"/>\n        </intent>\n'
                text = text.replace("<queries>\n", "<queries>\n" + intent, 1)
    manifest.write_text(text, encoding="utf-8")

    for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
        gradle = Path(name)
        if not gradle.exists():
            continue
        g = gradle.read_text(encoding="utf-8")
        min_sdk = cfg["min_sdk"]
        if name.endswith(".kts"):
            g = re.sub(r"minSdk\s*=\s*[^\n]+", f"minSdk = {min_sdk}", g, count=1)
        else:
            g = re.sub(r"minSdkVersion\s+[^\n]+", f"minSdkVersion {min_sdk}", g, count=1)
        gradle.write_text(g, encoding="utf-8")
        print(f"minSdk fijado en {min_sdk} en {name}")


def patch_ios(cfg: dict) -> None:
    plist_path = Path("ios/Runner/Info.plist")
    with plist_path.open("rb") as f:
        plist = plistlib.load(f)
    plist.update(cfg["ios_plist"])
    with plist_path.open("wb") as f:
        plistlib.dump(plist, f, sort_keys=False)

    podfile = Path("ios/Podfile")
    if podfile.exists():
        p = podfile.read_text(encoding="utf-8")
        p = re.sub(r"^#\s*platform :ios, '[^']*'", f"platform :ios, '{cfg['ios_min']}'", p, count=1, flags=re.M)
        podfile.write_text(p, encoding="utf-8")

    pbx = Path("ios/Runner.xcodeproj/project.pbxproj")
    if pbx.exists():
        t = pbx.read_text(encoding="utf-8")
        t = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {cfg['ios_min']};", t)
        pbx.write_text(t, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in APPS:
        print(f"Uso: patch_platforms.py <{'|'.join(APPS)}>")
        return 2
    cfg = APPS[sys.argv[1]]
    if Path("android").exists():
        patch_android(cfg)
        print("android/ ajustado")
    if Path("ios").exists():
        patch_ios(cfg)
        print("ios/ ajustado")
    return 0


if __name__ == "__main__":
    sys.exit(main())
