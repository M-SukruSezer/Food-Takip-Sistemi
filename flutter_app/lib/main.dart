import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/session.dart';
import 'core/theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // tr_TR tarih/saat bicimleri icin yerel veriler.
  initializeDateFormatting('tr_TR');
  await themePreference.restore();
  runApp(const FoodTakipApp());
  // Oturum geri yuklemesi arayuzu bloklamaz; router hazir olunca yonlendirir.
  session.restore();
}
