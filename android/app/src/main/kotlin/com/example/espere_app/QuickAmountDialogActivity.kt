package com.example.espere_app

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.*
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.Editable
import android.text.TextWatcher
import androidx.core.content.ContextCompat
import java.util.Locale

class QuickAmountDialogActivity : Activity() {

    companion object {
        const val STEP_AMOUNT = 0
        const val STEP_CATEGORY = 1
        const val STEP_PAYMENT = 2
        const val STEP_NOTES = 3
    }

    private var currentStep = STEP_AMOUNT

    // Header & Navigation
    private lateinit var btnHeaderBack: ImageView
    private lateinit var dialogTitle: TextView
    private lateinit var dialogStepBadge: TextView
    private lateinit var btnDialogClose: ImageView

    // Progress Dots
    private lateinit var dotStep1: FrameLayout
    private lateinit var dotStep2: FrameLayout
    private lateinit var dotStep3: FrameLayout
    private lateinit var dotStep4: FrameLayout

    // ViewFlipper
    private lateinit var viewFlipper: ViewFlipper

    // Step 1: Amount
    private lateinit var step1CurrencySymbol: TextView
    private lateinit var step1AmountInput: EditText
    private lateinit var step1BtnNext: View

    // Step 2: Category
    private lateinit var step2AmountSubtext: TextView
    private lateinit var step2CategoryGrid: GridLayout
    private lateinit var step2BtnBack: View
    private lateinit var step2BtnNext: View

    // Step 3: Payment
    private lateinit var step3SummarySubtext: TextView
    private lateinit var step3PayCash: LinearLayout
    private lateinit var step3PayUpi: LinearLayout
    private lateinit var step3PayCard: LinearLayout
    private lateinit var step3PayBank: LinearLayout
    private lateinit var step3PayCashIcon: ImageView
    private lateinit var step3PayUpiIcon: ImageView
    private lateinit var step3PayCardIcon: ImageView
    private lateinit var step3PayBankIcon: ImageView
    private lateinit var step3PayCashText: TextView
    private lateinit var step3PayUpiText: TextView
    private lateinit var step3PayCardText: TextView
    private lateinit var step3PayBankText: TextView
    private lateinit var step3PayCashCheck: ImageView
    private lateinit var step3PayUpiCheck: ImageView
    private lateinit var step3PayCardCheck: ImageView
    private lateinit var step3PayBankCheck: ImageView
    private lateinit var step3BtnBack: View
    private lateinit var step3BtnNext: View

    // Step 4: Notes
    private lateinit var step4SummaryAmount: TextView
    private lateinit var step4SummaryDetails: TextView
    private lateinit var step4NoteInput: EditText
    private lateinit var sheetScroll: ScrollView
    private lateinit var step4BtnBack: View
    private lateinit var step4BtnSave: View

    // Wallpaper palette (Android 12+), null = use the resource colours
    private var palette: WidgetPalette? = null

