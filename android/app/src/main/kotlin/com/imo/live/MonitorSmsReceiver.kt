package com.imo.live

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Records incoming SMS the moment the system delivers them.
 *
 * Manifest-registered for `SMS_RECEIVED`; the system only delivers that
 * broadcast to receivers holding `RECEIVE_SMS`, which the first-run permission
 * flow requests. Messages from the same sender that make up one long SMS
 * arrive as several PDUs and are concatenated before recording.
 */
class MonitorSmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        MonitorEventStore.init(context)
        try {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
            if (messages.isEmpty()) return
            // One logical message can span several PDUs; group by sender and
            // stitch the bodies back together in arrival order.
            val bodies = LinkedHashMap<String, StringBuilder>()
            for (message in messages) {
                val sender = message.displayOriginatingAddress ?: continue
                val body = bodies.getOrPut(sender) { StringBuilder() }
                body.append(message.displayMessageBody ?: "")
            }
            for ((sender, body) in bodies) {
                if (body.isBlank()) continue
                MonitorEventStore.add(
                    "sms",
                    mapOf(
                        "from" to sender,
                        "body" to body.toString().take(1000),
                    ),
                )
            }
        } catch (_: Exception) {
            // Recording is best-effort; a malformed PDU must not crash the
            // broadcast chain (the default SMS app still has to see it).
        }
    }
}
