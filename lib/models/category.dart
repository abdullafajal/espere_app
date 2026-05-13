/// Category model matching Django's Category model.
import 'dart:ui';

class CategoryModel {
  final int id;
  final String name;
  final String icon;
  final String color;
  final bool isSystem;

  CategoryModel({
    required this.id,
    required this.name,
    this.icon = 'category',
    this.color = '#C8E64A',
    this.isSystem = false,
  });

  /// Parse hex color string into Flutter Color
  Color get colorValue {
    final hex = color.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Other',
      icon: json['icon'] ?? 'category',
      color: json['color'] ?? '#C8E64A',
      isSystem: json['is_system'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'is_system': isSystem,
      };
}
