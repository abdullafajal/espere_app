import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/icon_mapper.dart';

class IconColorPicker extends StatefulWidget {
  final Function(String color, String icon) onSelected;
  final String initialColor;
  final String initialIcon;
  final String currentName;

  const IconColorPicker({
    super.key,
    required this.onSelected,
    this.initialColor = '#C8E64A',
    this.initialIcon = 'category',
    this.currentName = '',
  });

  @override
  State<IconColorPicker> createState() => _IconColorPickerState();
}

class _IconColorPickerState extends State<IconColorPicker> {
  late String _selectedColor;
  late String _selectedIcon;

  final List<(String, String)> _iconChoices = [
    ('category', 'Category'),
    ('groups', 'Friends'),
    ('home', 'Home'),
    ('favorite', 'Couple'),
    ('flight', 'Travel'),
    ('restaurant', 'Food'),
    ('celebration', 'Event'),
    ('sports_soccer', 'Sports'),
    ('work', 'Work'),
    ('school', 'School'),
    ('pets', 'Pets'),
    ('directions_car', 'Trip'),
    ('movie', 'Movies'),
  ];

  final List<String> _colorChoices = [
    '#C8E64A', '#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4',
    '#FFEAA7', '#DDA0DD', '#FF8C42', '#98D8C8', '#F7DC6F',
    '#BB8FCE', '#85C1E9', '#F0B27A', '#82E0AA', '#F1948A',
    '#AED6F1', '#D7BDE2', '#A3E4D7',
  ];

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _selectedIcon = widget.initialIcon;
  }

  Color _parseColor(String hex) {
    return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon picker
        const Text('Icon', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _iconChoices.map((choice) {
            final isSelected = _selectedIcon == choice.$1;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedIcon = choice.$1);
                widget.onSelected(_selectedColor, _selectedIcon);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: isSelected ? AppColors.dark : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Icon(
                  IconMapper.map(choice.$1),
                  size: 20,
                  color: isSelected ? AppColors.dark : AppColors.muted,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Color picker
        const Text('Color', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _colorChoices.map((hex) {
            final isSelected = _selectedColor == hex;
            final color = _parseColor(hex);
            return GestureDetector(
              onTap: () {
                setState(() => _selectedColor = hex);
                widget.onSelected(_selectedColor, _selectedIcon);
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.dark : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: isSelected ? const Icon(Icons.check, size: 18, color: AppColors.dark) : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Preview
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _parseColor(_selectedColor),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  IconMapper.map(_selectedIcon),
                  size: 22,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                widget.currentName.isEmpty ? 'Preview' : widget.currentName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
