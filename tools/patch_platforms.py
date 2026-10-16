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
    "sello": {
        "display_name": "Sello",
        "min_sdk": 24,
        "android_permissions": [
            "android.permission.CAMERA",
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.VIBRATE",
            "android.permission.INTERNET",
            # gal la necesita hasta Android 10; camerax declara maxSdkVersion 28, así que se fuerza el valor.
            ("android.permission.WRITE_EXTERNAL_STORAGE", {"android:maxSdkVersion": "29", "tools:replace": "android:maxSdkVersion"}),
        ],
        "android_features": [("android.hardware.camera", False), ("android.hardware.sensor.compass", False), ("android.hardware.location.gps", False)],
        "android_queries": [
            {"action": "android.intent.action.VIEW", "scheme": "geo"},
            {"action": "android.intent.action.VIEW", "scheme": "https"},
        ],
        "ios_plist": {
            "CFBundleDisplayName": "Sello",
            "ITSAppUsesNonExemptEncryption": False,
            "NSCameraUsageDescription": "Sello usa la cámara para tomar las fotos de campo que luego sella con la hora, la ubicación y el rumbo.",
            "NSLocationWhenInUseUsageDescription": "Sello usa tu ubicación para escribir las coordenadas, la altitud y la dirección en cada foto. Los datos quedan en el teléfono.",
            "NSPhotoLibraryAddUsageDescription": "Sello guarda una copia de las fotos selladas en tu fototeca si así lo eliges.",
            "NSPhotoLibraryUsageDescription": "Sello guarda una copia de las fotos selladas en tu fototeca si así lo eliges.",
            "NSMotionUsageDescription": "Sello usa los sensores de movimiento para calcular el rumbo de la cámara.",
            "LSApplicationQueriesSchemes": ["comgooglemaps", "maps", "waze"],
            # La carpeta de la app (fotos, exportaciones) se ve en Archivos y en iCloud Drive del usuario.
            "UIFileSharingEnabled": True,
            "LSSupportsOpeningDocumentsInPlace": True,
        },
        "ios_min": "13.0",
    },
    "plata": {
        "display_name": "Plata",
        "min_sdk": 24,
        "android_permissions": [
            "android.permission.INTERNET",
            "android.permission.POST_NOTIFICATIONS",
            "android.permission.VIBRATE",
            "android.permission.USE_BIOMETRIC",
            # flutter_local_notifications reprograma los recordatorios tras reiniciar.
            "android.permission.RECEIVE_BOOT_COMPLETED",
        ],
        "android_queries": [
            {"action": "android.intent.action.VIEW", "scheme": "https"},
            {"action": "android.intent.action.SENDTO", "scheme": "mailto"},
        ],
        # Dentro de <application>: el lector de avisos bancarios (NotificationListenerService)
        # y los receptores de notificaciones programadas del plugin.
        "android_application_xml": [
            '<service android:name="co.appsgratis.plata.BankNoticeListener" android:exported="true" android:label="Plata: avisos bancarios" android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE">\n            <intent-filter>\n                <action android:name="android.service.notification.NotificationListenerService"/>\n            </intent-filter>\n        </service>',
            '<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>',
            '<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>\n                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>\n            </intent-filter>\n        </receiver>',
        ],
        # Código nativo propio: la actividad (FlutterFragmentActivity por local_auth) y el lector de avisos.
        "android_files": {
            "native/android/MainActivity.kt": "android/app/src/main/kotlin/co/appsgratis/plata/MainActivity.kt",
            "native/android/BankNoticeListener.kt": "android/app/src/main/kotlin/co/appsgratis/plata/BankNoticeListener.kt",
        },
        # flutter_local_notifications 10+ exige desugaring de la biblioteca de Java.
        "android_desugaring": True,
        "ios_plist": {
            "CFBundleDisplayName": "Plata",
            "ITSAppUsesNonExemptEncryption": False,
            "NSFaceIDUsageDescription": "Plata usa Face ID para desbloquear tus cuentas sin escribir la clave.",
            "NSCameraUsageDescription": "Plata usa la cámara para adjuntar la foto de un recibo a un movimiento.",
            "NSPhotoLibraryUsageDescription": "Plata accede a tus fotos para adjuntar un recibo a un movimiento.",
            # La carpeta de la app (exportaciones y copias) se ve en Archivos y en iCloud Drive del usuario.
            "UIFileSharingEnabled": True,
            "LSSupportsOpeningDocumentsInPlace": True,
        },
        "ios_min": "13.0",
    },
}


def patch_android(cfg: dict) -> None:
    manifest = Path("android/app/src/main/AndroidManifest.xml")
    text = manifest.read_text(encoding="utf-8")
    text = re.sub(r'android:label="[^"]*"', f'android:label="{cfg["display_name"]}"', text, count=1)
    for perm in cfg["android_permissions"]:
        attrs = ""
        if isinstance(perm, tuple):
            perm, extra = perm
            attrs = "".join(f' {k}="{v}"' for k, v in extra.items())
            if any(k.startswith("tools:") for k in extra) and 'xmlns:tools=' not in text:
                text = text.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
        tag = f'<uses-permission android:name="{perm}"{attrs}/>'
        if perm not in text:
            text = text.replace("<application", f"    {tag}\n    <application", 1)
        elif attrs and tag not in text:
            # Ya estaba sin los atributos nuevos: se reemplaza la línea.
            text = re.sub(rf'<uses-permission android:name="{re.escape(perm)}"[^>]*/>', tag, text, count=1)
    for feature, required in cfg.get("android_features", []):
        tag = f'<uses-feature android:name="{feature}" android:required="{"true" if required else "false"}"/>'
        if feature not in text:
            text = text.replace("<application", f"    {tag}\n    <application", 1)
    queries = cfg["android_queries"]
    if queries:
        if "<queries>" not in text:
            text = text.replace("</manifest>", "    <queries>\n    </queries>\n</manifest>")
        for q in queries:
            if isinstance(q, str):
                q = {"action": q}
            data = f'            <data android:scheme="{q["scheme"]}"/>\n' if "scheme" in q else ""
            intent = f'        <intent>\n            <action android:name="{q["action"]}"/>\n{data}        </intent>\n'
            if intent not in text:
                text = text.replace("<queries>\n", "<queries>\n" + intent, 1)
    for snippet in cfg.get("android_application_xml", []):
        key = re.search(r'android:name="([^"]+)"', snippet).group(1)
        if key not in text:
            text = text.replace("</application>", f"        {snippet}\n    </application>", 1)
    manifest.write_text(text, encoding="utf-8")

    for src, dst in cfg.get("android_files", {}).items():
        target = Path(dst)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(Path(src).read_text(encoding="utf-8"), encoding="utf-8")
        print(f"copiado {src} -> {dst}")

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
        if cfg.get("android_desugaring") and "coreLibraryDesugaring" not in g:
            if name.endswith(".kts"):
                g = g.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
                g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
            else:
                g = g.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
                g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
            print(f"desugaring activado en {name}")
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
