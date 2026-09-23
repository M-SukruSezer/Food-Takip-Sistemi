import 'package:intl/intl.dart';

final _dateTime = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');
final _date = DateFormat('dd.MM.yyyy', 'tr_TR');
final _money = NumberFormat('#,##0.00', 'tr_TR');
final _int = NumberFormat('#,##0', 'tr_TR');

String fmtDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final d = DateTime.tryParse(iso);
  if (d == null) return '-';
  return _dateTime.format(d.toLocal());
}

String fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '-';
  final d = DateTime.tryParse(iso);
  if (d == null) return '-';
  return _date.format(d.toLocal());
}

String fmtMoney(num? value) {
  if (value == null) return '-';
  return '${_money.format(value)} TL';
}

String fmtInt(num? value) => _int.format(value ?? 0);

String formatHours(num? hours) {
  if (hours == null) return '-';
  if (hours <= 0) return 'Süre doldu';
  final h = hours.floor();
  if (h < 24) return '$h saat';
  final d = h ~/ 24;
  final rest = h % 24;
  return rest > 0 ? '$d gün $rest saat' : '$d gün';
}

const roleLabels = <String, String>{
  'super_admin': 'Ana Yönetici',
  'store_manager': 'Mağaza Yöneticisi',
  'staff': 'Personel',
};

const statusLabels = <String, String>{
  'frozen': 'Donuk Depo',
  'thawing': 'Çözülme (+4°C)',
  'food_cabinet': 'Food Dolabı',
  'sold': 'Satıldı',
  'discarded': 'İmha Edildi',
};

/// Turkce duyarsiz arama: personel telefonda Turkce karakter yazmadan da
/// bulabilsin ("cikolata" -> "ÇİKOLATA", "pogaca" -> "POĞAÇA").
/// i harfinin ayrisimi olmadigi icin once elle cevrilir.
String normalizeSearch(String? value) {
  if (value == null) return '';
  var s = value.toLowerCase();
  const map = {
    'ı': 'i', 'İ': 'i', 'ş': 's', 'Ş': 's', 'ğ': 'g', 'Ğ': 'g',
    'ç': 'c', 'Ç': 'c', 'ö': 'o', 'Ö': 'o', 'ü': 'u', 'Ü': 'u',
  };
  map.forEach((k, v) => s = s.replaceAll(k, v));
  return s;
}

bool isUrgent(String? urgency) =>
    urgency == 'expired' || urgency == 'critical' || urgency == 'warning';
