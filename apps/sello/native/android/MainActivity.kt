package co.appsgratis.sello

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Actividad de Sello con el canal co.appsgratis.sello/altitude.
 *
 * geolocator_android (4.6 o superior) cambia Location.getAltitude(), que es la
 * altura sobre el elipsoide WGS84, por getMslAltitudeMeters() cuando el sistema
 * la trae (Android 14 QPR3 o superior), sin decir cuál de las dos entregó. Con
 * eso la app no puede saber si debe restar el geoide. Este canal escucha el
 * proveedor GPS del sistema y entrega siempre la elipsoidal, con su hora, para
 * que la app aplique EGM96 una sola vez (docs/DECISIONES.md, "Altitud").
 */
class MainActivity : FlutterActivity() {
    private var altitude: GpsAltitudeStream? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val stream = GpsAltitudeStream(applicationContext)
        altitude = stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "co.appsgratis.sello/altitude").setStreamHandler(stream)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        altitude?.stop()
        altitude = null
        super.cleanUpFlutterEngine(flutterEngine)
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
        // Sin ubicación precisa no hay GPS: la altitud queda desconocida.
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
