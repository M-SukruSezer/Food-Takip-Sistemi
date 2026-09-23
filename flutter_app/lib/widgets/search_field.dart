import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// Urun arama kutusu. Oneri Satis Listesi ve Urunler ekrani ayni bicimi
/// paylasir: beyaz panel uzerinde beyaz kutu gorunmedigi icin alan gomulu
/// zeminle ayrisir, ikon marka renginde durur.
class ProductSearchField extends StatelessWidget {
  const ProductSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.filtering,
    this.hintText = 'Ürün ara...',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// Arama etkinken "Temizle" dugmesi cikar.
  final bool filtering;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: hintText,
              fillColor: t.bg,
              prefixIcon: Icon(Icons.search, color: t.primary),
            ),
          ),
        ),
        if (filtering) ...[
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onClear, child: const Text('Temizle')),
        ],
      ],
    );
  }
}
