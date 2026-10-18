package co.appsgratis.plata

import android.app.Notification
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.lang.ref.WeakReference
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// Lee las notificaciones de las apps bancarias de la lista y las guarda
/// cifradas en un archivo de la app (una línea por aviso) para que Flutter las
/// procese al abrirse; si la app está abierta, además las envía en vivo.
///
/// Solo se guardan título y texto de los paquetes de la lista, y solo mientras
/// "Leer avisos de bancos" está encendido en Plata: apagado, el servicio ignora
/// todo aunque el permiso del sistema siga concedido. Nada sale del teléfono.
class BankNoticeListener : NotificationListenerService() {
    companion object {
        /// Paquetes de bancos y billeteras, comprobados en Google Play (la misma
        /// lista que BankRules.packages en Dart; test/notices_test.dart verifica
        /// que coincidan).
        val packages: Set<String> = setOf(
            "co.com.bancolombia.personas.superapp",
            "com.nequi.MobileApp",
            "com.davivienda.daviplataapp",
            "com.davivienda.daviviendaapp",
            "co.com.bbva.mb",
            "com.bancodebogota.bancamovil",
            "com.grupoavaloc1.bancamovil",
            "eu.netinfo.colpatria.system",
            "co.com.lulobank.production",
            "com.nu.production",
            "com.movilred.subscriber"
        )

        private const val PREFS = "plata_notices"
        private const val ENABLED = "enabled"
        private const val KEY_ALIAS = "plata_notices"
        private const val MAX_BYTES = 300_000L
        private val fileLock = Any()

        /// Callback en vivo de la actividad abierta. El servicio guarda una
        /// referencia débil: no retiene la actividad (ella guarda la fuerte).
        @Volatile
        private var live: WeakReference<(Map<String, Any?>) -> Unit>? = null

        /// Lo ya entregado de cada notificación (por su clave): una notificación
        /// que se actualiza o que acumula líneas no repite los avisos que ya dio.
        private val seen = object : LinkedHashMap<String, MutableSet<String>>(64, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, MutableSet<String>>?): Boolean = size > 100
        }

        fun setLive(callback: ((Map<String, Any?>) -> Unit)?) {
            live = callback?.let { WeakReference(it) }
        }

        fun clearLive(callback: (Map<String, Any?>) -> Unit) {
            if (live?.get() === callback) live = null
        }

        private fun pendingFile(context: Context): File = File(context.filesDir, "bank_notices.enc")

        /// Lo que Flutter está procesando: se borra al terminar (clearPending).
        private fun readingFile(context: Context): File = File(context.filesDir, "bank_notices.reading")

        fun isEnabled(context: Context): Boolean = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(ENABLED, false)

        /// Enciende o apaga la lectura. Al apagarla se borra lo guardado.
        fun setEnabled(context: Context, on: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(ENABLED, on).apply()
            if (!on) {
                synchronized(fileLock) {
                    pendingFile(context).delete()
                    readingFile(context).delete()
                }
            }
        }

        /// Avisos guardados mientras la app estaba cerrada, descifrados. Pasan a
        /// un archivo aparte: lo que llegue mientras Flutter los procesa queda
        /// para la próxima lectura y no se borra con clearPending.
        fun readPending(context: Context): List<Map<String, Any?>> {
            val out = ArrayList<Map<String, Any?>>()
            synchronized(fileLock) {
                val pending = pendingFile(context)
                val reading = readingFile(context)
                try {
                    if (pending.exists()) {
                        if (reading.exists()) {
                            reading.appendText(pending.readText())
                            pending.delete()
                        } else {
                            pending.renameTo(reading)
                        }
                    }
                    if (!reading.exists()) return out
                    reading.forEachLine { line ->
                        if (line.isNotBlank()) {
                            try {
                                val o = JSONObject(decrypt(line))
                                out.add(mapOf(
                                    "package" to o.optString("package"),
                                    "title" to o.optString("title"),
                                    "text" to o.optString("text"),
                                    "time" to o.optLong("time")
                                ))
                            } catch (_: Exception) {
                                // Línea dañada o de una llave que ya no existe: se descarta.
                            }
                        }
                    }
                } catch (_: Exception) {
                }
            }
            return out
        }

        /// Borra lo que Flutter ya procesó.
        fun clearPending(context: Context) {
            synchronized(fileLock) {
                readingFile(context).delete()
            }
        }

        /// Llave AES del Keystore de Android: no sale del teléfono ni entra en copias.
        private fun key(): SecretKey {
            val ks = KeyStore.getInstance("AndroidKeyStore")
            ks.load(null)
            (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
            val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            gen.init(
                KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
            return gen.generateKey()
        }

        private fun encrypt(plain: String): String {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.ENCRYPT_MODE, key())
            return Base64.encodeToString(c.iv + c.doFinal(plain.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        }

        private fun decrypt(line: String): String {
            val all = Base64.decode(line, Base64.NO_WRAP)
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, all, 0, 12))
            return String(c.doFinal(all, 12, all.size - 12), Charsets.UTF_8)
        }

        @Synchronized
        private fun firstTime(key: String, token: String): Boolean = seen.getOrPut(key) { HashSet() }.add(token)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        if (!packages.contains(n.packageName)) return
        if (!isEnabled(this)) return
        val notification = n.notification ?: return
        // El resumen de un grupo repite avisos que ya llegaron uno por uno.
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        // Estilo bandeja: cada línea es un aviso, y las de antes se repiten en
        // cada actualización. Si no, el texto largo o el corto.
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.map { it.toString() }?.filter { it.isNotBlank() }.orEmpty()
        val texts: List<Pair<String, String>> = if (lines.isNotEmpty()) {
            lines.map { Pair(it, "L|$it") }
        } else {
            val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
            // Con la hora de creación: la misma compra repetida otro día no se
            // confunde con una actualización del mismo aviso.
            listOf(Pair(text, "W|${notification.`when`}|$title|$text"))
        }
        for ((text, token) in texts) {
            if (title.isBlank() && text.isBlank()) continue
            if (!firstTime(n.key, token)) continue
            val record: Map<String, Any?> = mapOf("package" to n.packageName, "title" to title, "text" to text, "time" to n.postTime)
            save(record)
            live?.get()?.invoke(record)
        }
    }

    private fun save(record: Map<String, Any?>) {
        try {
            val line = encrypt(JSONObject(record).toString())
            synchronized(fileLock) {
                val f = pendingFile(this)
                // Tope para que el archivo no crezca sin límite si la app no se abre.
                if (f.exists() && f.length() > MAX_BYTES) f.delete()
                f.appendText(line + "\n")
            }
        } catch (_: Exception) {
            // Sin Keystore no se guarda nada en claro; si la app está abierta, el
            // aviso igual llega en vivo.
        }
    }
}
