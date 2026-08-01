import 'package:intl/intl.dart';

String formatMoney(double amount, String currency) {
  final symbol = switch (currency) {
    'INR' => '₹',
    'USD' => '\$',
    'EUR' => '€',
    'GBP' => '£',
    _ => '$currency ',
  };
  final pattern = amount == amount.roundToDouble() ? '#,##0' : '#,##0.00';
  final formatted = NumberFormat(pattern).format(amount);
  return '$symbol$formatted';
}

String formatDay(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(date.year, date.month, date.day);
  final diff = that.difference(today).inDays;
  if (diff == 0) return 'today';
  if (diff == 1) return 'tomorrow';
  if (diff == -1) return 'yesterday';
  if (diff > 1 && diff < 7) return 'in $diff days';
  if (diff < -1 && diff > -7) return '${-diff} days ago';
  return DateFormat('d MMM').format(date);
}
