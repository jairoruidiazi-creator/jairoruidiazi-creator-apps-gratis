#!/usr/bin/env python3
"""Ajusta las carpetas android/ e ios/ generadas por `flutter create`.

Uso: python3 tools/patch_platforms.py <app>   (se ejecuta dentro de apps/<app>)

Cada app declara aquí su nombre visible, permisos y claves de Info.plist. El
script es idempotente: se puede volver a correr sin duplicar nada.
"""
import hashlib
import plistlib
import re
import shutil
import sys
from pathlib import Path

# Firma de release: si existe android/key.properties (la CI lo escribe con los
# secretos de la llave de subida), se firma con ella; si no, con la de depuración
# para que `flutter build apk --release` siga funcionando en local.
SIGNING_HEADER = """import java.io.FileInputStream
import java.util.Properties

"""
SIGNING_PROPS = """
// Llave de subida a Google Play (ver docs/PUBLICACION.md). Nunca se versiona.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
"""
SIGNING_CONFIGS = """    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {"""

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
            # Solo aparece si un adulto, al compartir un dibujo, elige "Guardar imagen" (M21).
            "NSPhotoLibraryAddUsageDescription": "Pilas usa este permiso solo si un adulto, al compartir un dibujo, elige guardarlo en las fotos del teléfono.",
        },
        "ios_strings_en": {
            "CFBundleDisplayName": "Pilas",
            "NSPhotoLibraryAddUsageDescription": "Pilas only uses this permission if an adult, when sharing a drawing, chooses to save it to the phone's photos.",
        },
        # La app solo está en español: la App Store no debe listar el inglés (M2).
        "ios_localizations": ["es"],
        # Sin acciones de texto de otras apps (buscar, traducir) que saquen al niño
        # de la app sin la puerta para adultos (G15).
        "android_remove_process_text": True,
        # Los niños juegan en tabletas y teléfonos en cualquier posición.
        "iphone_orientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
        "ios_privacy_collected": [],
        "ios_min": "15.0",
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
        "ios_strings_en": {
            "CFBundleDisplayName": "Clave",
            "NSMicrophoneUsageDescription": "Clave uses the microphone to tune your instrument and record your takes. The audio never leaves the device.",
        },
        "iphone_orientations": ["UIInterfaceOrientationPortrait"],
        "ios_privacy_collected": [],
        "ios_min": "15.0",
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
            # La fusión de manifiestos agrega la lectura implícita sin límite; Sello no lee
            # el almacenamiento compartido (los archivos se eligen con el selector del
            # sistema), así que queda con el mismo tope que la escritura.
            ("android.permission.READ_EXTERNAL_STORAGE", {"android:maxSdkVersion": "29", "tools:node": "replace"}),
            # El plugin de cámara declara el micrófono para grabar video; Sello solo toma fotos.
            ("android.permission.RECORD_AUDIO", {"tools:node": "remove"}),
        ],
        # El enfoque automático tampoco es obligatorio: los equipos de foco fijo sirven (M16).
        "android_features": [("android.hardware.camera", False), ("android.hardware.camera.autofocus", False), ("android.hardware.sensor.compass", False), ("android.hardware.location.gps", False)],
        # gal escribe el álbum "Sello" con la ruta clásica en Android 10 (API 29); sin
        # esto el almacenamiento con alcance lo bloquea. Desde Android 11 se ignora.
        # Reglas de copia: la nube de Google (25 MB por app) no lleva las fotos ni su
        # índice; el traspaso entre teléfonos lleva todo.
        "android_application_attrs": {
            "android:requestLegacyExternalStorage": "true",
            "android:dataExtractionRules": "@xml/data_extraction_rules",
            "android:fullBackupContent": "@xml/backup_rules",
        },
        # Código nativo propio: la altura elipsoidal del GPS (Android), el rumbo calibrado
        # del sistema (iOS) y las reglas de copia de seguridad.
        "android_files": {
            "native/android/MainActivity.kt": "android/app/src/main/kotlin/co/appsgratis/sello/MainActivity.kt",
            "native/android/data_extraction_rules.xml": "android/app/src/main/res/xml/data_extraction_rules.xml",
            "native/android/backup_rules.xml": "android/app/src/main/res/xml/backup_rules.xml",
        },
        "ios_files": {
            "native/ios/AppDelegate.swift": "ios/Runner/AppDelegate.swift",
        },
        "android_queries": [
            {"action": "android.intent.action.VIEW", "scheme": "geo"},
            {"action": "android.intent.action.VIEW", "scheme": "https"},
        ],
        "ios_plist": {
            "CFBundleDisplayName": "Sello",
            "ITSAppUsesNonExemptEncryption": False,
            "NSCameraUsageDescription": "Sello usa la cámara para tomar las fotos de campo que luego sella con la hora, la ubicación y el rumbo.",
            "NSLocationWhenInUseUsageDescription": "Sello usa tu ubicación para escribir en cada foto las coordenadas, la altitud y la dirección aproximada. Tus fotos y coordenadas se guardan solo en el teléfono.",
            "NSPhotoLibraryAddUsageDescription": "Sello guarda una copia de las fotos selladas en tu fototeca si así lo eliges.",
            "NSPhotoLibraryUsageDescription": "Sello guarda una copia de las fotos selladas en tu fototeca si así lo eliges.",
            "NSMotionUsageDescription": "Sello usa los sensores de movimiento para calcular el rumbo de la cámara.",
            # El complemento de cámara enlaza la grabación de audio: sin el texto, App Store
            # Connect devuelve ITMS-90683 aunque Sello nunca pida el micrófono (M17).
            "NSMicrophoneUsageDescription": "Sello solo toma fotos: no usa el micrófono ni graba audio.",
            "LSApplicationQueriesSchemes": ["comgooglemaps", "maps", "waze"],
            # La carpeta de la app (fotos y exportaciones) se ve en la app Archivos, en "En mi iPhone".
            "UIFileSharingEnabled": True,
            "LSSupportsOpeningDocumentsInPlace": True,
        },
        "ios_strings_en": {
            "CFBundleDisplayName": "Sello",
            "NSCameraUsageDescription": "Sello uses the camera to take the field photos it then stamps with the time, location and heading.",
            "NSLocationWhenInUseUsageDescription": "Sello uses your location to write the coordinates, altitude and approximate address on each photo. Your photos and coordinates are stored only on your phone.",
            "NSPhotoLibraryAddUsageDescription": "Sello saves a copy of the stamped photos to your photo library if you choose to.",
            "NSPhotoLibraryUsageDescription": "Sello saves a copy of the stamped photos to your photo library if you choose to.",
            "NSMotionUsageDescription": "Sello uses the motion sensors to work out the camera heading.",
            "NSMicrophoneUsageDescription": "Sello only takes photos: it does not use the microphone or record audio.",
        },
        # Cámara: la interfaz va en vertical y el sello sigue la orientación del teléfono.
        "iphone_orientations": ["UIInterfaceOrientationPortrait"],
        # La dirección aproximada (geocodificador del sistema) y las teselas del mapa
        # (OpenStreetMap) envían coordenadas fuera del teléfono; ambas son opcionales.
        "ios_privacy_collected": [
            {"type": "NSPrivacyCollectedDataTypePreciseLocation", "linked": False, "tracking": False, "purposes": ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]},
        ],
        "ios_min": "15.0",
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
        # Código nativo propio: la actividad (FlutterFragmentActivity por local_auth), el lector de
        # avisos y las reglas que dejan los datos cifrados fuera de la copia de Google y del traspaso.
        "android_files": {
            "native/android/MainActivity.kt": "android/app/src/main/kotlin/co/appsgratis/plata/MainActivity.kt",
            "native/android/BankNoticeListener.kt": "android/app/src/main/kotlin/co/appsgratis/plata/BankNoticeListener.kt",
            "native/android/data_extraction_rules.xml": "android/app/src/main/res/xml/data_extraction_rules.xml",
        },
        "android_application_attrs": {
            "android:allowBackup": "false",
            "android:dataExtractionRules": "@xml/data_extraction_rules",
        },
        # La carpeta de datos queda fuera de la copia de iCloud (la llave no viaja).
        "ios_files": {
            "native/ios/AppDelegate.swift": "ios/Runner/AppDelegate.swift",
        },
        # flutter_local_notifications 10+ exige desugaring de la biblioteca de Java.
        "android_desugaring": True,
        "ios_plist": {
            "CFBundleDisplayName": "Plata",
            # Cifra los datos con ChaCha20-Poly1305 (algoritmo estándar que no es el del sistema):
            # App Store Connect hace las preguntas de exportación en cada versión (ver store/COMPLIANCE.md).
            "ITSAppUsesNonExemptEncryption": True,
            "NSFaceIDUsageDescription": "Plata usa Face ID para desbloquear tus cuentas sin escribir la clave.",
            "NSCameraUsageDescription": "Plata usa la cámara para adjuntar la foto de un recibo a un movimiento.",
            "NSPhotoLibraryUsageDescription": "Plata accede a tus fotos para adjuntar un recibo a un movimiento.",
        },
        # Los datos viven en Application Support, fuera de la app Archivos: no hay carpeta que mostrar.
        "ios_plist_remove": ["UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace"],
        "ios_strings_en": {
            "CFBundleDisplayName": "Plata",
            "NSFaceIDUsageDescription": "Plata uses Face ID to unlock your accounts without typing the passcode.",
            "NSCameraUsageDescription": "Plata uses the camera to attach a photo of a receipt to a transaction.",
            "NSPhotoLibraryUsageDescription": "Plata accesses your photos to attach a receipt to a transaction.",
        },
        "iphone_orientations": ["UIInterfaceOrientationPortrait"],
        "ios_privacy_collected": [],
        "ios_min": "15.0",
    },
    "rutinas": {
        "display_name": "Rutinas",
        "min_sdk": 24,
        "android_permissions": [
            "android.permission.POST_NOTIFICATIONS",
            # Avisos del temporizador y de los recordatorios a la hora exacta, si el
            # usuario lo concede (Android 14 lo niega de entrada); sin él, la app usa
            # alarmas inexactas y lo explica en Ajustes.
            "android.permission.SCHEDULE_EXACT_ALARM",
            # flutter_local_notifications reprograma los avisos tras reiniciar.
            "android.permission.RECEIVE_BOOT_COMPLETED",
            "android.permission.VIBRATE",
        ],
        # flutter_tts necesita consultar el servicio de voz en Android 11+.
        "android_queries": ["android.intent.action.TTS_SERVICE"],
        # Receptores de las notificaciones programadas del plugin (y de su
        # reprogramación al reiniciar o actualizar la app).
        "android_application_xml": [
            '<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>',
            '<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>\n                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>\n            </intent-filter>\n        </receiver>',
        ],
        # Ícono de la barra de estado y lista de recursos que la compilación no debe quitar.
        "android_files": {
            "native/android/ic_stat_rutinas.xml": "android/app/src/main/res/drawable/ic_stat_rutinas.xml",
            "native/android/keep.xml": "android/app/src/main/res/raw/keep.xml",
        },
        # Sonidos propios (tools/gen_rutinas_sounds.py) para los canales de notificación.
        "android_binary_files": {
            f"assets/sounds/rutinas_{name}.wav": f"android/app/src/main/res/raw/rutinas_{name}.wav"
            for name in ("pip", "beep", "bell", "horn", "gong")
        },
        "android_desugaring": True,
        # El delegado de notificaciones de iOS: toques y botones de los avisos.
        "ios_files": {
            "native/ios/AppDelegate.swift": "ios/Runner/AppDelegate.swift",
        },
        "ios_plist": {
            "CFBundleDisplayName": "Rutinas",
            "ITSAppUsesNonExemptEncryption": False,
        },
        "ios_strings_en": {"CFBundleDisplayName": "Rutinas"},
        "iphone_orientations": ["UIInterfaceOrientationPortrait"],
        "ios_privacy_collected": [],
        "ios_min": "15.0",
    },
}


