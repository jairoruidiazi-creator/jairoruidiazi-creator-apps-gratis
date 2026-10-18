package co.appsgratis.plata

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// Actividad principal. Hereda de FlutterFragmentActivity por local_auth,
/// expone el puente de avisos bancarios (ver BankNoticeListener) y, mientras
/// hay clave, protege la ventana con FLAG_SECURE: sin capturas de pantalla y
/// con la miniatura de apps recientes en blanco.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "co.appsgratis.plata/notices"
    private val privacyChannelName = "co.appsgratis.plata/privacy"
    private var events: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /// La actividad guarda la referencia fuerte del callback en vivo; el
    /// servicio de avisos solo una débil, así que no la retiene.
    private val liveCallback: (Map<String, Any?>) -> Unit = { map -> mainHandler.post { events?.success(map) } }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Lo que eligió la app la última vez, desde el primer cuadro y antes de
        // que cargue Flutter.
        applySecure(getSharedPreferences(PRIVACY_PREFS, Context.MODE_PRIVATE).getBoolean(SECURE, false))
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        BankNoticeListener.clearLive(liveCallback)
        events = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(true)
                "isEnabled" -> result.success(isListenerEnabled())
                "setEnabled" -> {
                    BankNoticeListener.setEnabled(this, call.arguments as? Boolean ?: false)
                    result.success(true)
                }
                "openSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "readPending" -> result.success(BankNoticeListener.readPending(this))
                "clearPending" -> {
                    BankNoticeListener.clearPending(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "$channelName/stream").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
                BankNoticeListener.setLive(liveCallback)
            }

            override fun onCancel(arguments: Any?) {
                events = null
                BankNoticeListener.clearLive(liveCallback)
            }
        })
        MethodChannel(messenger, privacyChannelName).setMethodCallHandler { call, result ->
            if (call.method == "setSecure") {
                val on = call.arguments as? Boolean ?: false
                getSharedPreferences(PRIVACY_PREFS, Context.MODE_PRIVATE).edit().putBoolean(SECURE, on).apply()
                applySecure(on)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun applySecure(on: Boolean) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun isListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, BankNoticeListener::class.java).flattenToString()
        return flat.split(":").any { it == me || it.endsWith(BankNoticeListener::class.java.name) }
    }

    companion object {
        private const val PRIVACY_PREFS = "plata_privacy"
        private const val SECURE = "secure"
    }
}
