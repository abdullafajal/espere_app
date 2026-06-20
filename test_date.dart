import 'package:intl/intl.dart';

void main() {
  final d = DateTime.parse('2026-06-20T21:40:00Z');
  print('Original: $d');
  print('Local: ${d.toLocal()}');
  print('Formatted: ${DateFormat('yyyy-MM').format(d)}');
}
