import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/tokens.dart';

/// QR kod gostericisi.
///
/// Zemin HER ZAMAN beyaz: koyu temada koyu zemin uzerinde QR okunamaz hale
/// geliyor. Modullerin rengi de sabit siyah.
class QrView extends StatelessWidget {
  const QrView({super.key, required this.data, this.size = 220, this.label});

  final String data;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: data,
            size: size,
            version: QrVersions.auto,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 8),
            Text(
              label!,
              textAlign: TextAlign.center,
              // Beyaz zemin uzerinde temadan bagimsiz koyu gri.
              style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
            ),
          ],
        ],
      ),
    );
  }
}
