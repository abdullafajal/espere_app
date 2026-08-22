void main() {
  var now = DateTime.now();
  var parsed = DateTime.tryParse("2026-08-15T20:00:00+05:30") ?? DateTime.now();
  var d = parsed.toLocal();
  print("now: ${now}");
  print("parsed: ${parsed}");
  print("d: ${d}");
  print("parsed.isUtc: ${parsed.isUtc}");
  print("d.year == now.year && d.month == now.month && d.day == now.day: ${d.year == now.year && d.month == now.month && d.day == now.day}");
}
