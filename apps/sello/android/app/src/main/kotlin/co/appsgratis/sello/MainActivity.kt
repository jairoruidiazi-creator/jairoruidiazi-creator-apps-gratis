package co.appsgratis.sello

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream

/**
 * Actividad de Sello con dos canales propios.
 *
 * co.appsgratis.sello/altitude: geolocator_android (4.6 o superior) cambia
 * Location.getAltitude(), que es la altura sobre el elipsoide WGS84, por
 * getMslAltitudeMeters() cuando el sistema la trae (Android 14 QPR3 o
 * superior), sin decir cuál de las dos entregó. Con eso la app no puede saber
 * si debe restar el geoide. Este canal escucha el proveedor GPS del sistema y
 * entrega siempre la elipsoidal, con su hora, para que la app aplique EGM96
 * una sola vez (docs/DECISIONES.md, "Altitud").
 *
 * co.appsgratis.sello/files: la copia completa se guarda donde el usuario
 * elija (ACTION_CREATE_DOCUMENT) y se restaura desde donde la tenga
 * (ACTION_OPEN_DOCUMENT) copiando el flujo en un hilo aparte, de a 1 MB: el
 * archivo nunca pasa entero por la memoria (el selector de archivos de
 * Flutter lo leía completo en el hilo principal). También da el espacio libre.
 */
class MainActivity : FlutterActivity() {
    private var altitude: GpsAltitudeStream? = null
    private var documents: DocumentFiles? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val stream = GpsAltitudeStream(applicationContext)
        altitude = stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "co.appsgratis.sello/altitude").setStreamHandler(stream)
        val docs = DocumentFiles(this)
        documents = docs
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "co.appsgratis.sello/files").setMethodCallHandler(docs)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        altitude?.stop()
        altitude = null
        documents = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documents?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}

