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
                val savings = widgetData.getString("total_savings", "₹0.00")
                val isHidden = widgetData.getBoolean("is_balance_hidden", true)

                // Update Balance Visibility
                if (isHidden) {
                    setViewVisibility(R.id.widget_balance, View.GONE)
                    setViewVisibility(R.id.widget_balance_dots, View.VISIBLE)
                } else {
                    setViewVisibility(R.id.widget_balance, View.VISIBLE)
                    setViewVisibility(R.id.widget_balance_dots, View.GONE)
                }

                setTextViewText(R.id.widget_balance, balance)
                setTextViewText(R.id.widget_income_summary, income)
                setTextViewText(R.id.widget_expense_summary, expense)
                setTextViewText(R.id.widget_savings_summary, "Saved $savings this month")

                // 1. Root click opens the app dashboard
                val rootIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
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

                // 3. Income Button opens Add Transaction with income type
                val incomeUri = Uri.parse("https://montra.pythonanywhere.com/transaction/add?type=income")
                val incomeIntent = Intent(Intent.ACTION_VIEW, incomeUri).apply {
                    setPackage(context.packageName)
                }
                val incomePendingIntent = PendingIntent.getActivity(
                    context, 1, incomeIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.btn_add_income, incomePendingIntent)

                // 4. Expense Button opens Add Transaction with expense type
                val expenseUri = Uri.parse("https://montra.pythonanywhere.com/transaction/add?type=expense")
                val expenseIntent = Intent(Intent.ACTION_VIEW, expenseUri).apply {
                    setPackage(context.packageName)
                }
                val expensePendingIntent = PendingIntent.getActivity(
                    context, 2, expenseIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.btn_add_expense, expensePendingIntent)
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
            onUpdate(context, appWidgetManager, appWidgetIds)
        } else {
            super.onReceive(context, intent)
        }
    }
}
