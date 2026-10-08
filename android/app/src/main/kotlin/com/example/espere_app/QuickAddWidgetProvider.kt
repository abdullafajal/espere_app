package com.example.espere_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class CategoryItem(val id: Int, val name: String, val icon: String, val color: String)

data class FinancialMetrics(
    val totalSpend: String,
    val totalIncome: String,
    val todaySpend: String,
    val avgDaily: String
)

class QuickAddWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val PREFS_NAME = "QuickAddWidgetPreferences"
        const val FLUTTER_PREFS = "FlutterSharedPreferences"
        const val HOME_WIDGET_PREFS = "HomeWidgetPreferences"

        const val KEY_AMOUNT = "widget_amount"
        const val KEY_NOTE = "widget_note"
        const val KEY_LAST_SAVED_SUMMARY = "widget_last_saved_summary"
        const val EXTRA_PREFILL_AMOUNT = "prefill_amount"

        val DEFAULT_CATEGORIES = listOf(
            CategoryItem(1, "Food", "restaurant", "#FF9800"),
            CategoryItem(2, "Grocery", "shopping_bag", "#4CAF50"),
            CategoryItem(3, "Transport", "directions_car", "#2196F3"),
            CategoryItem(4, "Shopping", "checkroom", "#E91E63"),
            CategoryItem(5, "Bills", "payments", "#FF5722"),
            CategoryItem(6, "Other", "category", "#607D8B"),
            CategoryItem(7, "Health", "local_hospital", "#00BCD4"),
            CategoryItem(8, "Entertainment", "movie", "#9C27B0")
        )

        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, QuickAddWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            val intent = Intent(context, QuickAddWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
            }
            context.sendBroadcast(intent)
        }

        fun getCategories(context: Context): List<CategoryItem> {
            val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val raw = flutterPrefs.getString("flutter.cache_categories", null)
            if (raw != null) {
                try {
                    val json = JSONObject(raw)
                    val arr = json.optJSONArray("categories")
                    if (arr != null && arr.length() > 0) {
                        val list = mutableListOf<CategoryItem>()
                        for (i in 0 until arr.length()) {
                            val item = arr.getJSONObject(i)
                            val type = item.optString("type", "expense")
                            if (type == "expense") {
                                list.add(
                                    CategoryItem(
                                        id = item.optInt("id", i + 1),
                                        name = item.optString("name", "Other"),
                                        icon = item.optString("icon", "category"),
                                        color = item.optString("color", "#FF9800")
                                    )
                                )
                            }
                        }
                        if (list.isNotEmpty()) return list
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            return DEFAULT_CATEGORIES
        }

        fun getCurrencySymbol(context: Context): String {
            val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val raw = flutterPrefs.getString("flutter.cache_categories", null)
            if (raw != null) {
                try {
                    val json = JSONObject(raw)
                    val sym = json.optString("currency_symbol")
                    if (sym.isNotEmpty()) return sym
                } catch (_: Exception) {}
            }
            val homeWidgetPrefs = context.getSharedPreferences(HOME_WIDGET_PREFS, Context.MODE_PRIVATE)
            val homeSym = homeWidgetPrefs.getString("currency_symbol", null)
            if (!homeSym.isNullOrEmpty()) return homeSym

            return "₹"
        }

        fun getCategoryDrawable(icon: String, name: String = ""): Int {
            val iconNorm = icon.lowercase(Locale.ROOT).trim()
            val resId = when (iconNorm) {
                // Food & Dining
                "restaurant", "fastfood" -> R.drawable.ic_cat_food
                "coffee", "local_cafe" -> R.drawable.ic_cat_coffee

                // Grocery & Daily Needs
                "shopping_bag", "local_grocery_store", "store" -> R.drawable.ic_cat_grocery

                // Transport & Travel
                "directions_car", "directions_bus", "drive_eta", "trip" -> R.drawable.ic_cat_transport
                "flight", "flight_takeoff", "airplane_ticket" -> R.drawable.ic_cat_flight
                "local_gas_station", "ev_station" -> R.drawable.ic_cat_fuel

                // Home & Housing
                "home", "house" -> R.drawable.ic_cat_home

                // Work & Career
                "work", "business_center" -> R.drawable.ic_cat_work

                // Education
                "school", "menu_book" -> R.drawable.ic_cat_school

                // Health & Fitness
                "fitness_center" -> R.drawable.ic_cat_fitness
                "local_hospital", "medical_services", "emergency", "healing" -> R.drawable.ic_cat_health

                // Shopping & Fashion
                "checkroom" -> R.drawable.ic_cat_shopping

                // Bills & Utilities
                "payments", "receipt_long", "receipt" -> R.drawable.ic_cat_bills
                "electric_bolt", "flash_on", "bolt" -> R.drawable.ic_cat_electric
                "water_drop", "opacity" -> R.drawable.ic_cat_water

                // Entertainment & Leisure
                "movie", "theaters" -> R.drawable.ic_cat_entertainment
                "sports_esports", "videogame_asset" -> R.drawable.ic_cat_gaming
                "sports_soccer", "sports" -> R.drawable.ic_cat_sports
                "celebration", "redeem", "card_giftcard", "cake" -> R.drawable.ic_cat_celebration
                "music_note", "queue_music" -> R.drawable.ic_cat_music

                // Pets & Family & Relationships
                "pets" -> R.drawable.ic_cat_pets
                "favorite", "volunteer_activism" -> R.drawable.ic_cat_favorite
                "groups", "group", "family_restroom", "child_care", "people" -> R.drawable.ic_cat_groups

                // Devices & Tech
                "devices", "computer", "laptop", "phone_android" -> R.drawable.ic_cat_devices

                // Savings & Investments
                "savings", "trending_up", "account_balance" -> R.drawable.ic_cat_savings

                // Others & Hobbies
                "build", "handyman" -> R.drawable.ic_cat_build
                "brush", "palette" -> R.drawable.ic_cat_brush
                "science" -> R.drawable.ic_cat_science
                "diamond" -> R.drawable.ic_cat_diamond

                else -> 0
            }

            if (resId != 0) return resId

            // Smart fallback based on category name if icon was generic or unrecognized
            val nameNorm = name.lowercase(Locale.ROOT).trim()
            return when {
                nameNorm.contains("coffee") || nameNorm.contains("cafe") || nameNorm.contains("tea") -> R.drawable.ic_cat_coffee
                nameNorm.contains("food") || nameNorm.contains("lunch") || nameNorm.contains("dinner") ||
                        nameNorm.contains("meal") || nameNorm.contains("snack") || nameNorm.contains("rest") -> R.drawable.ic_cat_food
                nameNorm.contains("grocer") || nameNorm.contains("mart") || nameNorm.contains("veg") -> R.drawable.ic_cat_grocery
                nameNorm.contains("flight") || nameNorm.contains("plane") || nameNorm.contains("travel") ||
                        nameNorm.contains("tour") || nameNorm.contains("trip") -> R.drawable.ic_cat_flight
                nameNorm.contains("fuel") || nameNorm.contains("petrol") || nameNorm.contains("diesel") || nameNorm.contains("gas") -> R.drawable.ic_cat_fuel
                nameNorm.contains("car") || nameNorm.contains("bus") || nameNorm.contains("train") ||
                        nameNorm.contains("cab") || nameNorm.contains("uber") || nameNorm.contains("ola") ||
                        nameNorm.contains("transport") || nameNorm.contains("metro") -> R.drawable.ic_cat_transport
                nameNorm.contains("home") || nameNorm.contains("rent") || nameNorm.contains("house") ||
                        nameNorm.contains("flat") || nameNorm.contains("room") || nameNorm.contains("apartment") -> R.drawable.ic_cat_home
                nameNorm.contains("work") || nameNorm.contains("office") || nameNorm.contains("job") ||
                        nameNorm.contains("business") || nameNorm.contains("salary") -> R.drawable.ic_cat_work
                nameNorm.contains("school") || nameNorm.contains("college") || nameNorm.contains("fee") ||
                        nameNorm.contains("book") || nameNorm.contains("study") || nameNorm.contains("edu") -> R.drawable.ic_cat_school
                nameNorm.contains("gym") || nameNorm.contains("fitness") || nameNorm.contains("workout") -> R.drawable.ic_cat_fitness
                nameNorm.contains("sport") || nameNorm.contains("football") || nameNorm.contains("cricket") -> R.drawable.ic_cat_sports
                nameNorm.contains("game") || nameNorm.contains("gaming") || nameNorm.contains("steam") -> R.drawable.ic_cat_gaming
                nameNorm.contains("pet") || nameNorm.contains("dog") || nameNorm.contains("cat") || nameNorm.contains("vet") -> R.drawable.ic_cat_pets
                nameNorm.contains("friend") || nameNorm.contains("group") || nameNorm.contains("family") -> R.drawable.ic_cat_groups
                nameNorm.contains("love") || nameNorm.contains("couple") || nameNorm.contains("partner") -> R.drawable.ic_cat_favorite
                nameNorm.contains("device") || nameNorm.contains("tech") || nameNorm.contains("electr") ||
                        nameNorm.contains("phone") || nameNorm.contains("laptop") || nameNorm.contains("gadget") -> R.drawable.ic_cat_devices
                nameNorm.contains("movie") || nameNorm.contains("cinema") || nameNorm.contains("netflix") ||
                        nameNorm.contains("ott") || nameNorm.contains("show") || nameNorm.contains("film") -> R.drawable.ic_cat_entertainment
                nameNorm.contains("party") || nameNorm.contains("celebrat") || nameNorm.contains("event") ||
                        nameNorm.contains("birthday") || nameNorm.contains("gift") -> R.drawable.ic_cat_celebration
                nameNorm.contains("bill") || nameNorm.contains("recharge") || nameNorm.contains("wifi") ||
                        nameNorm.contains("broadband") || nameNorm.contains("utility") -> R.drawable.ic_cat_bills
                nameNorm.contains("health") || nameNorm.contains("doctor") || nameNorm.contains("med") ||
                        nameNorm.contains("hospital") || nameNorm.contains("pharma") || nameNorm.contains("clinic") -> R.drawable.ic_cat_health
                nameNorm.contains("shop") || nameNorm.contains("cloth") || nameNorm.contains("dress") ||
                        nameNorm.contains("shoe") || nameNorm.contains("wear") || nameNorm.contains("fashion") -> R.drawable.ic_cat_shopping
                nameNorm.contains("save") || nameNorm.contains("invest") || nameNorm.contains("sip") ||
                        nameNorm.contains("mutual") || nameNorm.contains("stock") -> R.drawable.ic_cat_savings
                nameNorm.contains("repair") || nameNorm.contains("service") || nameNorm.contains("tool") -> R.drawable.ic_cat_build
                nameNorm.contains("water") -> R.drawable.ic_cat_water
                nameNorm.contains("power") || nameNorm.contains("current") -> R.drawable.ic_cat_electric
                nameNorm.contains("music") || nameNorm.contains("song") || nameNorm.contains("spotify") -> R.drawable.ic_cat_music
                nameNorm.contains("jewel") || nameNorm.contains("gold") || nameNorm.contains("diamond") -> R.drawable.ic_cat_diamond
                else -> R.drawable.ic_cat_other
            }
        }


        fun triggerHaptic(context: Context, isSuccess: Boolean = false) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    val vibrator = vibratorManager?.defaultVibrator
                    val effect = if (isSuccess) {
                        VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK)
                    } else {
                        VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                    }
                    vibrator?.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val duration = if (isSuccess) 40L else 20L
                        vibrator?.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator?.vibrate(20L)
                    }
                }
            } catch (_: Exception) {}
        }

        fun executeSave(
            context: Context,
            amount: Double,
            catId: Int,
            catName: String,
            catIcon: String,
            catColor: String,
            paymentMethod: String,
            paymentDisplay: String,
            notes: String
        ) {
            val tempId = System.currentTimeMillis()
            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            val dateIso = isoFormat.format(Date())
            val formattedAmount = String.format(Locale.US, "%.2f", amount)

            val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

            // 1. Prepare Transaction JSON Object
            val catJson = JSONObject().apply {
                put("id", catId)
                put("name", catName)
                put("icon", catIcon)
                put("color", catColor)
                put("is_system", true)
                put("type", "expense")
            }

            val txnJson = JSONObject().apply {
                put("id", tempId)
                put("amount", formattedAmount)
                put("type", "expense")
                put("category", catJson)
                put("date", dateIso)
                put("payment_method", paymentMethod)
                put("payment_method_display", paymentDisplay)
                put("notes", notes)
            }

            // 2. Persist to flutter.cache_transactions
            try {
                val rawTxns = flutterPrefs.getString("flutter.cache_transactions", null)
                val txnsRoot = if (rawTxns != null) JSONObject(rawTxns) else JSONObject()
                val txnsArray = txnsRoot.optJSONArray("transactions") ?: JSONArray()
                val newTxnsArray = JSONArray()
                newTxnsArray.put(txnJson)
                for (i in 0 until txnsArray.length()) {
                    newTxnsArray.put(txnsArray.getJSONObject(i))
                }
                txnsRoot.put("transactions", newTxnsArray)
                if (!txnsRoot.has("currency_symbol")) {
                    txnsRoot.put("currency_symbol", getCurrencySymbol(context))
                }
                flutterPrefs.edit().putString("flutter.cache_transactions", txnsRoot.toString()).commit()
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // 3. Persist to flutter.cache_dashboard (optimistic totals update)
            try {
                val rawDashboard = flutterPrefs.getString("flutter.cache_dashboard", null)
                val dObj = if (rawDashboard != null) JSONObject(rawDashboard) else JSONObject()
                
                val curBalance = dObj.optString("total_balance", "0.00").replace(",", "").toDoubleOrNull() ?: 0.0
                val curExpenses = dObj.optString("monthly_expenses", "0.00").replace(",", "").toDoubleOrNull() ?: 0.0
                val curSavings = dObj.optString("monthly_savings", "0.00").replace(",", "").toDoubleOrNull() ?: 0.0
                val curIncome = dObj.optString("monthly_income", "0.00").replace(",", "").toDoubleOrNull() ?: 0.0

                val newBalance = curBalance - amount
                val newExpenses = curExpenses + amount
                val newSavings = curSavings - amount

                dObj.put("total_balance", String.format(Locale.US, "%.2f", newBalance))
                dObj.put("monthly_expenses", String.format(Locale.US, "%.2f", newExpenses))
                dObj.put("monthly_savings", String.format(Locale.US, "%.2f", newSavings))
                if (!dObj.has("monthly_income")) {
                    dObj.put("monthly_income", String.format(Locale.US, "%.2f", curIncome))
                }

                val recentArray = dObj.optJSONArray("recent_transactions") ?: JSONArray()
                val newRecent = JSONArray()
                newRecent.put(txnJson)
                for (i in 0 until Math.min(recentArray.length(), 4)) {
                    newRecent.put(recentArray.getJSONObject(i))
                }
                dObj.put("recent_transactions", newRecent)

                // Update category in pie chart if cached
                val pieLabels = dObj.optJSONArray("pie_labels")
                val pieValues = dObj.optJSONArray("pie_values")
                val pieColors = dObj.optJSONArray("pie_colors")
                if (pieLabels != null && pieValues != null && pieColors != null) {
                    var found = false
                    for (i in 0 until pieLabels.length()) {
                        if (pieLabels.optString(i) == catName) {
                            val v = pieValues.optDouble(i, 0.0) + amount
                            pieValues.put(i, v)
                            found = true
                            break
                        }
                    }
                    if (!found) {
                        pieLabels.put(catName)
                        pieValues.put(amount)
                        pieColors.put(catColor)
                    }
                }

                flutterPrefs.edit().putString("flutter.cache_dashboard", dObj.toString()).commit()

                // Also update HomeWidgetPreferences for dashboard widgets
                val currency = getCurrencySymbol(context)
                val homeWidgetPrefs = context.getSharedPreferences(HOME_WIDGET_PREFS, Context.MODE_PRIVATE)
                homeWidgetPrefs.edit()
                    .putString("total_balance", "$currency${String.format(Locale.US, "%.2f", newBalance)}")
                    .putString("total_expense", "$currency${newExpenses.toInt()}")
                    .putString("total_savings", "$currency${String.format(Locale.US, "%.2f", newSavings)}")
                    .commit()
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // 4. Add to flutter.sync_queue
            try {
                val rawQueue = flutterPrefs.getString("flutter.sync_queue", "[]")
                val queueArray = JSONArray(rawQueue ?: "[]")
                val op = JSONObject().apply {
                    put("id", "${tempId}000")
                    put("action", "create")
                    put("entity", "transaction")
                    put("data", JSONObject().apply {
                        put("amount", formattedAmount)
                        put("type", "expense")
                        put("category_id", catId)
                        put("date", dateIso)
                        put("payment_method", paymentMethod)
                        put("notes", notes)
                    })
                    put("entityId", tempId)
                    put("createdAt", dateIso)
                }
                queueArray.put(op)
                flutterPrefs.edit().putString("flutter.sync_queue", queueArray.toString()).commit()
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // 5. Asynchronous Background Sync to Django Backend if online
            Thread {
                attemptBackgroundSync(context, tempId, formattedAmount, catId, dateIso, paymentMethod, notes)
            }.start()

            // 6. Update QuickAdd widget summary
            val currency = getCurrencySymbol(context)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putString(KEY_LAST_SAVED_SUMMARY, "Last: $currency$formattedAmount • $catName ($paymentDisplay)")
                .commit()

            triggerHaptic(context, isSuccess = true)
            updateAllWidgets(context)
        }

        private fun attemptBackgroundSync(
            context: Context,
            tempId: Long,
            amount: String,
            categoryId: Int,
            date: String,
            paymentMethod: String,
            notes: String
        ) {
            val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
            val activeNet = connectivity.activeNetwork ?: return
            val caps = connectivity.getNetworkCapabilities(activeNet) ?: return
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return

            val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val token = flutterPrefs.getString("flutter.auth_token", null) ?: return
            if (token.isEmpty()) return

            val baseUrl = flutterPrefs.getString("flutter.base_url", "https://montra.pythonanywhere.com") ?: "https://montra.pythonanywhere.com"

            try {
                val url = URL("$baseUrl/api/transactions/")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Authorization", "Bearer $token") // Fixed: Bearer instead of Token
                conn.doOutput = true
                conn.connectTimeout = 8000
                conn.readTimeout = 8000

                val payload = JSONObject().apply {
                    put("amount", amount)
                    put("type", "expense")
                    put("category_id", categoryId)
                    put("date", date)
                    put("payment_method", paymentMethod)
                    put("notes", notes)
                }

                OutputStreamWriter(conn.outputStream).use { writer ->
                    writer.write(payload.toString())
                    writer.flush()
                }

                if (conn.responseCode == 201) {
                    val resp = conn.inputStream.bufferedReader().use { it.readText() }
                    val respJson = JSONObject(resp)
                    val realTxn = respJson.optJSONObject("transaction")
                    val realId = realTxn?.optInt("id", 0) ?: 0

                    val rawQueue = flutterPrefs.getString("flutter.sync_queue", "[]")
                    val queueArray = JSONArray(rawQueue ?: "[]")
                    val cleanArray = JSONArray()
                    for (i in 0 until queueArray.length()) {
                        val item = queueArray.getJSONObject(i)
                        if (item.optLong("entityId") != tempId) {
                            cleanArray.put(item)
                        }
                    }
                    flutterPrefs.edit().putString("flutter.sync_queue", cleanArray.toString()).commit()

                    // Update cached transactions with the real server-returned object
                    if (realId > 0 && realTxn != null) {
                        try {
                            val rTxns = flutterPrefs.getString("flutter.cache_transactions", null)
                            if (rTxns != null) {
                                val tRoot = JSONObject(rTxns)
                                val tArr = tRoot.optJSONArray("transactions")
                                if (tArr != null) {
                                    for (i in 0 until tArr.length()) {
                                        val obj = tArr.getJSONObject(i)
                                        if (obj.optLong("id") == tempId) {
                                            tArr.put(i, realTxn)
                                            break
                                        }
                                    }
                                    flutterPrefs.edit().putString("flutter.cache_transactions", tRoot.toString()).commit()
                                }
                            }
                        } catch (_: Exception) {}
                    }
                }
                conn.disconnect()
            } catch (e: Exception) {
                // Stays in queue for Flutter SyncService
            }
        }

        private fun parseTransactionDate(dateStr: String?): Calendar? {
            if (dateStr.isNullOrEmpty()) return null
            val formats = arrayOf(
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") },
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") },
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US),
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US),
                SimpleDateFormat("yyyy-MM-dd", Locale.US)
            )
            for (sdf in formats) {
                try {
                    val d = sdf.parse(dateStr)
                    if (d != null) {
                        val cal = Calendar.getInstance()
                        cal.time = d
                        return cal
                    }
                } catch (_: Exception) {}
            }
            if (dateStr.length >= 10 && dateStr[4] == '-' && dateStr[7] == '-') {
                try {
                    val y = dateStr.substring(0, 4).toInt()
                    val m = dateStr.substring(5, 7).toInt() - 1
                    val d = dateStr.substring(8, 10).toInt()
                    val cal = Calendar.getInstance()
                    cal.set(y, m, d, 0, 0, 0)
                    return cal
                } catch (_: Exception) {}
            }
            return null
        }

        fun getFinancialMetrics(context: Context): FinancialMetrics {
            val currency = getCurrencySymbol(context)
            val numFormat = NumberFormat.getNumberInstance(Locale.US).apply {
                minimumFractionDigits = 2
                maximumFractionDigits = 2
            }

            val homeWidgetPrefs = context.getSharedPreferences(HOME_WIDGET_PREFS, Context.MODE_PRIVATE)
            val homeSpend = homeWidgetPrefs.getString("widget_total_spend", null)
            val homeIncome = homeWidgetPrefs.getString("widget_total_income", null)
            val homeToday = homeWidgetPrefs.getString("widget_today_spend", null)
            val homeAvg = homeWidgetPrefs.getString("widget_avg_daily", null)

            val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val rawTxns = flutterPrefs.getString("flutter.cache_transactions", null)

            var calculatedTotalSpend = 0.0
            var calculatedTotalIncome = 0.0
            var calculatedTodaySpend = 0.0
            var hasTxns = false

            val now = Calendar.getInstance()
            val curYear = now.get(Calendar.YEAR)
            val curMonth = now.get(Calendar.MONTH)
            val curDay = now.get(Calendar.DAY_OF_MONTH)
            val daysPassed = if (curDay > 0) curDay else 1

            if (!rawTxns.isNullOrEmpty()) {
                try {
                    val json = JSONObject(rawTxns)
                    val arr = json.optJSONArray("transactions")
                    if (arr != null && arr.length() > 0) {
                        hasTxns = true
                        for (i in 0 until arr.length()) {
                            val t = arr.getJSONObject(i)
                            val type = t.optString("type", "expense")
                            val amtStr = t.optString("amount", "0.0")
                            val amt = amtStr.toDoubleOrNull() ?: t.optDouble("amount", 0.0)
                            val dateCal = parseTransactionDate(t.optString("date", "")) ?: continue

                            if (dateCal.get(Calendar.YEAR) == curYear && dateCal.get(Calendar.MONTH) == curMonth) {
                                if (type.equals("income", ignoreCase = true)) {
                                    calculatedTotalIncome += amt
                                } else {
                                    calculatedTotalSpend += amt
                                    if (dateCal.get(Calendar.DAY_OF_MONTH) == curDay) {
                                        calculatedTodaySpend += amt
                                    }
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }

            if (hasTxns) {
                val calculatedAvgDaily = calculatedTotalSpend / daysPassed
                return FinancialMetrics(
                    totalSpend = "$currency${numFormat.format(calculatedTotalSpend)}",
                    totalIncome = "$currency${numFormat.format(calculatedTotalIncome)}",
                    todaySpend = "$currency${numFormat.format(calculatedTodaySpend)}",
                    avgDaily = "$currency${numFormat.format(calculatedAvgDaily)}"
                )
            }

            if (!homeSpend.isNullOrEmpty() && !homeIncome.isNullOrEmpty()) {
                return FinancialMetrics(
                    totalSpend = homeSpend,
                    totalIncome = homeIncome,
                    todaySpend = homeToday ?: "$currency 0.00",
                    avgDaily = homeAvg ?: "$currency 0.00"
                )
            }

            // Fallback: check dashboard cache
            val rawDash = flutterPrefs.getString("flutter.cache_dashboard", null)
            if (!rawDash.isNullOrEmpty()) {
                try {
                    val dashJson = JSONObject(rawDash)
                    val exp = dashJson.optString("monthly_expenses", "0.0").replace(",", "").toDoubleOrNull() ?: 0.0
                    val inc = dashJson.optString("monthly_income", "0.0").replace(",", "").toDoubleOrNull() ?: 0.0
                    val avg = exp / daysPassed
                    return FinancialMetrics(
                        totalSpend = "$currency${numFormat.format(exp)}",
                        totalIncome = "$currency${numFormat.format(inc)}",
                        todaySpend = "$currency${numFormat.format(0.0)}",
                        avgDaily = "$currency${numFormat.format(avg)}"
                    )
                } catch (_: Exception) {}
            }

            return FinancialMetrics(
                totalSpend = "$currency 0.00",
                totalIncome = "$currency 0.00",
                todaySpend = "$currency 0.00",
                avgDaily = "$currency 0.00"
            )
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val metrics = getFinancialMetrics(context)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.quick_add_widget)

            // Bind 2x2 Financial Metrics
            views.setTextViewText(R.id.widget_total_spend, metrics.totalSpend)
            views.setTextViewText(R.id.widget_total_income, metrics.totalIncome)
            views.setTextViewText(R.id.widget_today_spend, metrics.todaySpend)
            views.setTextViewText(R.id.widget_avg_daily, metrics.avgDaily)

            // Tint logo icon to exact Add Expense button background color
            val primaryColor = ContextCompat.getColor(context, R.color.quick_widget_primary)
            views.setInt(R.id.widget_app_logo, "setColorFilter", primaryColor)

            // 1. Main Action: Tap card or plus to open all-in-one Quick Add Popup
            val openDialogPendingIntent = createOpenDialogPendingIntent(context, 0.0, 1001)
            views.setOnClickPendingIntent(R.id.widget_root, openDialogPendingIntent)
            views.setOnClickPendingIntent(R.id.btn_open_quick_add, openDialogPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_btn_plus, openDialogPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun createOpenDialogPendingIntent(context: Context, prefillAmount: Double, requestCode: Int): PendingIntent {
        val intent = Intent(context, QuickAmountDialogActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_PREFILL_AMOUNT, prefillAmount)
        }
        return PendingIntent.getActivity(
            context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
