import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/icon_mapper.dart';

/// Icon picker for groups. Groups have no colour any more (the app uses only ink, white
/// and lime), so only the icon is chosen; the colour passed to [onSelected] is whatever the
/// group already had, so the server data stays untouched.
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
  late String _selectedIcon;

  static const List<(String, String)> _iconChoices = [
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
    ('category', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.initialIcon;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Icon', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.82,
          children: _iconChoices.map((choice) {
            final isSelected = _selectedIcon == choice.$1;
            return Semantics(
              button: true,
              selected: isSelected,
              label: choice.$2,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedIcon = choice.$1);
                  widget.onSelected(widget.initialColor, _selectedIcon);
                },
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.accent : AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: isSelected ? AppColors.dark : Colors.transparent, width: 2),
                      ),
                      child: Icon(IconMapper.map(choice.$1), size: 22, color: AppColors.dark),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      choice.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
