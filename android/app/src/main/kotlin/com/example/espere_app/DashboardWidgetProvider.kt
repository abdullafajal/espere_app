package com.example.espere_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class DashboardWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.dashboard_widget).apply {
                // Get data from SharedPreferences (set from Flutter)
                val balance = widgetData.getString("total_balance", "₹0.00")
                val income = widgetData.getString("total_income", "₹0")
                val expense = widgetData.getString("total_expense", "₹0")
                val savings = widgetData.getString("total_savings", "₹0")
                val isHidden = widgetData.getBoolean("is_balance_hidden", true)

                // Update Balance Visibility and Eye Icon
                if (isHidden) {
                    setImageViewResource(R.id.btn_hide_balance, R.drawable.ic_eye_hide)
                    setViewVisibility(R.id.widget_balance, View.GONE)
                    setViewVisibility(R.id.widget_balance_dots, View.VISIBLE)
                } else {
                    setImageViewResource(R.id.btn_hide_balance, R.drawable.ic_eye_show)
                    setViewVisibility(R.id.widget_balance, View.VISIBLE)
                    setViewVisibility(R.id.widget_balance_dots, View.GONE)
                }

                setTextViewText(R.id.widget_balance, balance)
                setTextViewText(R.id.widget_income_summary, income)
                setTextViewText(R.id.widget_expense_summary, expense)
                setTextViewText(R.id.widget_savings_summary, savings)

                // 1. Root click opens the app dashboard
                val rootIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: Intent(context, MainActivity::class.java)
                val rootPendingIntent = PendingIntent.getActivity(
                    context, 0, rootIntent, 
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_root, rootPendingIntent)

                // 2. Hide/Show balance toggle
                val toggleIntent = Intent(context, DashboardWidgetProvider::class.java).apply {
                    action = "TOGGLE_BALANCE"
                }
                val togglePendingIntent = PendingIntent.getBroadcast(
                    context, 0, toggleIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.btn_hide_balance, togglePendingIntent)

                // 3. Plus Button opens Add Transaction
                val plusUri = Uri.parse("https://montra.pythonanywhere.com/transaction/add")
                val plusIntent = Intent(Intent.ACTION_VIEW, plusUri).apply {
                    setPackage(context.packageName)
                }
                val plusPendingIntent = PendingIntent.getActivity(
                    context, 1, plusIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.btn_add_transaction, plusPendingIntent)

                // 4. Receipt Button opens Transaction List
                val listUri = Uri.parse("https://montra.pythonanywhere.com/transactions")
                val listIntent = Intent(Intent.ACTION_VIEW, listUri).apply {
                    setPackage(context.packageName)
                }
                val listPendingIntent = PendingIntent.getActivity(
                    context, 2, listIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.btn_view_list, listPendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "TOGGLE_BALANCE") {
            val widgetData = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val current = widgetData.getBoolean("is_balance_hidden", true)
            widgetData.edit().putBoolean("is_balance_hidden", !current).apply()
            
            // Trigger update manually
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, DashboardWidgetProvider::class.java)
            )
            onUpdate(context, appWidgetManager, appWidgetIds, widgetData)
        } else {
            super.onReceive(context, intent)
        }
    }
}
