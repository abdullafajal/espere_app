/// "Export to CSV" sheet: pick a period, download the CSV and share it.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../utils/app_toast.dart';
import 'package:image_picker/image_picker.dart';

/// Opens the export sheet.
void showExportSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    builder: (ctx) => const ExportSheet(),
  );
}

class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key});

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  String _selectedPeriod = 'current_month';
  DateTime? _startDate;
  DateTime? _endDate;

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.accent,
              onPrimary: AppColors.dark,
              surface: AppColors.card,
              onSurface: AppColors.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (range != null) {
      setState(() {
        _selectedPeriod = 'custom';
        _startDate = range.start;
        _endDate = range.end;
      });
    }
  }

  bool _isExporting = false;

  Future<void> _export() async {
    setState(() => _isExporting = true);
    
    final result = await ApiService.downloadCSV(
      _selectedPeriod,
      startDate: _startDate?.toIso8601String().split('T')[0],
      endDate: _endDate?.toIso8601String().split('T')[0],
    );

    if (!mounted) return;
    setState(() => _isExporting = false);

    if (result.isSuccess && result.data != null) {
      try {
        String? finalPath;
        final fileName = 'espere_transactions_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
        
        if (Platform.isAndroid) {
          var status = await Permission.storage.request();
          
          // On Android 11+ (SDK 30+), storage permission often returns denied even if we can write to app-specific dirs.
          // To write to public /Download, we try MANAGE_EXTERNAL_STORAGE as a fallback.
          if (status.isDenied) {
            status = await Permission.manageExternalStorage.request();
          }

          if (status.isGranted) {
            final dirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
            if (dirs != null && dirs.isNotEmpty) {
              finalPath = '${dirs.first.path}/$fileName';
            } else {
              // Direct path attempt if dirs is empty
              finalPath = '/storage/emulated/0/Download/$fileName';
            }
          }
        }
        
        if (finalPath == null) {
          final directory = await getApplicationDocumentsDirectory();
          finalPath = '${directory.path}/$fileName';
        }

        final file = File(finalPath);
        await file.writeAsString(result.data!);
        
        if (mounted) {
          AppToast.success(context, 'Exported: $fileName');
        }
        
        // Also share it for convenience
        await Share.shareXFiles(
          [XFile(finalPath)],
          subject: 'Espere Transactions Export',
          text: 'Here is your exported transaction history from Espere.',
        );
        
        if (mounted) Navigator.pop(context);
      } catch (e) {
        debugPrint('Export Save Error: $e');
        if (mounted) AppToast.error(context, 'Failed to save file locally.');
      }
    } else {
      if (mounted) {
        AppToast.error(context, result.error ?? 'Export failed.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Export Transactions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select a period to download your CSV report.',
            style: TextStyle(fontSize: 14, color: AppColors.muted),
          ),
          const SizedBox(height: 16),

          _buildOption('current_month', 'Current Month', Icons.calendar_today),
          _buildOption('last_month', 'Last Month', Icons.history),
          _buildOption('3m', 'Last 3 Months', Icons.query_builder),
          _buildOption('6m', 'Last 6 Months', Icons.timelapse),
          _buildOption('all', 'All Time', Icons.all_inclusive),
          
          GestureDetector(
            onTap: _pickDateRange,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedPeriod == 'custom' ? AppColors.accent.withOpacity(0.1) : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _selectedPeriod == 'custom' ? AppColors.accent : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.date_range,
                    color: _selectedPeriod == 'custom' ? AppColors.accent : AppColors.muted,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom Date Range',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _selectedPeriod == 'custom' ? AppColors.accent : AppColors.text,
                          ),
                        ),
                        if (_startDate != null && _endDate != null)
                          Text(
                            '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                      ],
                    ),
                  ),
                  if (_selectedPeriod == 'custom')
                    Icon(Icons.check_circle, color: AppColors.accent, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isExporting ? null : _export,
              child: _isExporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: AppColors.dark,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Export CSV'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(String period, String label, IconData icon) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () => setState(() => _selectedPeriod = period),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent.withOpacity(0.1) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.accent : AppColors.muted,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.accent : AppColors.text,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check_circle, color: AppColors.accent, size: 20),
          ],
        ),
      ),
    );
  }
}
