package co.appsgratis.plata

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

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

    /// Selector propio para restaurar copias (ver lib/core/backup_picker.dart):
    /// mira el tamaño antes de leer y copia a la caché sin pasar del tope.
    private val filesChannelName = "co.appsgratis.plata/files"
    private var pendingPick: MethodChannel.Result? = null
    private var pickMax: Long = DEFAULT_MAX_BYTES
    private val openDocument = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> onBackupPicked(uri) }

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
        MethodChannel(messenger, filesChannelName).setMethodCallHandler { call, result ->
            if (call.method == "pickBackup") {
                if (pendingPick != null) {
                    result.error("busy", "El selector ya está abierto", null)
                } else {
                    pickMax = call.argument<Number>("maxBytes")?.toLong() ?: DEFAULT_MAX_BYTES
                    pendingPick = result
                    try {
                        // Sin filtro de tipo: un .plata en Drive o Descargas
                        // llega como application/octet-stream.
                        openDocument.launch(arrayOf("*/*"))
                    } catch (e: Exception) {
                        pendingPick = null
                        result.error("picker", e.message, null)
                    }
                }
            } else {
                result.notImplemented()
            }
        }
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

    private fun onBackupPicked(uri: Uri?) {
        val result = pendingPick ?: return
        if (uri == null) {
            pendingPick = null
            result.success(null)
            return
        }
        val max = pickMax
        // El selector sigue "ocupado" hasta terminar la copia: otro pedido
        // mientras tanto recibe "busy" en vez de abrir un segundo selector.
        Thread {
            val answer = copyPicked(uri, max)
            mainHandler.post {
                pendingPick = null
                result.success(answer)
            }
        }.start()
    }

    /// Copia el archivo elegido a <caché>/restore/ (con un nombre propio) por partes, sin cargarlo
    /// entero en memoria: si el proveedor dice que pasa del tope no se lee, y
    /// si no lo dice, la copia se corta al pasarlo. Dart lee la copia y la
    /// borra enseguida; lo que quede se borra al abrir la app y al borrar todo.
    private fun copyPicked(uri: Uri, max: Long): Map<String, Any?> {
        var name = ""
        var size: Long? = null
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (n >= 0 && !c.isNull(n)) {
                        name = c.getString(n) ?: ""
                    }
                    val s = c.getColumnIndex(OpenableColumns.SIZE)
                    if (s >= 0 && !c.isNull(s)) {
                        size = c.getLong(s)
                    }
                }
            }
        } catch (e: Exception) {
            // Sin nombre ni tamaño: se copia igual, con el tope de abajo.
        }
        val known = size
        if (known != null && known > max) {
            return mapOf("name" to name, "error" to "tooBig")
        }
        val dir = File(cacheDir, "restore")
        dir.mkdirs()
        // Un nombre por elección: dos copias nunca escriben el mismo archivo.
        val target = File.createTempFile("elegido-", ".bin", dir)
        var tooBig = false
        try {
            val input = contentResolver.openInputStream(uri) ?: return mapOf("name" to name, "error" to "unreadable")
            input.use { inp ->
                target.outputStream().use { out ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val read = inp.read(buffer)
                        if (read < 0) {
                            break
                        }
                        total += read
                        if (total > max) {
                            tooBig = true
                            break
                        }
                        out.write(buffer, 0, read)
                    }
                }
            }
        } catch (e: Exception) {
            target.delete()
            return mapOf("name" to name, "error" to "unreadable")
        }
        if (tooBig) {
            target.delete()
            return mapOf("name" to name, "error" to "tooBig")
        }
        return mapOf("name" to name, "path" to target.path)
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
        private const val DEFAULT_MAX_BYTES = 200L * 1024 * 1024
    }
}
