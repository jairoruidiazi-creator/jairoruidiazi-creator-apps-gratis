#!/usr/bin/env python3
"""Comprueba que el manifiesto de privacidad de iOS declare las API de «motivo
requerido» que usa el código nativo propio de la app.

Desde el 1 de mayo de 2024 App Store Connect rechaza (ITMS-91053) un binario que
use una de esas API sin declararla con su motivo en PrivacyInfo.xcprivacy. Los
complementos traen su propio manifiesto; esto revisa lo nuestro: el Swift y el
Objective-C de apps/<app>/native/ios y de apps/<app>/ios/Runner.

Uso: python3 tools/ci/check_privacy_apis.py <app>
"""
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

# Símbolos de cada categoría según
# https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
CATEGORIES = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": [
        r"\bcreationDate\b", r"\bmodificationDate\b", r"\bfileModificationDate\b",
        r"contentModificationDateKey", r"creationDateKey", r"NSFileCreationDate",
        r"NSFileModificationDate", r"\bgetattrlist\b", r"\bfstat\b", r"\blstat\b", r"\bstat\(",
    ],
    "NSPrivacyAccessedAPICategorySystemBootTime": [r"\bsystemUptime\b", r"\bmach_absolute_time\b"],
    "NSPrivacyAccessedAPICategoryDiskSpace": [
        r"volumeAvailableCapacity", r"volumeTotalCapacity", r"NSFileSystemFreeSize",
        r"NSFileSystemSize", r"systemFreeSize", r"systemSize", r"\bstatfs\b", r"\bstatvfs\b",
    ],
    "NSPrivacyAccessedAPICategoryActiveKeyboards": [r"\bactiveInputModes\b"],
    "NSPrivacyAccessedAPICategoryUserDefaults": [r"\bUserDefaults\b", r"\bNSUserDefaults\b"],
}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    app_dir = ROOT / "apps" / sys.argv[1]
    manifest = app_dir / "ios" / "Runner" / "PrivacyInfo.xcprivacy"
    if not manifest.exists():
        print(f"{sys.argv[1]}: sin ios/Runner/PrivacyInfo.xcprivacy")
        return 1
    declared = {
        e["NSPrivacyAccessedAPIType"]: e.get("NSPrivacyAccessedAPITypeReasons", [])
        for e in plistlib.loads(manifest.read_bytes()).get("NSPrivacyAccessedAPITypes", [])
    }
    sources = [p for d in (app_dir / "native" / "ios", app_dir / "ios" / "Runner") if d.exists()
               for p in d.rglob("*") if p.suffix in (".swift", ".m", ".mm", ".h")]
    problems: list[str] = []
    for path in sources:
        code = re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8", errors="replace"))
        for category, patterns in CATEGORIES.items():
            hits = [pat for pat in patterns if re.search(pat, code)]
            if hits and not declared.get(category):
                problems.append(f"{path.relative_to(ROOT)} usa {category} ({', '.join(hits)}) y el manifiesto no la declara")
    for category, reasons in declared.items():
        print(f"declarado: {category} {reasons}")
    if problems:
        print("\n".join(problems))
        return 1
    print(f"{sys.argv[1]}: el manifiesto de privacidad cubre las API del código nativo propio ({len(sources)} archivos)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
