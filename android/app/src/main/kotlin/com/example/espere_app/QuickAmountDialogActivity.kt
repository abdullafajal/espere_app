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
    private lateinit var step2CategorySpinner: Spinner
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
    private lateinit var step4BtnBack: View
    private lateinit var step4BtnSave: View

    // State
    private var amount: Double = 0.0
    private var categories: List<CategoryItem> = emptyList()
    private var selectedCategory: CategoryItem = CategoryItem(1, "Food", "restaurant", "#FF9800")
    private var selectedPaymentMethod = "upi"
    private var selectedPaymentDisplay = "UPI"
    private var isCategorySpinnerInitialized = false
    private var categoryAdapter: ArrayAdapter<CategoryItem>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.dialog_quick_amount)

        bindViews()
        setupStep1Amount()
        setupStep2Category()
        setupStep3Payment()
        setupStep4Notes()
        setupNavigation()

        updateStepIndicators(STEP_AMOUNT)

        // Focus keyboard automatically on Step 1
        step1AmountInput.requestFocus()
        step1AmountInput.post {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.showSoftInput(step1AmountInput, InputMethodManager.SHOW_IMPLICIT)
        }
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
        step2CategorySpinner = findViewById(R.id.step2_category_spinner)
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
            step1AmountInput.error = "Enter an amount > 0"
            step1AmountInput.requestFocus()
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

        val adapter = object : ArrayAdapter<CategoryItem>(
            this,
            R.layout.item_category_spinner,
            categories
        ) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                val view = convertView ?: LayoutInflater.from(context).inflate(R.layout.item_category_spinner, parent, false)
                val item = getItem(position) ?: return view
                val iconView = view.findViewById<ImageView>(R.id.spinner_cat_icon)
                val nameView = view.findViewById<TextView>(R.id.spinner_cat_name)

                iconView.setImageResource(QuickAddWidgetProvider.getCategoryDrawable(item.icon, item.name))
                val wallpaperColor = ContextCompat.getColor(context, R.color.quick_widget_primary)
                iconView.setColorFilter(wallpaperColor)
                nameView.text = item.name
                return view
            }

            override fun getDropDownView(position: Int, convertView: View?, parent: ViewGroup): View {
                val view = convertView ?: LayoutInflater.from(context).inflate(R.layout.item_category_dropdown, parent, false)
                val item = getItem(position) ?: return view
                val iconView = view.findViewById<ImageView>(R.id.dropdown_cat_icon)
                val nameView = view.findViewById<TextView>(R.id.dropdown_cat_name)
                val checkView = view.findViewById<ImageView>(R.id.dropdown_cat_check)

                iconView.setImageResource(QuickAddWidgetProvider.getCategoryDrawable(item.icon, item.name))
                val wallpaperColor = ContextCompat.getColor(context, R.color.quick_widget_primary)
                iconView.setColorFilter(wallpaperColor)
                nameView.text = item.name

                val isSelected = (item.id == selectedCategory.id)
                checkView.visibility = if (isSelected) View.VISIBLE else View.GONE
                if (isSelected) {
                    nameView.setTextColor(wallpaperColor)
                } else {
                    nameView.setTextColor(ContextCompat.getColor(context, R.color.quick_widget_text_primary))
                }
                return view
            }
        }

        categoryAdapter = adapter
        step2CategorySpinner.adapter = adapter

        step2CategorySpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (position in categories.indices) {
                    selectedCategory = categories[position]
                    adapter.notifyDataSetChanged()
                    // If user manually chose an item after initialization, auto advance with animation!
                    if (isCategorySpinnerInitialized) {
                        QuickAddWidgetProvider.triggerHaptic(this@QuickAmountDialogActivity)
                        goToStep(STEP_PAYMENT, isForward = true)
                    } else {
                        isCategorySpinnerInitialized = true
                    }
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        // Quick Top Category Pick Chips (1-tap selection)
        findViewById<TextView>(R.id.step2_chip_food).setOnClickListener {
            selectQuickCategory("Food", "restaurant", "#FF9800")
        }
        findViewById<TextView>(R.id.step2_chip_grocery).setOnClickListener {
            selectQuickCategory("Grocery", "shopping_bag", "#4CAF50")
        }
        findViewById<TextView>(R.id.step2_chip_transport).setOnClickListener {
            selectQuickCategory("Transport", "directions_car", "#2196F3")
        }
        findViewById<TextView>(R.id.step2_chip_bills).setOnClickListener {
            selectQuickCategory("Bills", "payments", "#FF5722")
        }

        step2BtnBack.setOnClickListener {
            goToStep(STEP_AMOUNT, isForward = false)
        }

        step2BtnNext.setOnClickListener {
            QuickAddWidgetProvider.triggerHaptic(this)
            goToStep(STEP_PAYMENT, isForward = true)
        }
    }

    private fun selectQuickCategory(name: String, icon: String, color: String) {
        val found = categories.find { it.name.equals(name, ignoreCase = true) }
        selectedCategory = found ?: CategoryItem(1, name, icon, color)
        val idx = categories.indexOfFirst { it.name.equals(name, ignoreCase = true) }
        if (idx >= 0) {
            isCategorySpinnerInitialized = false
            step2CategorySpinner.setSelection(idx)
            isCategorySpinnerInitialized = true
        }
        categoryAdapter?.notifyDataSetChanged()
        QuickAddWidgetProvider.triggerHaptic(this)
        goToStep(STEP_PAYMENT, isForward = true)
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

        val primaryColor = getColor(R.color.quick_widget_primary)
        val normalTextColor = getColor(R.color.quick_widget_text_primary)

        for (quad in items) {
            val (checkView, isSelected) = quad.checkPair
            if (isSelected) {
                quad.layout.setBackgroundResource(R.drawable.quick_widget_item_selected)
                quad.icon.setColorFilter(primaryColor)
                quad.text.setTextColor(primaryColor)
                checkView.visibility = View.VISIBLE
            } else {
                quad.layout.setBackgroundResource(R.drawable.quick_widget_item_normal)
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
        dialogStepBadge.text = "${step + 1} of 4"

        val activeRes = R.drawable.quick_widget_progress_active
        val inactiveRes = R.drawable.quick_widget_progress_inactive

        dotStep1.setBackgroundResource(if (step >= STEP_AMOUNT) activeRes else inactiveRes)
        dotStep2.setBackgroundResource(if (step >= STEP_CATEGORY) activeRes else inactiveRes)
        dotStep3.setBackgroundResource(if (step >= STEP_PAYMENT) activeRes else inactiveRes)
        dotStep4.setBackgroundResource(if (step >= STEP_NOTES) activeRes else inactiveRes)

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