/** Guardar y abrir documentos del sistema copiando el flujo en un hilo aparte. */
private class DocumentFiles(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var pendingSource: String? = null
    private var pendingTarget: String? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "freeBytes" -> {
                try {
                    result.success(StatFs(activity.filesDir.path).availableBytes)
                } catch (e: Exception) {
                    result.success(null)
                }
            }
            "saveDocument" -> {
                val source = call.argument<String>("source")
                if (source == null || !File(source).isFile) {
                    result.error("args", "Falta el archivo de origen", null)
                    return
                }
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mime") ?: "application/zip"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: File(source).name)
                }
                launch(intent, REQUEST_SAVE, result, source = source)
            }
            "openDocument" -> {
                val target = call.argument<String>("target")
                if (target == null) {
                    result.error("args", "Falta el destino", null)
                    return
                }
                val mimes = call.argument<List<String>>("mimes") ?: listOf("application/zip")
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, mimes.toTypedArray())
                }
                launch(intent, REQUEST_OPEN, result, target = target)
            }
            else -> result.notImplemented()
        }
    }

    private fun launch(intent: Intent, request: Int, result: MethodChannel.Result, source: String? = null, target: String? = null) {
        if (pending != null) {
            result.error("busy", "Ya hay un selector de archivos abierto", null)
            return
        }
        pending = result
        pendingSource = source
        pendingTarget = target
        try {
            activity.startActivityForResult(intent, request)
        } catch (e: ActivityNotFoundException) {
            clear()
            result.error("no-picker", e.message, null)
        }
    }

    private fun clear() {
        pending = null
        pendingSource = null
        pendingTarget = null
    }

    /** Verdadero si el resultado era de este canal. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_SAVE && requestCode != REQUEST_OPEN) {
            return false
        }
        val result = pending ?: return true
        val source = pendingSource
        val target = pendingTarget
        clear()
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // Cancelado: guardar devuelve falso; abrir, nada.
            result.success(if (requestCode == REQUEST_SAVE) false else null)
            return true
        }
        Thread {
            try {
                if (requestCode == REQUEST_SAVE) {
                    copyToUri(File(source!!), uri)
                    main.post { result.success(true) }
                } else {
                    val size = copyFromUri(uri, File(target!!))
                    val name = displayName(uri)
                    main.post { result.success(mapOf("name" to name, "size" to size)) }
                }
            } catch (e: Exception) {
                if (requestCode == REQUEST_SAVE) {
                    // Un documento a medias no sirve de copia: se borra.
                    try {
                        DocumentsContract.deleteDocument(activity.contentResolver, uri)
                    } catch (ignored: Exception) {
                    }
                } else if (target != null) {
                    File(target).delete()
                    File("$target.tmp-open").delete()
                }
                main.post { result.error("io", e.message ?: e.toString(), null) }
            }
        }.start()
        return true
    }

    private fun openOutput(uri: Uri): OutputStream {
        // "wt" vacía el documento si ya existía; no todos los proveedores lo aceptan.
        val stream = try {
            activity.contentResolver.openOutputStream(uri, "wt")
        } catch (e: Exception) {
            activity.contentResolver.openOutputStream(uri)
        }
        return stream ?: throw IOException("No se pudo abrir el destino")
    }

    private fun copyToUri(source: File, uri: Uri) {
        openOutput(uri).use { output ->
            FileInputStream(source).use { input -> input.copyTo(output, BUFFER) }
        }
    }

    private fun copyFromUri(uri: Uri, dest: File): Long {
        dest.parentFile?.mkdirs()
        val tmp = File("${dest.path}.tmp-open")
        val input = activity.contentResolver.openInputStream(uri) ?: throw IOException("No se pudo abrir el archivo")
        val copied = input.use { i ->
            FileOutputStream(tmp).use { o ->
                val n = i.copyTo(o, BUFFER)
                o.fd.sync()
                n
            }
        }
        if (dest.exists()) {
            dest.delete()
        }
        if (!tmp.renameTo(dest)) {
            throw IOException("No se pudo guardar la copia elegida")
        }
        return copied
    }

    private fun displayName(uri: Uri): String {
        try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    return c.getString(0) ?: ""
                }
            }
        } catch (ignored: Exception) {
        }
        return ""
    }

    companion object {
        const val REQUEST_SAVE = 0x5E11
        const val REQUEST_OPEN = 0x5E12
        const val BUFFER = 1 shl 20
    }
}

/** Lecturas del proveedor GPS: altura elipsoidal, hora (ms UTC) y precisión vertical. */
private class GpsAltitudeStream(private val context: Context) : EventChannel.StreamHandler, LocationListener {
    private val manager: LocationManager? = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
    private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        start()
    }

    override fun onCancel(arguments: Any?) {
        stop()
        sink = null
    }

    private fun start() {
        val m = manager ?: return
        // Sin ubicación precisa no hay GPS: la altitud queda desconocida. La
        // app vuelve a abrir este canal al volver de los ajustes del teléfono,
        // por si el permiso cambió (de aproximada a precisa).
        if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            return
        }
        if (!m.allProviders.contains(LocationManager.GPS_PROVIDER)) {
            return
        }
        try {
            m.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, this, Looper.getMainLooper())
        } catch (e: SecurityException) {
            sink?.error("permission", e.message, null)
        } catch (e: IllegalArgumentException) {
            sink?.error("provider", e.message, null)
        }
    }

    fun stop() {
        try {
            manager?.removeUpdates(this)
        } catch (e: Exception) {
            // Nada que detener.
        }
    }

    override fun onLocationChanged(location: Location) {
        if (!location.hasAltitude()) {
            return
        }
        val event = HashMap<String, Any>()
        event["ellipsoid"] = location.altitude
        event["time"] = location.time
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasVerticalAccuracy()) {
            event["accuracy"] = location.verticalAccuracyMeters.toDouble()
        }
        sink?.success(event)
    }

    // Hasta Android 10 estos tres métodos no tienen implementación por defecto:
    // sin ellos el sistema cerraría la app al llamarlos.
    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    override fun onProviderEnabled(provider: String) {}

    override fun onProviderDisabled(provider: String) {}
}
