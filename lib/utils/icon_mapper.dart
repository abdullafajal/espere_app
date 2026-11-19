/// Maps Django Material Symbol icon names to Flutter IconData.
///
/// Centralised so every widget uses the same mapping.
import 'package:flutter/material.dart';

class IconMapper {
  IconMapper._();

  static const Map<String, IconData> _map = {
    'restaurant': Icons.restaurant_rounded,
    'directions_car': Icons.directions_car_rounded,
    'home': Icons.home_rounded,
    'movie': Icons.movie_rounded,
    'shopping_bag': Icons.shopping_bag_rounded,
    'local_hospital': Icons.local_hospital_rounded,
    'school': Icons.school_rounded,
    'payments': Icons.payments_rounded,
    'work': Icons.work_rounded,
    'trending_up': Icons.trending_up_rounded,
    'redeem': Icons.redeem_rounded,
    'category': Icons.category_rounded,
    'receipt_long': Icons.receipt_long_rounded,
    'flight': Icons.flight_rounded,
    'checkroom': Icons.checkroom_rounded,
    'fitness_center': Icons.fitness_center_rounded,
    'pets': Icons.pets_rounded,
    'coffee': Icons.coffee_rounded,
    'savings': Icons.savings_rounded,
    'arrow_upward': Icons.arrow_upward_rounded,
    'arrow_downward': Icons.arrow_downward_rounded,
    'flag': Icons.flag_rounded,
    'devices': Icons.devices_rounded,
    'favorite': Icons.favorite_rounded,
    'emergency': Icons.emergency_rounded,
    'diamond': Icons.diamond_rounded,
    'volunteer_activism': Icons.volunteer_activism_rounded,
    // Payment Methods
    'cash': Icons.payments_rounded,
    'card': Icons.credit_card_rounded,
    'bank': Icons.account_balance_rounded,
    'upi': Icons.account_balance_wallet_rounded,
    'other': Icons.more_horiz_rounded,
    'medical_services': Icons.medical_services_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'sports_soccer': Icons.sports_soccer_rounded,
    'brush': Icons.brush_rounded,
    'music_note': Icons.music_note_rounded,
    'science': Icons.science_rounded,
    'build': Icons.build_rounded,
    'celebration': Icons.celebration_rounded,
    'fastfood': Icons.fastfood_rounded,
    'local_gas_station': Icons.local_gas_station_rounded,
    'electric_bolt': Icons.electric_bolt_rounded,
    'water_drop': Icons.water_drop_rounded,
    'family_restroom': Icons.family_restroom_rounded,
    'child_care': Icons.child_care_rounded,
    'groups': Icons.groups_rounded,
    'shopping_cart': Icons.shopping_cart_rounded,
    'directions_bus': Icons.directions_bus_rounded,
    'smartphone': Icons.smartphone_rounded,
    'subscriptions': Icons.subscriptions_rounded,
    'spa': Icons.spa_rounded,
    'account_balance': Icons.account_balance_rounded,
    'swap_horiz': Icons.swap_horiz_rounded,
    'local_cafe': Icons.local_cafe_rounded,
    'storefront': Icons.storefront_rounded,
    'laptop_mac': Icons.laptop_mac_rounded,
    'sell': Icons.sell_rounded,
    'percent': Icons.percent_rounded,
    'undo': Icons.undo_rounded,
    'more_horiz': Icons.more_horiz_rounded,
  };

  /// Returns the Flutter [IconData] for a Django icon name.
  static IconData map(String iconName) => _map[iconName] ?? Icons.category_rounded;
}
