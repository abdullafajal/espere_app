package com.example.espere_app

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText

class QuickNoteDialogActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.dialog_quick_note)

        val noteInput = findViewById<EditText>(R.id.dialog_note_input)
        val btnCancel = findViewById<Button>(R.id.dialog_btn_cancel)
        val btnSave = findViewById<Button>(R.id.dialog_btn_save)

        val prefs = getSharedPreferences(QuickAddWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
        val currentNote = prefs.getString(QuickAddWidgetProvider.KEY_NOTE, "")
        if (!currentNote.isNullOrEmpty()) {
            noteInput.setText(currentNote)
            noteInput.setSelection(currentNote.length)
        }

        noteInput.requestFocus()
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.showSoftInput(noteInput, InputMethodManager.SHOW_IMPLICIT)

        noteInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE || actionId == EditorInfo.IME_ACTION_GO) {
                saveNote(noteInput.text.toString().trim())
                true
            } else {
                false
            }
        }

        btnCancel.setOnClickListener {
            finish()
        }

        btnSave.setOnClickListener {
            saveNote(noteInput.text.toString().trim())
        }
    }

    private fun saveNote(note: String) {
        val prefs = getSharedPreferences(QuickAddWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(QuickAddWidgetProvider.KEY_NOTE, note).apply()
        QuickAddWidgetProvider.updateAllWidgets(this)
        finish()
    }
}