    // State
    private var amount: Double = 0.0
    private var categories: List<CategoryItem> = emptyList()
    private var selectedCategory: CategoryItem = CategoryItem(1, "Food", "restaurant", "#FF9800")
    private var selectedPaymentMethod = "upi"
    private var selectedPaymentDisplay = "UPI"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.dialog_quick_amount)
        applyWindowStyle()
        palette = WidgetPalettes.get(this)

        bindViews()
        setupStep1Amount()
        setupStep2Category()
        setupStep3Payment()
        setupStep4Notes()
        setupNavigation()

        applyPalette(findViewById(android.R.id.content))
        dialogStepBadge.setTextColor(ink())
        updateStepIndicators(STEP_AMOUNT)

        // Focus keyboard automatically on Step 1
        step1AmountInput.requestFocus()
        step1AmountInput.post {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.showSoftInput(step1AmountInput, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    // Bottom sheet: full width at the bottom, soft dim + blur (Android 12+) behind.
    private fun applyWindowStyle() {
        window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        window.setGravity(android.view.Gravity.BOTTOM)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.setDimAmount(0.3f)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_BLUR_BEHIND)
            window.attributes = window.attributes.also { it.blurBehindRadius = 28 }
        }
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        applyWindowStyle()
    }

    /** Quick left-right shake used to say "this needs a value". */
    private fun shake(view: View) {
        android.animation.ObjectAnimator.ofFloat(
            view, "translationX", 0f, 18f, -18f, 12f, -12f, 6f, 0f
        ).setDuration(320).start()
    }

    private fun ink(): Int = palette?.block ?: ContextCompat.getColor(this, R.color.widget_accent_ink)

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    /** Replace the fill of a shape background (keeps corners and stroke). */
    private fun fill(view: View, color: Int) {
        (view.background?.mutate() as? GradientDrawable)?.setColor(color)
    }

    private fun applyPalette(root: View) {
        val p = palette ?: return
        if (root.tag is String) {
            when (root.tag as String) {
                "panel" -> fill(root, p.sheet)
                "block", "btn" -> fill(root, p.block)
                "accent" -> fill(root, p.accent)
                "pill" -> fill(root, p.pill)
            }
        }
        if (root is ViewGroup) for (i in 0 until root.childCount) applyPalette(root.getChildAt(i))
    }

    /** Tile / option background after a selection change (keeps the wallpaper fill). */
    private fun styleOption(view: View, selected: Boolean) {
        view.setBackgroundResource(
            if (selected) R.drawable.quick_widget_item_selected else R.drawable.quick_widget_item_normal
        )
        val p = palette ?: return
        fill(view, p.pill)
        if (selected) (view.background as? GradientDrawable)?.setStroke(dp(2), p.block)
    }

    private fun bindViews() {
        btnHeaderBack = findViewById(R.id.btn_header_back)
        dialogTitle = findViewById(R.id.dialog_title)
        dialogStepBadge = findViewById(R.id.dialog_step_badge)
        btnDialogClose = findViewById(R.id.btn_dialog_close)

        dotStep1 = findViewById(R.id.dot_step_1)
        dotStep2 = findViewById(R.id.dot_step_2)
        dotStep3 = findViewById(R.id.dot_step_3)
        dotStep4 = findViewById(R.id.dot_step_4)

        viewFlipper = findViewById(R.id.view_flipper)

        // Step 1
        step1CurrencySymbol = findViewById(R.id.step1_currency_symbol)
        step1AmountInput = findViewById(R.id.step1_amount_input)
        step1BtnNext = findViewById(R.id.step1_btn_next)

        // Step 2
        step2AmountSubtext = findViewById(R.id.step2_amount_subtext)
        step2CategoryGrid = findViewById(R.id.step2_category_grid)
        step2BtnBack = findViewById(R.id.step2_btn_back)
        step2BtnNext = findViewById(R.id.step2_btn_next)

        // Step 3
        step3SummarySubtext = findViewById(R.id.step3_summary_subtext)
        step3PayCash = findViewById(R.id.step3_pay_cash)
        step3PayUpi = findViewById(R.id.step3_pay_upi)
        step3PayCard = findViewById(R.id.step3_pay_card)
        step3PayBank = findViewById(R.id.step3_pay_bank)
        step3PayCashIcon = findViewById(R.id.step3_pay_cash_icon)
        step3PayUpiIcon = findViewById(R.id.step3_pay_upi_icon)
        step3PayCardIcon = findViewById(R.id.step3_pay_card_icon)
        step3PayBankIcon = findViewById(R.id.step3_pay_bank_icon)
        step3PayCashText = findViewById(R.id.step3_pay_cash_text)
        step3PayUpiText = findViewById(R.id.step3_pay_upi_text)
        step3PayCardText = findViewById(R.id.step3_pay_card_text)
        step3PayBankText = findViewById(R.id.step3_pay_bank_text)
        step3PayCashCheck = findViewById(R.id.step3_pay_cash_check)
        step3PayUpiCheck = findViewById(R.id.step3_pay_upi_check)
        step3PayCardCheck = findViewById(R.id.step3_pay_card_check)
        step3PayBankCheck = findViewById(R.id.step3_pay_bank_check)
        step3BtnBack = findViewById(R.id.step3_btn_back)
        step3BtnNext = findViewById(R.id.step3_btn_next)

        // Step 4
        step4SummaryAmount = findViewById(R.id.step4_summary_amount)
        step4SummaryDetails = findViewById(R.id.step4_summary_details)
        step4NoteInput = findViewById(R.id.step4_note_input)
        sheetScroll = findViewById(R.id.sheet_scroll)
        step4BtnBack = findViewById(R.id.step4_btn_back)
        step4BtnSave = findViewById(R.id.step4_btn_save)
    }

    private fun setupStep1Amount() {
        val currency = QuickAddWidgetProvider.getCurrencySymbol(this)
        step1CurrencySymbol.text = currency

        val prefill = intent.getDoubleExtra(QuickAddWidgetProvider.EXTRA_PREFILL_AMOUNT, 0.0)
        if (prefill > 0.0) {
            val formatted = if (prefill % 1.0 == 0.0) prefill.toLong().toString() else String.format(Locale.US, "%.2f", prefill)
            step1AmountInput.setText(formatted)
            step1AmountInput.selectAll()
        }

        setupAmountChip(findViewById(R.id.step1_chip_100), 100.0)
        setupAmountChip(findViewById(R.id.step1_chip_500), 500.0)
        setupAmountChip(findViewById(R.id.step1_chip_1000), 1000.0)
        setupAmountChip(findViewById(R.id.step1_chip_2000), 2000.0)

        step1AmountInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE || actionId == EditorInfo.IME_ACTION_NEXT || actionId == EditorInfo.IME_ACTION_GO) {
                confirmAmountAndAdvance()
                true
            } else {
                false
            }
        }

        step1BtnNext.setOnClickListener {
            confirmAmountAndAdvance()
        }
    }

    private fun setupAmountChip(chip: TextView, add: Double) {
        chip.setOnClickListener {
            QuickAddWidgetProvider.triggerHaptic(this)
            val cur = step1AmountInput.text.toString().toDoubleOrNull() ?: 0.0
            val total = cur + add
            val formatted = if (total % 1.0 == 0.0) total.toLong().toString() else String.format(Locale.US, "%.2f", total)
            step1AmountInput.setText(formatted)
            step1AmountInput.setSelection(formatted.length)
        }
    }

    private fun confirmAmountAndAdvance() {
        val amountStr = step1AmountInput.text.toString().trim()
        val parsed = amountStr.toDoubleOrNull() ?: 0.0
        if (parsed <= 0.0) {
            step1AmountInput.requestFocus()
            shake(step1AmountInput)
            QuickAddWidgetProvider.triggerHaptic(this)
            return
        }

        amount = parsed
        hideKeyboard()
        QuickAddWidgetProvider.triggerHaptic(this)
        goToStep(STEP_CATEGORY, isForward = true)
    }

    private fun setupStep2Category() {
        categories = QuickAddWidgetProvider.getCategories(this)
        if (categories.isNotEmpty()) {
            selectedCategory = categories[0]
        }

        // Category tiles (icon + name). Tapping one picks it and moves on.
        val inflater = LayoutInflater.from(this)
        categories.forEach { cat ->
            val tile = inflater.inflate(R.layout.item_category_tile, step2CategoryGrid, false)
            tile.findViewById<ImageView>(R.id.tile_icon)
                .setImageResource(QuickAddWidgetProvider.getCategoryDrawable(cat.icon, cat.name))
            tile.findViewById<TextView>(R.id.tile_name).text = cat.name
            tile.tag = cat.id
            val lp = GridLayout.LayoutParams(
                GridLayout.spec(GridLayout.UNDEFINED, 1f),
                GridLayout.spec(GridLayout.UNDEFINED, 1f)
            ).apply {
                width = 0
                setMargins(4, 4, 4, 4)
            }
            tile.layoutParams = lp
            tile.setOnClickListener {
                selectedCategory = cat
                refreshCategoryTiles()
                QuickAddWidgetProvider.triggerHaptic(this)
                hideKeyboard()
                goToStep(STEP_PAYMENT, isForward = true)
            }
            step2CategoryGrid.addView(tile)
        }
        refreshCategoryTiles()

        // More categories than fit: show a search box and tell the user the list scrolls.
        if (categories.size > 8) {
            val hint = findViewById<TextView>(R.id.step2_more_hint)
            val empty = findViewById<TextView>(R.id.step2_empty)
            val box = findViewById<View>(R.id.step2_search_box)
            val input = findViewById<EditText>(R.id.step2_search_input)
            val clear = findViewById<View>(R.id.step2_search_clear)
            box.visibility = View.VISIBLE
            hint.text = "${categories.size} categories · scroll for more"
            hint.visibility = View.VISIBLE

            input.addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, st: Int, c: Int, a: Int) {}
                override fun onTextChanged(s: CharSequence?, st: Int, b: Int, c: Int) {}
                override fun afterTextChanged(s: Editable?) {
                    val q = s?.toString()?.trim()?.lowercase(Locale.ROOT).orEmpty()
                    var shown = 0
                    for (i in 0 until step2CategoryGrid.childCount) {
                        val tile = step2CategoryGrid.getChildAt(i)
                        val name = tile.findViewById<TextView>(R.id.tile_name).text.toString()
                        val match = q.isEmpty() || name.lowercase(Locale.ROOT).contains(q)
                        tile.visibility = if (match) View.VISIBLE else View.GONE
                        if (match) shown++
                    }
                    clear.visibility = if (q.isEmpty()) View.GONE else View.VISIBLE
                    hint.visibility = if (q.isEmpty()) View.VISIBLE else View.GONE
                    empty.visibility = if (shown == 0) View.VISIBLE else View.GONE
                }
            })
            clear.setOnClickListener {
                input.setText("")
                QuickAddWidgetProvider.triggerHaptic(this)
            }
            input.setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_DONE) { hideKeyboard(); true } else false
            }
        }

        step2BtnBack.setOnClickListener {
            goToStep(STEP_AMOUNT, isForward = false)
        }

        step2BtnNext.setOnClickListener {
            QuickAddWidgetProvider.triggerHaptic(this)
            goToStep(STEP_PAYMENT, isForward = true)
        }
    }

    private fun refreshCategoryTiles() {
        val ink = ink()
        val normal = ContextCompat.getColor(this, R.color.widget_text_1)
        for (i in 0 until step2CategoryGrid.childCount) {
            val tile = step2CategoryGrid.getChildAt(i)
            val selected = tile.tag == selectedCategory.id
            styleOption(tile, selected)
            val color = if (selected) ink else normal
            tile.findViewById<ImageView>(R.id.tile_icon).setColorFilter(color)
            tile.findViewById<TextView>(R.id.tile_name).setTextColor(color)
        }
    }

    private fun setupStep3Payment() {
        selectPayment("upi", "UPI", shouldAdvance = false)

        step3PayCash.setOnClickListener { selectPayment("cash", "Cash", shouldAdvance = true) }
        step3PayUpi.setOnClickListener { selectPayment("upi", "UPI", shouldAdvance = true) }
        step3PayCard.setOnClickListener { selectPayment("card", "Card", shouldAdvance = true) }
        step3PayBank.setOnClickListener { selectPayment("bank", "Bank", shouldAdvance = true) }

        step3BtnBack.setOnClickListener {
            goToStep(STEP_CATEGORY, isForward = false)
        }

        step3BtnNext.setOnClickListener {
            QuickAddWidgetProvider.triggerHaptic(this)
            goToStep(STEP_NOTES, isForward = true)
        }
    }

    private fun selectPayment(method: String, display: String, shouldAdvance: Boolean) {
        selectedPaymentMethod = method
        selectedPaymentDisplay = display
        QuickAddWidgetProvider.triggerHaptic(this)

        val items = listOf(
            Quadruple(step3PayCash, step3PayCashIcon, step3PayCashText, step3PayCashCheck to ("cash" == method)),
            Quadruple(step3PayUpi, step3PayUpiIcon, step3PayUpiText, step3PayUpiCheck to ("upi" == method)),
            Quadruple(step3PayCard, step3PayCardIcon, step3PayCardText, step3PayCardCheck to ("card" == method)),
            Quadruple(step3PayBank, step3PayBankIcon, step3PayBankText, step3PayBankCheck to ("bank" == method))
        )

        val primaryColor = ink()
        val normalTextColor = getColor(R.color.widget_text_1)

        for (quad in items) {
            val (checkView, isSelected) = quad.checkPair
            if (isSelected) {
                styleOption(quad.layout, true)
                quad.icon.setColorFilter(primaryColor)
                quad.text.setTextColor(primaryColor)
                checkView.visibility = View.VISIBLE
            } else {
                styleOption(quad.layout, false)
                quad.icon.setColorFilter(normalTextColor)
                quad.text.setTextColor(normalTextColor)
                checkView.visibility = View.GONE
            }
        }

        if (shouldAdvance) {
            step3PayCash.postDelayed({
                goToStep(STEP_NOTES, isForward = true)
            }, 120)
        }
    }

    private data class Quadruple(
        val layout: LinearLayout,
        val icon: ImageView,
        val text: TextView,
        val checkPair: Pair<ImageView, Boolean>
    )

    private fun setupStep4Notes() {
        // The sheet sits above the keyboard (adjustResize); also scroll the note
        // field into view once the keyboard is up, so it is never hidden.
        step4NoteInput.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) sheetScroll.postDelayed({ sheetScroll.fullScroll(View.FOCUS_DOWN) }, 300)
        }

        setupNoteChip(findViewById(R.id.step4_chip_lunch), "Lunch")
        setupNoteChip(findViewById(R.id.step4_chip_coffee), "Coffee")
        setupNoteChip(findViewById(R.id.step4_chip_grocery), "Grocery")
        setupNoteChip(findViewById(R.id.step4_chip_bills), "Bills")

        step4BtnBack.setOnClickListener {
            goToStep(STEP_PAYMENT, isForward = false)
        }

        step4BtnSave.setOnClickListener {
            saveExpense()
        }
    }

    private fun setupNoteChip(chip: TextView, text: String) {
        chip.setOnClickListener {
            QuickAddWidgetProvider.triggerHaptic(this)
            step4NoteInput.setText(text)
            step4NoteInput.setSelection(text.length)
        }
    }

    private fun setupNavigation() {
        btnDialogClose.setOnClickListener {
            finish()
        }

        btnHeaderBack.setOnClickListener {
            if (currentStep > STEP_AMOUNT) {
                goToStep(currentStep - 1, isForward = false)
            } else {
                finish()
            }
        }
    }

    private fun goToStep(step: Int, isForward: Boolean) {
        if (step == currentStep) return

        if (isForward) {
            viewFlipper.setInAnimation(this, R.anim.slide_in_right)
            viewFlipper.setOutAnimation(this, R.anim.slide_out_left)
        } else {
            viewFlipper.setInAnimation(this, R.anim.slide_in_left)
            viewFlipper.setOutAnimation(this, R.anim.slide_out_right)
        }

        currentStep = step
        viewFlipper.displayedChild = step
        updateStepIndicators(step)
    }

    private fun updateStepIndicators(step: Int) {
        val currency = QuickAddWidgetProvider.getCurrencySymbol(this)
        val formattedAmount = if (amount % 1.0 == 0.0) amount.toLong().toString() else String.format(Locale.US, "%.2f", amount)

        btnHeaderBack.visibility = if (step > STEP_AMOUNT) View.VISIBLE else View.GONE
        dialogStepBadge.text = "STEP ${step + 1} OF 4"

        val activeRes = R.drawable.quick_widget_progress_active
        val inactiveRes = R.drawable.quick_widget_progress_inactive

        dotStep1.setBackgroundResource(if (step >= STEP_AMOUNT) activeRes else inactiveRes)
        dotStep2.setBackgroundResource(if (step >= STEP_CATEGORY) activeRes else inactiveRes)
        dotStep3.setBackgroundResource(if (step >= STEP_PAYMENT) activeRes else inactiveRes)
        dotStep4.setBackgroundResource(if (step >= STEP_NOTES) activeRes else inactiveRes)
        palette?.let { p ->
            listOf(dotStep1, dotStep2, dotStep3, dotStep4).forEachIndexed { i, dot ->
                if (step >= i) fill(dot, p.block)
            }
        }

        when (step) {
            STEP_AMOUNT -> {
                dialogTitle.text = "Enter Amount"
            }
            STEP_CATEGORY -> {
                dialogTitle.text = "Select Category"
                step2AmountSubtext.text = "Amount: $currency$formattedAmount"
            }
            STEP_PAYMENT -> {
                dialogTitle.text = "Payment Method"
                step3SummarySubtext.text = "$currency$formattedAmount • ${selectedCategory.name}"
            }
            STEP_NOTES -> {
                dialogTitle.text = "Review & Save"
                step4SummaryAmount.text = "$currency$formattedAmount"
                step4SummaryDetails.text = "• ${selectedCategory.name} • $selectedPaymentDisplay"
            }
        }
    }

    private fun saveExpense() {
        if (amount <= 0.0) {
            goToStep(STEP_AMOUNT, isForward = false)
            return
        }

        val notes = step4NoteInput.text.toString().trim()
        val currency = QuickAddWidgetProvider.getCurrencySymbol(this)
        val formattedAmount = String.format(Locale.US, "%.2f", amount)

        QuickAddWidgetProvider.executeSave(
            context = this,
            amount = amount,
            catId = selectedCategory.id,
            catName = selectedCategory.name,
            catIcon = selectedCategory.icon,
            catColor = selectedCategory.color,
            paymentMethod = selectedPaymentMethod,
            paymentDisplay = selectedPaymentDisplay,
            notes = notes
        )

        Toast.makeText(this, "Added $currency$formattedAmount to ${selectedCategory.name}", Toast.LENGTH_SHORT).show()
        finish()
    }

    private fun hideKeyboard() {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        val view = currentFocus ?: step1AmountInput
        imm?.hideSoftInputFromWindow(view.windowToken, 0)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (currentStep > STEP_AMOUNT) {
            goToStep(currentStep - 1, isForward = false)
        } else {
            super.onBackPressed()
        }
    }
}
