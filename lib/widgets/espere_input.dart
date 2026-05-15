/// Reusable styled text input matching Django's form inputs.
///
/// Matches the Tailwind CSS:
///   border: 1.5px solid #EEEEEE
///   background: #FAFAFA
///   border-radius: 14px
///   focus: border-color #C8E64A with glow
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EspereInput extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool autofocus;
  final int maxLines;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final Widget? suffixIcon;
  final String? prefixText;
  final String? errorText;

  const EspereInput({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.autofocus = false,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
    this.suffixIcon,
    this.prefixText,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label — matches: text-sm font-medium text-[#1A1A1A] mb-1.5
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 6),
        // Input field
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          autofocus: autofocus,
          maxLines: maxLines,
          validator: validator,
          onChanged: onChanged,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.text,
          ),
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            errorStyle: const TextStyle(color: AppColors.accent, fontSize: 12),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
            suffixIcon: suffixIcon,
            prefixText: prefixText,
            prefixStyle: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
