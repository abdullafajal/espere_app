/// Maps Django Material Symbol icon names to Flutter IconData.
///
/// Centralised so every widget uses the same mapping.
import 'package:flutter/material.dart';

class IconMapper {
  IconMapper._();

  static const Map<String, IconData> _map = {
    'restaurant': Icons.restaurant,
    'directions_car': Icons.directions_car,
    'home': Icons.home,
    'movie': Icons.movie,
    'shopping_bag': Icons.shopping_bag,
    'local_hospital': Icons.local_hospital,
    'school': Icons.school,
    'payments': Icons.payments,
    'work': Icons.work,
    'trending_up': Icons.trending_up,
    'redeem': Icons.redeem,
    'category': Icons.category,
    'receipt_long': Icons.receipt_long,
    'flight': Icons.flight,
    'checkroom': Icons.checkroom,
    'fitness_center': Icons.fitness_center,
    'pets': Icons.pets,
    'coffee': Icons.coffee,
    'savings': Icons.savings,
    'arrow_upward': Icons.arrow_upward,
    'arrow_downward': Icons.arrow_downward,
    'flag': Icons.flag,
    'devices': Icons.devices,
    'favorite': Icons.favorite,
    'emergency': Icons.emergency,
    'diamond': Icons.diamond,
    'volunteer_activism': Icons.volunteer_activism,
    // Payment Methods
    'cash': Icons.payments,
    'card': Icons.credit_card,
    'bank': Icons.account_balance,
    'upi': Icons.account_balance_wallet,
    'other': Icons.more_horiz,
    'medical_services': Icons.medical_services,
    'sports_esports': Icons.sports_esports,
    'sports_soccer': Icons.sports_soccer,
    'brush': Icons.brush,
    'music_note': Icons.music_note,
    'science': Icons.science,
    'build': Icons.build,
    'celebration': Icons.celebration,
    'fastfood': Icons.fastfood,
    'local_gas_station': Icons.local_gas_station,
    'electric_bolt': Icons.electric_bolt,
    'water_drop': Icons.water_drop,
    'family_restroom': Icons.family_restroom,
    'child_care': Icons.child_care,
    'groups': Icons.groups,
  };

  /// Returns the Flutter [IconData] for a Django icon name.
  static IconData map(String iconName) => _map[iconName] ?? Icons.category;
}
