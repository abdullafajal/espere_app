package com.example.espere_app

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.PathInterpolator
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.GridLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import org.json.JSONObject
import java.util.Locale
import kotlin.math.max

/**
 * Quick Add popup opened from the home-screen widget. Three steps:
 *   1. Amount   2. Category   3. Payment method + optional note -> Save
 *
 * The category and payment method the user picks most come pre-selected, so the usual
 * flow is: type amount -> Continue -> tap category (moves on by itself) -> Save.
 *
 * Motion: steps use a shared-axis transition (slide a little + fade) while the sheet
 * height glides to the new size; the progress bar fills, the title cross-fades, and
 * the sheet rides along with the keyboard instead of jumping.
 */
class QuickAmountDialogActivity : Activity() {

    companion object {
        private const val KEY_LAST_PAYMENT = "qa_last_payment"
        private const val KEY_LAST_CATEGORY = "qa_last_category"
        private const val KEY_CATEGORY_USES = "qa_category_uses"

        private const val STEP_AMOUNT = 0
        private const val STEP_CATEGORY = 1
        private const val STEP_DETAILS = 2

        private const val STEP_MS = 340L
        private const val VISIBLE_CATEGORY_ROWS = 3

        private val PAYMENTS = listOf(
            Triple("upi", "UPI", R.drawable.ic_pay_upi),
            Triple("cash", "Cash", R.drawable.ic_pay_cash),
            Triple("card", "Card", R.drawable.ic_pay_card),
            Triple("bank", "Bank", R.drawable.ic_pay_bank)
        )
        private val TITLES = arrayOf("How much?", "What was it for?", "How did you pay?")
    }

    /** Material "emphasized" easing: quick start, long soft landing. */
    private val ease = PathInterpolator(0.2f, 0f, 0f, 1f)

    private lateinit var root: View
    private lateinit var sheet: View
    private lateinit var stepHost: ViewGroup
    private lateinit var steps: List<View>
    private lateinit var progress: List<View>
    private lateinit var headerText: View
    private lateinit var stepLabel: TextView
    private lateinit var title: TextView

    private lateinit var amountInput: EditText
    private lateinit var amountRow: View
    private lateinit var amountNext: TextView
    private lateinit var categoryGrid: GridLayout
    private lateinit var categoryScroll: ScrollView
    private lateinit var categorySummary: TextView
    private lateinit var detailsSummary: TextView
    private lateinit var paymentRow: LinearLayout
    private lateinit var noteInput: EditText
    private lateinit var saveButton: TextView

    private var currency = "₹"
    private var categories: List<CategoryItem> = emptyList()
    private lateinit var selectedCategory: CategoryItem
    private var selectedPayment = "upi"

