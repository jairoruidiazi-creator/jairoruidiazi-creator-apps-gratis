package co.appsgratis.plata

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.io.File

/// Lee las notificaciones de las apps bancarias elegidas y las deja en un
/// archivo de la app (una línea JSON por aviso) para que Flutter las procese
/// al abrirse; si la app está abierta, además las envía en vivo.
///
/// Solo se guardan título y texto de los paquetes de la lista; nada sale del
/// teléfono. El usuario concede el acceso en Ajustes > Notificaciones.
class BankNoticeListener : NotificationListenerService() {
    companion object {
        /// Paquetes de bancos y billeteras (misma lista que BankRules en Dart).
        val packages: Set<String> = setOf(
            "com.bancolombia.personas", "com.bancolombia.app.personas",
            "com.nequi.MobileApp", "com.nequi.mobileapp",
            "com.davivienda.daviplataapp", "com.davivienda.daviviendaapp",
            "co.com.bbva.mb", "com.bancodebogota.bancamovil",
            "co.com.bancodeoccidente.bancamovil", "com.scotiabankcolpatria.mobile",
            "com.lulobank.app", "co.com.rappi.pay", "com.nu.production", "co.uala.app", "com.movii.movii"
        )

        @Volatile
        var liveSink: ((Map<String, Any?>) -> Unit)? = null

        fun pendingFile(context: Context): File = File(context.filesDir, "bank_notices.jsonl")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        if (!packages.contains(n.packageName)) return
        val extras = n.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        if (title.isBlank() && text.isBlank()) return
        val record = JSONObject()
            .put("package", n.packageName)
            .put("title", title)
            .put("text", text)
            .put("time", n.postTime)
        try {
            val f = pendingFile(this)
            // Tope de 300 KB para que el archivo no crezca sin límite.
            if (f.exists() && f.length() > 300_000) f.delete()
            f.appendText(record.toString() + "\n")
        } catch (_: Exception) {
        }
        liveSink?.invoke(mapOf("package" to n.packageName, "title" to title, "text" to text, "time" to n.postTime))
    }
}