OLD_RELEASE = '        release {\n            // TODO: Add your own signing config for the release build.\n            // Signing with the debug keys for now, so `flutter run --release` works.\n            signingConfig = signingConfigs.getByName("debug")\n        }'
NEW_RELEASE = '        release {\n            signingConfig = if (keystorePropertiesFile.exists()) {\n                signingConfigs.getByName("release")\n            } else {\n                signingConfigs.getByName("debug")\n            }\n        }'


# ------------------------------------------------------- pantalla de arranque
# Flutter deja en iOS un marcador vacío de 1×1 sobre blanco fijo (destello blanco
# en modo oscuro) y en Android anterior a la 12 un fondo liso. Cada app arranca con
# su ícono centrado sobre el fondo del sistema (claro u oscuro); las imágenes las
# genera tools/gen_launch_assets.py en native/launch/ y aquí se copian.

ANDROID_LAUNCH_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- Pantalla de arranque antes de Android 12: el ícono de la app centrado sobre el
     fondo del tema (claro u oscuro). Desde Android 12 el sistema dibuja la suya con
     el ícono adaptativo. Generado por tools/patch_platforms.py. -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="{background}" />
    <item>
        <bitmap
            android:gravity="center"
            android:src="@drawable/launch_image" />
    </item>
</layer-list>
"""

IOS_LAUNCH_COLORSET = """{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "1.000", "green" : "1.000", "red" : "1.000" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0.000", "green" : "0.000", "red" : "0.000" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} no es un PNG")
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


