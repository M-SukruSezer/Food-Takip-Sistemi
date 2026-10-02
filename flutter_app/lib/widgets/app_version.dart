import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Uygulamanin kurulu surumu ve derleme numarasi, paketin kendisinden okunur
/// ("v1.0.0 (Build 12)"). Bir kez okunur, tum ekranlar ayni sonucu kullanir.
final Future<PackageInfo> appPackageInfo = PackageInfo.fromPlatform();

String formatAppVersion(PackageInfo p) =>
    'v${p.version} (Build ${p.buildNumber})';

class AppVersionText extends StatelessWidget {
  const AppVersionText({super.key, this.style, this.prefix = ''});

  final TextStyle? style;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: appPackageInfo,
      builder: (context, snap) => Text(
        snap.hasData ? '$prefix${formatAppVersion(snap.data!)}' : '',
        style: style,
      ),
    );
  }
}
