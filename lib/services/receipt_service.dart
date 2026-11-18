/// Payment receipts the user hands to Espere on purpose:
///  - "Share" from a UPI app's success screen (text or image) → Espere
///  - "Scan receipt" in the Add Transaction form (pick a screenshot)
///
/// Images are read on device (ML Kit via Play services) and deleted right after. The result
/// always opens in the transaction form, so the user checks it before anything is saved.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/transaction_form_screen.dart';
import '../utils/app_toast.dart';
import 'auto_expense_service.dart';
import 'cache_service.dart';
import 'receipt_parser.dart';

/// Values the transaction form starts with.
class TransactionPrefill {
  final double? amount;
  final String type;
  final String? notes;
  final DateTime? date;
  final String paymentMethod;
  final int? categoryId;

  /// The receipt text that was read (shown on request when something was not found).
  final String? sourceText;

  const TransactionPrefill({
    this.amount,
    this.type = 'expense',
    this.notes,
    this.date,
    this.paymentMethod = 'upi',
    this.categoryId,
    this.sourceText,
  });
}

class ReceiptService {
  ReceiptService._();

  static const _channel = MethodChannel('com.example.espere_app/receipt');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static BuildContext? _homeContext;
  static bool _busy = false;

  /// Called once at app start.
  static void init() {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare') await _handlePending();
    });
  }

  /// The signed-in home screen is up: shares can now open the form. Also picks up a share
  /// that started the app (cold start).
  static void attachHome(BuildContext context) {
    _homeContext = context;
    _handlePending();
  }

  static void detachHome(BuildContext context) {
    if (identical(_homeContext, context)) _homeContext = null;
  }

  // ─── Native calls ─────────────────────────────────────────────────────────

  /// Text on the image at [path] (on-device OCR), or null if it could not be read.
  static Future<String?> recognizeText(String path) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('recognizeText', {'path': path});
    } on PlatformException catch (e) {
      debugPrint('[Receipt] OCR failed: ${e.code}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<Map<dynamic, dynamic>?> _takePendingShare() async {
    try {
      return await _channel.invokeMethod<Map<dynamic, dynamic>>('takePendingShare');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  // ─── Shared receipt → form ────────────────────────────────────────────────

  static Future<void> _handlePending() async {
    final context = _homeContext;
    if (context == null || !context.mounted || _busy) return; // kept until home is ready
    _busy = true;
    try {
      final share = await _takePendingShare();
      if (share == null || !context.mounted) return;

      final imagePath = share['imagePath'] as String?;
      final parts = <String>[
        if ((share['subject'] as String?)?.trim().isNotEmpty ?? false) share['subject'] as String,
        if ((share['text'] as String?)?.trim().isNotEmpty ?? false) share['text'] as String,
      ];
      if (imagePath != null) {
        final ocr = await recognizeText(imagePath);
        _deleteQuietly(imagePath);
        if (ocr != null && ocr.trim().isNotEmpty) parts.add(ocr);
      }
      if (!context.mounted) return;

      if (parts.isEmpty) {
        AppToast.error(context, 'Could not read this receipt. Please add it manually.');
        TransactionFormScreen.show(context, prefill: const TransactionPrefill());
        return;
      }
      await openForm(context, parts.join('\n'));
    } finally {
      _busy = false;
    }
  }

  /// Parses [text] and opens the Add Transaction form with what was found.
  static Future<void> openForm(BuildContext context, String text) async {
    final data = ReceiptParser.parse(text);
    if (!context.mounted) return;

    if (data.notCompleted) {
      AppToast.error(context, 'This payment failed or is still pending, so nothing was added.');
      return;
    }

    if (data.amount != null && await _probablyAdded(data)) {
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already added?'),
          content: Text(
              'A ${data.type} of ${_fmt(data.amount!)} around this time is already in your '
              'transactions. Add it again?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add anyway')),
          ],
        ),
      );
      if (go != true || !context.mounted) return;
    }

    final prefill = await prefillFrom(data, sourceText: text);
    if (!context.mounted) return;
    if (data.amount == null) {
      AppToast.info(context, 'Could not find the amount. Please enter it.');
    }
    TransactionFormScreen.show(context, prefill: prefill);
  }

  /// Form values for a parsed receipt (category from the user's past choice / payee words).
  static Future<TransactionPrefill> prefillFrom(ReceiptData data, {String? sourceText}) async {
    final categoryId = await AutoExpenseService.suggestCategory(payee: data.payee, type: data.type);
    return TransactionPrefill(
      amount: data.amount,
      type: data.type,
      notes: data.payee,
      date: data.time,
      paymentMethod: 'upi',
      categoryId: categoryId,
      sourceText: sourceText,
    );
  }

  /// Same amount and type within 20 minutes of the receipt time already in the cache.
  static Future<bool> _probablyAdded(ReceiptData data) async {
    final cached = await CacheService.getCachedTransactions();
    final list = List<Map<String, dynamic>>.from(cached?['transactions'] ?? const []);
    final when = data.time ?? DateTime.now();
    for (final t in list) {
      if (t['type'] != data.type) continue;
      final amount = double.tryParse(t['amount']?.toString() ?? '');
      if (amount == null || (amount - data.amount!).abs() > 0.009) continue;
      final date = DateTime.tryParse(t['date']?.toString() ?? '')?.toLocal();
      if (date == null) continue;
      if (date.difference(when).inMinutes.abs() <= 20) return true;
    }
    return false;
  }

  static String _fmt(double v) =>
      '₹${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

  static void _deleteQuietly(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }
}
