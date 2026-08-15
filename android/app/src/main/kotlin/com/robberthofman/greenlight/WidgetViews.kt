package com.robberthofman.greenlight

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object WidgetViews {
    const val ACTION_RECORD = "com.robberthofman.greenlight.RECORD_GREEN"

    // The exact SharedPreferences file home_widget's Dart saveWidgetData
    // writes to; key names mirror lib/constants.dart.
    const val PREFS_FILE = "HomeWidgetPreferences"

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)

    fun todayString(tsMs: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(tsMs))

    fun build(context: Context): RemoteViews {
        val p = prefs(context)
        val name = p.getString("active_light_name", null)
        val storedCount = readIntSafe(p, "today_count")
        val countIsToday =
            p.getString("count_date", null) == todayString(System.currentTimeMillis())
        val today = if (countIsToday) storedCount else 0

        val views = RemoteViews(context.packageName, R.layout.greenlight_widget)
        if (name == null) {
            views.setTextViewText(R.id.txt_name, "Greenlight")
            views.setTextViewText(R.id.txt_status, "Open the app and pick a light")
        } else {
            views.setTextViewText(R.id.txt_name, name)
            views.setTextViewText(
                R.id.txt_status,
                if (today == 1) "1 green today" else "$today greens today"
            )
        }

        // The big button records natively — no app launch, no Flutter engine.
        val record = Intent(context, RecordGreenReceiver::class.java)
            .setAction(ACTION_RECORD)
        views.setOnClickPendingIntent(
            R.id.btn_green,
            PendingIntent.getBroadcast(
                context, 0, record,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )

        // The header opens the app straight onto the record screen.
        views.setOnClickPendingIntent(
            R.id.header,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("greenlight://record?homeWidget")
            )
        )
        return views
    }

    // Dart ints arrive as Int or Long depending on magnitude; never let a
    // type mismatch crash the widget.
    private fun readIntSafe(p: SharedPreferences, key: String): Int =
        runCatching { p.getInt(key, 0) }
            .getOrElse { runCatching { p.getLong(key, 0L).toInt() }.getOrDefault(0) }
}