def patch_android_launch() -> None:
    src = Path("native/launch/android")
    if not src.exists():
        return
    res = Path("android/app/src/main/res")
    for folder in sorted(src.iterdir()):
        target = res / folder.name / "launch_image.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((folder / "launch_image.png").read_bytes())
    # API 21+ toma el color del tema (claro u oscuro); la versión sin calificador
    # solo la usarían teléfonos anteriores, que las apps no admiten.
    for name, background in (("drawable/launch_background.xml", "@android:color/white"), ("drawable-v21/launch_background.xml", "?android:colorBackground")):
        target = res / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(ANDROID_LAUNCH_XML.format(background=background), encoding="utf-8")
    print("pantalla de arranque de Android con el ícono de la app")


def patch_ios_launch() -> None:
    src = Path("native/launch/ios")
    if not src.exists():
        return
    assets = Path("ios/Runner/Assets.xcassets")
    imageset = assets / "LaunchImage.imageset"
    for name in ("LaunchImage.png", "LaunchImage@2x.png", "LaunchImage@3x.png"):
        (imageset / name).write_bytes((src / name).read_bytes())
    colorset = assets / "LaunchBackground.colorset"
    colorset.mkdir(parents=True, exist_ok=True)
    (colorset / "Contents.json").write_text(IOS_LAUNCH_COLORSET, encoding="utf-8")
    board = Path("ios/Runner/Base.lproj/LaunchScreen.storyboard")
    t = board.read_text(encoding="utf-8")
    t = re.sub(r'<color key="backgroundColor"[^>]*/>', '<color key="backgroundColor" name="LaunchBackground"/>', t, count=1)
    if 'name="Named colors"' not in t:
        t = t.replace("    </dependencies>", '        <capability name="Named colors" minToolsVersion="9.0"/>\n    </dependencies>', 1)
    w, h = png_size(src / "LaunchImage.png")
    t = re.sub(r'<image name="LaunchImage" width="[^"]*" height="[^"]*"/>', f'<image name="LaunchImage" width="{w}" height="{h}"/>', t, count=1)
    if '<namedColor name="LaunchBackground">' not in t:
        t = t.replace(
            "    </resources>",
            '        <namedColor name="LaunchBackground">\n'
            '            <color red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>\n'
            "        </namedColor>\n"
            "    </resources>",
            1,
        )
    board.write_text(t, encoding="utf-8")
    print("pantalla de arranque de iOS con el ícono de la app y fondo claro u oscuro")


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
    if cfg.get("android_remove_process_text"):
        text = re.sub(r"\n?[ \t]*<intent>\s*<action android:name=\"android\.intent\.action\.PROCESS_TEXT\"\s*/>\s*<data android:mimeType=\"text/plain\"\s*/>\s*</intent>", "", text)
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
    for attr, value in cfg.get("android_application_attrs", {}).items():
        m = re.search(r"<application\b[^>]*>", text)
        if not m:
            raise SystemExit("No encontré <application> en el manifiesto")
        tag = m.group(0)
        if f'{attr}="' in tag:
            new_tag = re.sub(rf'{re.escape(attr)}="[^"]*"', f'{attr}="{value}"', tag, count=1)
        else:
            new_tag = tag.replace("<application", f'<application\n        {attr}="{value}"', 1)
        text = text[: m.start()] + new_tag + text[m.end():]
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
    # Archivos binarios (por ejemplo, sonidos de notificación en res/raw).
    for src, dst in cfg.get("android_binary_files", {}).items():
        target = Path(dst)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(Path(src).read_bytes())
        print(f"copiado {src} -> {dst}")
    patch_android_launch()

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
        if name.endswith(".kts") and "keystoreProperties" not in g:
            g = SIGNING_HEADER + g
            g = g.replace("\nandroid {", SIGNING_PROPS + "\nandroid {", 1)
            g = g.replace("    buildTypes {", SIGNING_CONFIGS, 1)
            if OLD_RELEASE not in g:
                raise SystemExit(f"No encontré el bloque release esperado en {name}; revisa la plantilla de flutter create.")
            g = g.replace(OLD_RELEASE, NEW_RELEASE, 1)
            print(f"firma de release por key.properties en {name}")
        gradle.write_text(g, encoding="utf-8")
        print(f"minSdk fijado en {min_sdk} en {name}")


