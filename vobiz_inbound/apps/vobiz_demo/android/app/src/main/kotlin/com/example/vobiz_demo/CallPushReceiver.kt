package com.example.vobiz_demo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives Vobiz's call pushes (Firebase data messages) directly, from the same
 * broadcast firebase_messaging listens to, and hands them to [CallEngine]: the
 * app's one engine, which shows the call screen and signs in.
 *
 * Only call pushes are taken (type incoming_call or call_ended); anything else
 * is left to Firebase.
 */
class CallPushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        val type = extras.getString("type") ?: return
        if (type != "incoming_call" && type != "call_ended") return
        val data = HashMap<String, String>()
        for (key in extras.keySet()) {
            if (key.startsWith("google.") || key.startsWith("gcm.") || key == "from" || key == "collapse_key") continue
            val value = extras.getString(key) ?: continue
            data[key] = value
        }
        CallEngine.deliverPush(context, data)
    }
}
