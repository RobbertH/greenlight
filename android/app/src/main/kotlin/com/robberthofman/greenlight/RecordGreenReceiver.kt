package com.robberthofman.greenlight

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

/// Handles the widget's green button 100% natively: captures the timestamp at
/// tap time, appends it to the pending queue the Flutter app merges into
/// SQLite, and refreshes the widget for instant feedback. No Flutter engine.
class RecordGreenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val tsMs = System.currentTimeMillis() // capture before anything else
        if (intent.action != WidgetViews.ACTION_RECORD) return

        val prefs = WidgetViews.prefs(context)
        val lightId = prefs.getString("active_light_id", null) ?: return

        val pending = runCatching {
            JSONArray(prefs.getString("pending_events", "[]") ?: "[]")
        }.getOrElse { JSONArray() }
        pending.put(JSONObject().put("lightId", lightId).put("ts", tsMs))

        val today = WidgetViews.todayString(tsMs)
        val count =
            if (prefs.getString("count_date", null) == today)
                runCatching { prefs.getInt("today_count", 0) }.getOrDefault(0) + 1
            else 1

        // commit(), not apply(): the receiver's process may be killed right
        // after onReceive returns.
        prefs.edit()
            .putString("pending_events", pending.toString())
            .putLong("last_recorded_ms", tsMs)
            .putString("count_date", today)
            .putInt("today_count", count)
            .commit()

        AppWidgetManager.getInstance(context).updateAppWidget(
            ComponentName(context, GreenlightWidgetProvider::class.java),
            WidgetViews.build(context)
        )
    }
}