def patch_ios(cfg: dict) -> None:
    plist_path = Path("ios/Runner/Info.plist")
    with plist_path.open("rb") as f:
        plist = plistlib.load(f)
    plist.update(cfg["ios_plist"])
    for key in cfg.get("ios_plist_remove", []):
        plist.pop(key, None)
    # Idiomas que la App Store muestra en la ficha y que iOS usa para los textos del sistema.
    plist["CFBundleLocalizations"] = cfg.get("ios_localizations", ["es", "en"])
    if "iphone_orientations" in cfg:
        plist["UISupportedInterfaceOrientations"] = cfg["iphone_orientations"]
    with plist_path.open("wb") as f:
        plistlib.dump(plist, f, sort_keys=False)

    for src, dst in cfg.get("ios_files", {}).items():
        Path(dst).write_text(Path(src).read_text(encoding="utf-8"), encoding="utf-8")
        print(f"copiado {src} -> {dst}")
    patch_ios_launch()

    podfile = Path("ios/Podfile")
    if podfile.exists():
        p = podfile.read_text(encoding="utf-8")
        p = re.sub(r"^#\s*platform :ios, '[^']*'", f"platform :ios, '{cfg['ios_min']}'", p, count=1, flags=re.M)
        podfile.write_text(p, encoding="utf-8")

    pbx = Path("ios/Runner.xcodeproj/project.pbxproj")
    if pbx.exists():
        t = pbx.read_text(encoding="utf-8")
        t = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {cfg['ios_min']};", t)
        t = add_privacy_manifest(t, cfg)
        t = add_infoplist_strings(t, cfg, plist)
        pbx.write_text(t, encoding="utf-8")


