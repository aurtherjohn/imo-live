package com.imo.live

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Append-only, size-bounded store for monitoring events.
 *
 * Everything the monitoring stack captures — incoming SMS, call-log changes,
 * posted notifications, foreground app changes and the service's own lifecycle —
 * is written here as one JSON object per line in `monitor_events.jsonl` inside
 * the app's private storage. Nothing ever leaves the device; the Flutter side
 * reads it back through the `com.imo.live/monitor` method channel for the
 * Monitoring screen in Settings.
 *
 * Design rules:
 *
 *  * **Never crash the host.** Every write and read is wrapped; a failing
 *    store must not take down the accessibility service, the notification
 *    listener or the foreground service that called it.
 *  * **Never block the caller.** [add] hands the work to a single background
 *    executor; the UI thread only builds a small [JSONObject].
 *  * **Bounded.** The file is trimmed back to [KEEP_AFTER_TRIM] lines once it
 *    grows past [HARD_LIMIT], so a chatty device cannot grow it without end.
 */
object MonitorEventStore {

    private const val FILE_NAME = "monitor_events.jsonl"
    private const val HARD_LIMIT = 2000
    private const val KEEP_AFTER_TRIM = 600

    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "imo-monitor-store").apply { isDaemon = true }
    }

    /** Set once from the first native component that starts; null until then. */
    @Volatile
    private var appContext: Context? = null

    private val lineCount = AtomicLong(-1)

    /** Idempotent; safe to call from every component's entry point. */
    fun init(context: Context) {
        if (appContext != null) return
        synchronized(this) {
            if (appContext != null) return
            appContext = context.applicationContext
        }
    }

    /** Records one event. Payload values must be JSON primitives or null. */
    fun add(type: String, payload: Map<String, Any?> = emptyMap()) {
        val ctx = appContext ?: return
        val json = JSONObject()
        try {
            json.put("ts", System.currentTimeMillis())
            json.put("type", type)
            for ((key, value) in payload) json.put(key, value ?: JSONObject.NULL)
        } catch (_: Exception) {
            return
        }
        executor.execute {
            try {
                val file = file(ctx)
                synchronized(file) {
                    ensureCounter(file)
                    file.appendText(json.toString() + "\n")
                    lineCount.incrementAndGet()
                    if (lineCount.get() > HARD_LIMIT) trim(file)
                }
            } catch (_: Exception) {
                // Recording an event is always best-effort.
            }
        }
    }

    /**
     * Returns the newest [limit] events, newest first, optionally filtered by
     * [type]. Synchronous by design: the file is bounded at [KEEP_AFTER_TRIM]
     * lines, so this reads at most a few hundred short JSON lines — a few
     * milliseconds — and is only called from the method channel and tests.
     */
    fun query(type: String?, limit: Int): List<Map<String, Any?>> {
        val ctx = appContext ?: return emptyList()
        val out = ArrayList<Map<String, Any?>>(minOf(limit, 64))
        try {
            val file = file(ctx)
            if (!file.exists()) return emptyList()
            val lines = ArrayList<String>()
            synchronized(file) {
                file.forEachLine { if (it.isNotBlank()) lines.add(it) }
            }
            for (i in lines.indices.reversed()) {
                if (out.size >= limit) break
                try {
                    val obj = JSONObject(lines[i])
                    if (type != null && obj.optString("type") != type) continue
                    val map = HashMap<String, Any?>()
                    for (key in obj.keys()) {
                        map[key] = if (obj.isNull(key)) null else obj.opt(key)
                    }
                    out.add(map)
                } catch (_: Exception) {
                    // Skip a malformed line rather than drop the whole file.
                }
            }
        } catch (_: Exception) {
            // Reading is best-effort too.
        }
        return out
    }

    /** Deletes every recorded event. */
    fun clear() {
        val ctx = appContext ?: return
        executor.execute {
            try {
                val file = file(ctx)
                synchronized(file) {
                    file.delete()
                    lineCount.set(0)
                }
            } catch (_: Exception) {
                // Ignored.
            }
        }
    }

    // -------------------------------------------------------------- internals

    private fun file(context: Context): File =
        File(context.filesDir, FILE_NAME)

    /** Loads the line counter once per process from the file's real length. */
    private fun ensureCounter(file: File) {
        if (lineCount.get() >= 0) return
        var count = 0L
        if (file.exists()) {
            file.forEachLine { if (it.isNotBlank()) count++ }
        }
        lineCount.set(count)
    }

    /** Rewrites the file keeping only the newest [KEEP_AFTER_TRIM] lines. */
    private fun trim(file: File) {
        val lines = ArrayList<String>()
        file.forEachLine { if (it.isNotBlank()) lines.add(it) }
        val keep = if (lines.size > KEEP_AFTER_TRIM) {
            lines.subList(lines.size - KEEP_AFTER_TRIM, lines.size)
        } else {
            lines
        }
        val tmp = File(file.parentFile, "$FILE_NAME.tmp")
        tmp.writeText(keep.joinToString(separator = "\n", postfix = "\n"))
        if (!tmp.renameTo(file)) {
            // Some filesystems cannot rename over an open file; fall back to a
            // plain overwrite.
            file.writeText(keep.joinToString(separator = "\n", postfix = "\n"))
            tmp.delete()
        }
        lineCount.set(keep.size.toLong())
    }
}
