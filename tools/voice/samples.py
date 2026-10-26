#!/usr/bin/env python3
"""Muestras de voces neuronales en español para elegir la voz de Pilas.

Uso: python3 tools/voice/samples.py <carpeta de modelos Piper> <salida>

Genera, para cada voz candidata, un MP3 con las mismas frases (instrucciones,
felicitaciones, ánimo, conteo y una palabra con su sonido) a velocidad normal
y un poco más lenta, para comparar en igualdad de condiciones.
"""
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

FRASES = [
    "¡Hola! Qué bueno verte. ¿Jugamos un rato?",
    "Busca la pareja de cada dibujo. Toca dos tarjetas.",
    "¡Muy bien! Lo lograste.",
    "Casi. Míralo otra vez, tú puedes.",
    "¿Cuántas manzanas hay? Cuenta conmigo: una, dos, tres, cuatro.",
    "Esta es la letra eme. Eme, de mamá y de mariposa.",
    "Arrastra la estrella hasta la caja azul.",
    "¡Ganaste una pegatina nueva para tu álbum!",
]

# Candidatas con licencia que permite uso comercial y distribución.
PIPER = {
    "piper_es_MX-claude-high": "es_MX-claude-high.onnx",   # datos Apache-2.0
    "piper_es_MX-ald-medium": "es_MX-ald-medium.onnx",     # datos Unlicense
    "piper_es_AR-daniela-high": "es_AR-daniela-high.onnx",  # datos CC BY-SA 4.0
}
KOKORO = {  # pesos Apache-2.0
    "kokoro_ef_dora": "ef_dora",
    "kokoro_em_alex": "em_alex",
}
SPEEDS = {"normal": 1.0, "lenta": 0.88}


def silence(sr: int, secs: float) -> np.ndarray:
    return np.zeros(int(sr * secs), dtype=np.float32)


def write_mp3(samples: np.ndarray, sr: int, out: Path) -> None:
    pcm = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    wav = out.with_suffix(".wav")
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-codec:a", "libmp3lame", "-q:a", "3", str(out)], check=True)
    wav.unlink()


def piper_voice(model: Path, speed: float):
    from piper import PiperVoice, SynthesisConfig

    voice = PiperVoice.load(str(model))
    sr = voice.config.sample_rate
    cfg = SynthesisConfig(length_scale=1.0 / speed)
    parts = []
    for f in FRASES:
        chunks = [c.audio_float_array for c in voice.synthesize(f, syn_config=cfg)]
        parts += [np.concatenate(chunks).astype(np.float32), silence(sr, 0.7)]
    return np.concatenate(parts), sr


def kokoro_voice(pipe, name: str, speed: float):
    sr = 24000
    parts = []
    for f in FRASES:
        audio = [np.asarray(a, dtype=np.float32) for _, _, a in pipe(f, voice=name, speed=speed)]
        parts += [np.concatenate(audio), silence(sr, 0.7)]
    return np.concatenate(parts), sr


def main() -> int:
    models, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    errors = []
    for label, file in PIPER.items():
        for sname, speed in SPEEDS.items():
            try:
                a, sr = piper_voice(models / file, speed)
                write_mp3(a, sr, out / f"{label}_{sname}.mp3")
                print("ok", label, sname)
            except Exception as e:  # noqa: BLE001 - se informa y se sigue con las demás
                errors.append(f"{label} {sname}: {e}")
    try:
        from kokoro import KPipeline

        pipe = KPipeline(lang_code="e")
        for label, name in KOKORO.items():
            for sname, speed in SPEEDS.items():
                a, sr = kokoro_voice(pipe, name, speed)
                write_mp3(a, sr, out / f"{label}_{sname}.mp3")
                print("ok", label, sname)
    except Exception as e:  # noqa: BLE001
        errors.append(f"kokoro: {e}")
    (out / "frases.txt").write_text("\n".join(FRASES) + "\n", encoding="utf-8")
    (out / "errores.txt").write_text("\n".join(errors) + "\n", encoding="utf-8")
    print("\n".join(errors))
    return 0


if __name__ == "__main__":
    sys.exit(main())