# ----------------------------------------------------------------- Xcode

def pbx_id(key: str) -> str:
    """Identificador estable de 24 caracteres para objetos que agregamos."""
    return hashlib.sha1(("apps-gratis:" + key).encode()).hexdigest()[:24].upper()


def pbx_insert(t: str, section: str, entry: str) -> str:
    marker = f"/* End {section} section */"
    if marker not in t:
        # La sección no existe todavía: se crea antes de la siguiente.
        t = t.replace("/* Begin PBXGroup section */", f"/* Begin {section} section */\n/* End {section} section */\n\n/* Begin PBXGroup section */", 1)
    return t.replace(marker, entry + marker, 1)


def pbx_add_to_runner_group(t: str, ref_id: str, comment: str) -> str:
    m = re.search(r"children = \(\n((?:\t\t\t\t[^\n]*\n)*?)\t\t\t\);\n\t\t\tpath = Runner;", t)
    if not m:
        raise SystemExit("No encontré el grupo Runner en project.pbxproj")
    if ref_id in m.group(1):
        return t
    insert_at = m.end(1)
    return t[:insert_at] + f"\t\t\t\t{ref_id} /* {comment} */,\n" + t[insert_at:]


def pbx_add_to_runner_resources(t: str, build_id: str, comment: str) -> str:
    # La fase de recursos del Runner es la que ya lleva Assets.xcassets.
    for m in re.finditer(r"/\* Resources \*/ = \{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = \d+;\n\t\t\tfiles = \(\n((?:\t\t\t\t[^\n]*\n)*?)\t\t\t\);", t):
        if "Assets.xcassets in Resources" in m.group(1):
            if build_id in m.group(1):
                return t
            insert_at = m.end(1)
            return t[:insert_at] + f"\t\t\t\t{build_id} /* {comment} in Resources */,\n" + t[insert_at:]
    raise SystemExit("No encontré la fase de recursos del Runner en project.pbxproj")


def privacy_manifest(cfg: dict) -> dict:
    return {
        "NSPrivacyTracking": False,
        "NSPrivacyTrackingDomains": [],
        "NSPrivacyCollectedDataTypes": [
            {
                "NSPrivacyCollectedDataType": c["type"],
                "NSPrivacyCollectedDataTypeLinked": c["linked"],
                "NSPrivacyCollectedDataTypeTracking": c["tracking"],
                "NSPrivacyCollectedDataTypePurposes": c["purposes"],
            }
            for c in cfg.get("ios_privacy_collected", [])
        ],
        # shared_preferences guarda los ajustes de la app en sus propios UserDefaults.
        "NSPrivacyAccessedAPITypes": [
            {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]},
        ],
    }


