import 'package:flutter/widgets.dart';

/// İçerik ekranlarına mobil uygulama kabuğunda olduklarını bildirir.
class AppShellScope extends InheritedWidget {
  const AppShellScope({super.key, required this.mobile, required super.child});

  final bool mobile;

  static bool isMobile(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellScope>()?.mobile ??
      false;

  @override
  bool updateShouldNotify(AppShellScope oldWidget) =>
      mobile != oldWidget.mobile;
}
