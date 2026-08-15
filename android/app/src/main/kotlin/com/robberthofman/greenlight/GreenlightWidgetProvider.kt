package com.robberthofman.greenlight

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetProvider

class GreenlightWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, WidgetViews.build(context))
        }
    }
}
