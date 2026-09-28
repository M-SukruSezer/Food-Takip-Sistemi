sed -i 's/color: active ? t.primarySoft : null,//' flutter_app/lib/widgets/app_shell.dart
sed -i 's/Icon(icon, size: 24, color: color)/Icon(icon, size: 22, color: color)/' flutter_app/lib/widgets/app_shell.dart
sed -i 's/fontSize: 10.5,/fontSize: 11, fontFamily: "Inter",/' flutter_app/lib/widgets/app_shell.dart
sed -i 's/final color = active ? t.primary : t.muted;/final color = active ? const Color(0xFF005C55) : const Color(0xFF3E4947);/' flutter_app/lib/widgets/app_shell.dart
