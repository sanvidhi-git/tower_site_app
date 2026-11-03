import 'package:intl/intl.dart';

final _date = DateFormat('d MMM yyyy');
final _dateTime = DateFormat('d MMM, h:mm a');
final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

String fmtDate(dynamic v) {
  if (v == null || v == '') return '-';
  final d = v is DateTime ? v : DateTime.tryParse(v.toString());
  return d == null ? v.toString() : _date.format(d);
}

String fmtDateTime(DateTime d) => _dateTime.format(d);

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String money(num? v) => _money.format(v ?? 0);

/// 12.0 -> "12", 12.5 -> "12.5"
String qty(dynamic v) {
  final n = v is num ? v : num.tryParse('$v') ?? 0;
  return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

double toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
