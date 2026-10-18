package co.appsgratis.rutinas

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Vibración del temporizador al cambiar de intervalo. Flutter solo ofrece la
// respuesta táctil del sistema, que es un toque muy breve y no se siente si el
// usuario la apagó; aquí se usa el motor de vibración, que respeta el ajuste
// de vibración del teléfono.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rutinas/vibracion").setMethodCallHandler { call, result ->
            if (call.method == "vibrar") {
                val ms = (call.argument<Int>("ms") ?: 300).coerceIn(10, 2000).toLong()
                vibrar(ms)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun vibrar(ms: Long) {
        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (vibrator == null || !vibrator.hasVibrator()) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(ms)
        }
    }
}