def add_privacy_manifest(t: str, cfg: dict) -> str:
    path = Path("ios/Runner/PrivacyInfo.xcprivacy")
    with path.open("wb") as f:
        plistlib.dump(privacy_manifest(cfg), f, sort_keys=False)
    ref, build = pbx_id("PrivacyInfo.ref"), pbx_id("PrivacyInfo.build")
    if ref not in t:
        t = pbx_insert(t, "PBXFileReference", f"\t\t{ref} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = \"<group>\"; }};\n")
        t = pbx_insert(t, "PBXBuildFile", f"\t\t{build} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {ref} /* PrivacyInfo.xcprivacy */; }};\n")
    t = pbx_add_to_runner_group(t, ref, "PrivacyInfo.xcprivacy")
    t = pbx_add_to_runner_resources(t, build, "PrivacyInfo.xcprivacy")
    print("manifiesto de privacidad PrivacyInfo.xcprivacy")
    return t


def strings_file(values: dict) -> str:
    def esc(v: str) -> str:
        return v.replace("\\", "\\\\").replace('"', '\\"')
    return "".join(f'"{k}" = "{esc(v)}";\n' for k, v in values.items())


def add_infoplist_strings(t: str, cfg: dict, plist: dict) -> str:
    """InfoPlist.strings en español e inglés (nombre y textos de permisos)."""
    keys = [k for k in plist if k == "CFBundleDisplayName" or k.endswith("UsageDescription")]
    langs = cfg.get("ios_localizations", ["es", "en"])
    es = {k: plist[k] for k in keys}
    en = dict(cfg.get("ios_strings_en", {}))
    missing = [k for k in keys if k not in en]
    if "en" in langs and missing:
        raise SystemExit(f"Faltan traducciones al inglés en ios_strings_en: {missing}")
    if "en" not in langs:
        # Sin carpeta en.lproj: la App Store lista los idiomas por las carpetas del paquete.
        shutil.rmtree("ios/Runner/en.lproj", ignore_errors=True)
        t = t.replace("developmentRegion = en;", "developmentRegion = es;")
        # Y fuera del proyecto la referencia a en.lproj/InfoPlist.strings.
        en_ref = pbx_id("InfoPlist.strings.en")
        t = "".join(line for line in t.splitlines(keepends=True) if en_ref not in line)
    for lang, values in (("es", es), ("en", en)):
        if lang not in langs:
            continue
        d = Path(f"ios/Runner/{lang}.lproj")
        d.mkdir(parents=True, exist_ok=True)
        (d / "InfoPlist.strings").write_text(strings_file(values), encoding="utf-8")
    group = pbx_id("InfoPlist.strings.group")
    build = pbx_id("InfoPlist.strings.build")
    refs = {lang: pbx_id(f"InfoPlist.strings.{lang}") for lang in ("es", "en") if lang in langs}
    if group not in t:
        for lang, ref in refs.items():
            t = pbx_insert(t, "PBXFileReference", f"\t\t{ref} /* {lang} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {lang}; path = {lang}.lproj/InfoPlist.strings; sourceTree = \"<group>\"; }};\n")
        children = "".join(f"\t\t\t\t{ref} /* {lang} */,\n" for lang, ref in refs.items())
        t = pbx_insert(t, "PBXVariantGroup", f"\t\t{group} /* InfoPlist.strings */ = {{\n\t\t\tisa = PBXVariantGroup;\n\t\t\tchildren = (\n{children}\t\t\t);\n\t\t\tname = InfoPlist.strings;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
        t = pbx_insert(t, "PBXBuildFile", f"\t\t{build} /* InfoPlist.strings in Resources */ = {{isa = PBXBuildFile; fileRef = {group} /* InfoPlist.strings */; }};\n")
    t = pbx_add_to_runner_group(t, group, "InfoPlist.strings")
    t = pbx_add_to_runner_resources(t, build, "InfoPlist.strings")
    m = re.search(r"knownRegions = \(\n((?:\t\t\t\t[^\n]*\n)*?)\t\t\t\);", t)
    if m and "\t\t\t\tes,\n" not in m.group(1):
        t = t[: m.end(1)] + "\t\t\t\tes,\n" + t[m.end(1):]
    print("InfoPlist.strings en es y en")
    return t


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