    private var step = STEP_AMOUNT
    private var stepAnimator: ValueAnimator? = null
    private var imeAnimating = false
    private var closing = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.dialog_quick_amount)
        applyWindowStyle()
        bindViews()
        setupInsets()

        currency = QuickAddWidgetProvider.getCurrencySymbol(this)
        findViewById<TextView>(R.id.qa_currency).text = currency

        root.setOnClickListener { close() }                 // tap outside the sheet
        findViewById<View>(R.id.btn_dialog_close).setOnClickListener { close() }

        setupAmountStep()
        setupCategoryStep()
        setupDetailsStep()

        progress.forEach { it.pivotX = 0f }
        updateProgress(animate = false)
        playEnterAnimation()
    }

    // ─── Window ─────────────────────────────────────────────────────────────────

    /** Full-screen transparent window with dim (and blur on Android 12+) behind. */
    private fun applyWindowStyle() {
        window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.setDimAmount(0.32f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            window.addFlags(WindowManager.LayoutParams.FLAG_BLUR_BEHIND)
            window.attributes = window.attributes.also { it.blurBehindRadius = 28 }
        }
        // We place the sheet above the keyboard / nav bar ourselves (see setupInsets).
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    private fun bindViews() {
        root = findViewById(R.id.qa_root)
        sheet = findViewById(R.id.qa_sheet)
        stepHost = findViewById(R.id.qa_step_host)
        steps = listOf(
            findViewById(R.id.qa_step_amount),
            findViewById(R.id.qa_step_category),
            findViewById(R.id.qa_step_details)
        )
        progress = listOf(
            findViewById(R.id.qa_progress_1),
            findViewById(R.id.qa_progress_2),
            findViewById(R.id.qa_progress_3)
        )
        headerText = findViewById(R.id.qa_header_text)
        stepLabel = findViewById(R.id.qa_step_label)
        title = findViewById(R.id.qa_title)

        amountInput = findViewById(R.id.qa_amount)
        amountRow = findViewById(R.id.qa_amount_row)
        amountNext = findViewById(R.id.btn_amount_next)
        categoryGrid = findViewById(R.id.qa_category_grid)
        categoryScroll = findViewById(R.id.qa_category_scroll)
        categorySummary = findViewById(R.id.qa_category_summary)
        detailsSummary = findViewById(R.id.qa_details_summary)
        paymentRow = findViewById(R.id.qa_payment_row)
        noteInput = findViewById(R.id.qa_note)
        saveButton = findViewById(R.id.btn_save)
    }

    /**
     * Keep the sheet above the keyboard and navigation bar. While the keyboard animates,
     * the bottom padding follows it frame by frame, so the sheet glides instead of jumping.
     */
    private fun setupInsets() {
        fun apply(insets: WindowInsetsCompat) {
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            root.setPadding(0, bars.top, 0, max(ime.bottom, bars.bottom))
        }
        ViewCompat.setOnApplyWindowInsetsListener(root) { _, insets ->
            if (!imeAnimating) apply(insets)
            insets
        }
        ViewCompat.setWindowInsetsAnimationCallback(
            root,
            object : WindowInsetsAnimationCompat.Callback(DISPATCH_MODE_STOP) {
                override fun onPrepare(animation: WindowInsetsAnimationCompat) {
                    if (animation.typeMask and WindowInsetsCompat.Type.ime() != 0) imeAnimating = true
                }

                override fun onProgress(
                    insets: WindowInsetsCompat,
                    running: MutableList<WindowInsetsAnimationCompat>
                ): WindowInsetsCompat {
                    apply(insets)
                    return insets
                }

                override fun onEnd(animation: WindowInsetsAnimationCompat) {
                    if (animation.typeMask and WindowInsetsCompat.Type.ime() != 0) {
                        imeAnimating = false
                        ViewCompat.requestApplyInsets(root)
                    }
                }
            }
        )
    }

    // ─── Enter / exit ───────────────────────────────────────────────────────────

    private fun playEnterAnimation() {
        sheet.alpha = 0f
        sheet.post {
            sheet.translationY = sheet.height * 0.6f
            sheet.animate().translationY(0f).alpha(1f)
                .setDuration(380).setInterpolator(ease).start()
            focusAmount()
        }
    }

    private fun close() {
        if (closing) return
        closing = true
        hideKeyboard()
        sheet.animate().translationY(sheet.height.toFloat() + dp(24)).alpha(0f)
            .setDuration(220).setInterpolator(PathInterpolator(0.3f, 0f, 0.8f, 0.15f))
            .withEndAction { finish() }
            .start()
    }

    override fun finish() {
        super.finish()
        // Only the dim fades; the sheet already slid away.
        @Suppress("DEPRECATION")
        overridePendingTransition(0, R.anim.qa_fade_out)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (step > STEP_AMOUNT) goTo(step - 1) else close()
    }

    // ─── Step 1: amount ─────────────────────────────────────────────────────────

    private fun setupAmountStep() {
        val prefill = intent.getDoubleExtra(QuickAddWidgetProvider.EXTRA_PREFILL_AMOUNT, 0.0)
        if (prefill > 0.0) {
            amountInput.setText(formatAmount(prefill))
            amountInput.setSelection(amountInput.text.length)
        }
        amountInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, st: Int, c: Int, a: Int) {}
            override fun onTextChanged(s: CharSequence?, st: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) = refreshAmountButtons()
        })
        amountInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_NEXT || actionId == EditorInfo.IME_ACTION_DONE) {
                confirmAmount(); true
            } else false
        }
        amountNext.setOnClickListener { confirmAmount() }
        refreshAmountButtons()
    }

    private fun amount(): Double = amountInput.text.toString().trim().toDoubleOrNull() ?: 0.0

    private fun formatAmount(v: Double): String =
        if (v % 1.0 == 0.0) v.toLong().toString() else String.format(Locale.US, "%.2f", v)

    private fun refreshAmountButtons() {
        amountNext.animate().alpha(if (amount() > 0.0) 1f else 0.5f).setDuration(150).start()
    }

    private fun confirmAmount() {
        if (amount() <= 0.0) {
            amountInput.requestFocus()
            ObjectAnimator.ofFloat(amountRow, "translationX", 0f, 18f, -18f, 12f, -12f, 6f, 0f)
                .setDuration(320).start()
            QuickAddWidgetProvider.triggerHaptic(this)
            return
        }
        QuickAddWidgetProvider.triggerHaptic(this)
        goTo(STEP_CATEGORY)
    }

    private fun focusAmount() {
        amountInput.requestFocus()
        amountInput.setSelection(amountInput.text.length)
        (getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
            ?.showSoftInput(amountInput, InputMethodManager.SHOW_IMPLICIT)
    }

    // ─── Step 2: category (most used first, last used pre-selected) ─────────────

    private fun setupCategoryStep() {
        val prefs = getSharedPreferences(QuickAddWidgetProvider.PREFS_NAME, MODE_PRIVATE)
        val uses = readUses()
        val lastId = prefs.getInt(KEY_LAST_CATEGORY, -1)
        val history = expenseCountsFromHistory()

        categories = QuickAddWidgetProvider.getCategories(this).withIndex()
            .sortedWith(compareByDescending<IndexedValue<CategoryItem>> { it.value.id == lastId }
                .thenByDescending {
                    uses.optInt(it.value.id.toString(), 0) + (history[it.value.id] ?: 0)
                }
                .thenBy { it.index })
            .map { it.value }
        selectedCategory = categories.first()

        val inflater = LayoutInflater.from(this)
        categories.forEach { cat ->
            val tile = inflater.inflate(R.layout.item_quick_tile, categoryGrid, false)
            tile.findViewById<ImageView>(R.id.chip_icon)
                .setImageResource(QuickAddWidgetProvider.getCategoryDrawable(cat.icon, cat.name))
            tile.findViewById<TextView>(R.id.chip_label).text = cat.name
            tile.contentDescription = cat.name
            tile.tag = cat.id
            tile.layoutParams = GridLayout.LayoutParams(
                GridLayout.spec(GridLayout.UNDEFINED),
                GridLayout.spec(GridLayout.UNDEFINED, 1f)
            ).apply {
                width = 0
                height = dp(78)
                setMargins(dp(4), dp(4), dp(4), dp(4))
            }
            tile.setOnClickListener {
                selectedCategory = cat
                refreshCategoryTiles()
                QuickAddWidgetProvider.triggerHaptic(this)
                // Picking a category is the answer to this step: move on by itself.
                tile.postDelayed({ if (step == STEP_CATEGORY) goTo(STEP_DETAILS) }, 160)
            }
            categoryGrid.addView(tile)
        }
        refreshCategoryTiles()

        // More than three rows: fixed height that shows a peek of the next row, rest scrolls.
        val rows = (categories.size + 3) / 4
        if (rows > VISIBLE_CATEGORY_ROWS) {
            categoryScroll.layoutParams.height = dp(86 * VISIBLE_CATEGORY_ROWS + 40)
        }

        findViewById<View>(R.id.btn_category_back).setOnClickListener { goTo(STEP_AMOUNT) }
        findViewById<View>(R.id.btn_category_next).setOnClickListener {
            QuickAddWidgetProvider.triggerHaptic(this)
            goTo(STEP_DETAILS)
        }
    }

    private fun refreshCategoryTiles() {
        for (i in 0 until categoryGrid.childCount) {
            val tile = categoryGrid.getChildAt(i)
            val selected = tile.tag == selectedCategory.id
            tile.setBackgroundResource(if (selected) R.drawable.qa_tile_selected else R.drawable.qa_tile)
            tintContent(tile, selected)
        }
    }

    /** How often each category appears in the app's cached expenses, so ranking works from day one. */
    private fun expenseCountsFromHistory(): Map<Int, Int> {
        val raw = getSharedPreferences(QuickAddWidgetProvider.FLUTTER_PREFS, MODE_PRIVATE)
            .getString("flutter.cache_transactions", null) ?: return emptyMap()
        return try {
            val arr = JSONObject(raw).optJSONArray("transactions") ?: return emptyMap()
            val counts = HashMap<Int, Int>()
            for (i in 0 until arr.length()) {
                val t = arr.optJSONObject(i) ?: continue
                if (t.optString("type", "expense") != "expense") continue
                val id = t.optJSONObject("category")?.optInt("id", -1) ?: -1
                if (id >= 0) counts[id] = (counts[id] ?: 0) + 1
            }
            counts
        } catch (_: Exception) {
            emptyMap()
        }
    }

    // ─── Step 3: payment + note ─────────────────────────────────────────────────

    private fun setupDetailsStep() {
        val prefs = getSharedPreferences(QuickAddWidgetProvider.PREFS_NAME, MODE_PRIVATE)
        selectedPayment = prefs.getString(KEY_LAST_PAYMENT, "upi")
            ?.takeIf { key -> PAYMENTS.any { it.first == key } } ?: "upi"

        val inflater = LayoutInflater.from(this)
        PAYMENTS.forEachIndexed { i, (key, label, icon) ->
            val chip = inflater.inflate(R.layout.item_quick_chip, paymentRow, false)
            chip.findViewById<ImageView>(R.id.chip_icon).setImageResource(icon)
            chip.findViewById<TextView>(R.id.chip_label).text = label
            chip.contentDescription = label
            chip.tag = key
            chip.setPadding(dp(6), 0, dp(6), 0)
            chip.layoutParams = LinearLayout.LayoutParams(0, dp(44), 1f).apply {
                marginEnd = if (i < PAYMENTS.size - 1) dp(8) else 0
            }
            chip.setOnClickListener {
                selectedPayment = key
                QuickAddWidgetProvider.triggerHaptic(this)
                refreshPaymentChips()
            }
            paymentRow.addView(chip)
        }
        refreshPaymentChips()

        noteInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) { save(); true } else false
        }
        findViewById<View>(R.id.btn_details_back).setOnClickListener { goTo(STEP_CATEGORY) }
        saveButton.setOnClickListener { save() }
    }

    private fun refreshPaymentChips() {
        for (i in 0 until paymentRow.childCount) {
            val chip = paymentRow.getChildAt(i)
            val selected = chip.tag == selectedPayment
            chip.setBackgroundResource(if (selected) R.drawable.qa_chip_selected else R.drawable.qa_chip)
            tintContent(chip, selected)
        }
    }

    private fun tintContent(item: View, selected: Boolean) {
        val color = getColor(if (selected) R.color.wp_on_block else R.color.widget_text_1)
        item.findViewById<ImageView>(R.id.chip_icon).setColorFilter(color)
        item.findViewById<TextView>(R.id.chip_label).setTextColor(color)
        item.isSelected = selected
    }

    // ─── Step transitions ───────────────────────────────────────────────────────

    private fun refreshSummaries() {
        val amt = "$currency${formatAmount(amount())}"
        categorySummary.text = amt
        detailsSummary.text = "$amt · ${selectedCategory.name}"
        saveButton.text = "Save $amt"
    }

    /**
     * Shared-axis step change: the old step drifts out (and fades) in the direction of
     * travel, the new one drifts in from the other side, and the sheet height glides
     * from one step's height to the other's - all on one eased timeline.
     */
    private fun goTo(target: Int) {
        if (target == step || closing) return
        stepAnimator?.end()
        refreshSummaries()

        val forward = target > step
        val from = steps[step]
        val to = steps[target]
        step = target

        // Keyboard: only the amount step asks for it.
        if (target == STEP_AMOUNT) focusAmount() else { hideKeyboard(); currentFocus?.clearFocus() }

        val startH = stepHost.height
        to.visibility = View.VISIBLE
        to.measure(
            View.MeasureSpec.makeMeasureSpec(stepHost.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val endH = to.measuredHeight
        stepHost.layoutParams.height = startH
        stepHost.requestLayout()

        val shift = dp(48).toFloat() * if (forward) 1 else -1
        to.alpha = 0f
        to.translationX = shift

        stepAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = STEP_MS
            interpolator = ease
            addUpdateListener {
                val p = it.animatedValue as Float
                // Outgoing finishes fading in the first ~35%, incoming starts after ~20%.
                from.alpha = (1f - p / 0.35f).coerceIn(0f, 1f)
                from.translationX = -shift * p
                to.alpha = ((p - 0.2f) / 0.8f).coerceIn(0f, 1f)
                to.translationX = shift * (1f - p)
                stepHost.layoutParams.height = (startH + (endH - startH) * p).toInt()
                stepHost.requestLayout()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    from.visibility = View.GONE
                    from.alpha = 1f
                    from.translationX = 0f
                    to.alpha = 1f
                    to.translationX = 0f
                    stepHost.layoutParams.height = ViewGroup.LayoutParams.WRAP_CONTENT
                    stepHost.requestLayout()
                    stepAnimator = null
                }
            })
            start()
        }

        crossfadeHeader(forward)
        updateProgress(animate = true)
    }

    private fun crossfadeHeader(forward: Boolean) {
        val d = dp(10).toFloat() * if (forward) 1 else -1
        headerText.animate().cancel()
        headerText.animate().alpha(0f).translationX(-d).setDuration(120)
            .setInterpolator(PathInterpolator(0.3f, 0f, 1f, 1f))
            .withEndAction {
                stepLabel.text = "STEP ${step + 1} OF 3"
                title.text = TITLES[step]
                headerText.translationX = d
                headerText.animate().alpha(1f).translationX(0f).setDuration(220)
                    .setInterpolator(ease).start()
            }.start()
    }

    private fun updateProgress(animate: Boolean) {
        progress.forEachIndexed { i, bar ->
            val target = if (i <= step) 1f else 0f
            if (animate) {
                bar.animate().scaleX(target).setDuration(STEP_MS).setInterpolator(ease).start()
            } else {
                bar.scaleX = target
            }
        }
    }

    // ─── Save ───────────────────────────────────────────────────────────────────

    private fun save() {
        if (closing) return
        val a = amount()
        if (a <= 0.0) { goTo(STEP_AMOUNT); return }

        val cat = selectedCategory
        val paymentLabel = PAYMENTS.first { it.first == selectedPayment }.second
        QuickAddWidgetProvider.executeSave(
            context = this,
            amount = a,
            catId = cat.id,
            catName = cat.name,
            catIcon = cat.icon,
            catColor = cat.color,
            paymentMethod = selectedPayment,
            paymentDisplay = paymentLabel,
            notes = noteInput.text.toString().trim()
        )
        rememberChoices(cat.id)

        Toast.makeText(this, "Added $currency${formatAmount(a)} · ${cat.name}", Toast.LENGTH_SHORT).show()
        close()
    }

    private fun readUses(): JSONObject = try {
        JSONObject(
            getSharedPreferences(QuickAddWidgetProvider.PREFS_NAME, MODE_PRIVATE)
                .getString(KEY_CATEGORY_USES, "{}") ?: "{}"
        )
    } catch (_: Exception) { JSONObject() }

    private fun rememberChoices(categoryId: Int) {
        val uses = readUses()
        val key = categoryId.toString()
        uses.put(key, uses.optInt(key, 0) + 1)
        getSharedPreferences(QuickAddWidgetProvider.PREFS_NAME, MODE_PRIVATE).edit()
            .putString(KEY_CATEGORY_USES, uses.toString())
            .putInt(KEY_LAST_CATEGORY, categoryId)
            .putString(KEY_LAST_PAYMENT, selectedPayment)
            .apply()
    }

    // ─── Helpers ────────────────────────────────────────────────────────────────

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun hideKeyboard() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.hideSoftInputFromWindow((currentFocus ?: amountInput).windowToken, 0)
    }
}
