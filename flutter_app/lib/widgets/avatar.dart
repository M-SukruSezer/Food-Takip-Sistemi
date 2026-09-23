import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../models/user.dart';

/// Profil fotosu yoksa ad-soyad bas harfleri gosterilir.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.user, this.size = 32});

  final AppUser? user;
  final double size;

  Uint8List? get _bytes {
    final raw = user?.avatar;
    if (raw == null || !raw.contains(',')) return null;
    try {
      return base64Decode(raw.split(',').last);
    } catch (_) {
      return null;
    }
  }

  String get _initials {
    final parts = (user?.fullName ?? '').trim().split(RegExp(r'\s+'));
    final letters = parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bytes = _bytes;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.primarySoft,
        border: Border.all(color: t.border),
      ),
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover)
          : Center(
              child: Text(
                _initials,
                style: TextStyle(
                  color: t.primary,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}
