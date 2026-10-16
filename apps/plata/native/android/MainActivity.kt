package co.appsgratis.plata

import android.content.ComponentName
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/// Actividad principal. Hereda de FlutterFragmentActivity por local_auth y
/// expone el puente de avisos bancarios (ver BankNoticeListener).
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "co.appsgratis.plata/notices"
    private var events: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(true)
                "isEnabled" -> result.success(isListenerEnabled())
                "openSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "readPending" -> result.success(readPending())
                "clearPending" -> {
                    BankNoticeListener.pendingFile(this).delete()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "$channelName/stream").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
                BankNoticeListener.liveSink = { map -> mainHandler.post { events?.success(map) } }
            }

            override fun onCancel(arguments: Any?) {
                events = null
                BankNoticeListener.liveSink = null
            }
        })
    }

    private fun isListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, BankNoticeListener::class.java).flattenToString()
        return flat.split(":").any { it == me || it.endsWith(BankNoticeListener::class.java.name) }
    }

    /// Avisos guardados mientras la app estaba cerrada (una línea JSON por aviso).
    private fun readPending(): List<Map<String, Any?>> {
        val file: File = BankNoticeListener.pendingFile(this)
        if (!file.exists()) return emptyList()
        val out = ArrayList<Map<String, Any?>>()
        try {
            file.forEachLine { line ->
                if (line.isNotBlank()) {
                    try {
                        val o = JSONObject(line)
                        out.add(mapOf(
                            "package" to o.optString("package"),
                            "title" to o.optString("title"),
                            "text" to o.optString("text"),
                            "time" to o.optLong("time")
                        ))
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (_: Exception) {
        }
        return out
    }
}
