import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/image_pick.dart';
import '../core/login_branding.dart';
import '../core/notify.dart';
import '../core/tokens.dart';
import 'login_art.dart';
import 'panels.dart';

class LoginBrandingEditor extends StatefulWidget {
  const LoginBrandingEditor({super.key});
  @override
  State<LoginBrandingEditor> createState() => _LoginBrandingEditorState();
}

class _LoginBrandingEditorState extends State<LoginBrandingEditor> {
  bool _busy = false, _changed = false;
  String? _draft, _error;
  @override
  void initState() {
    super.initState();
    loadLoginArtwork().catchError((Object e) {
      if (mounted) {
        setState(() => _error = 'Görsel ayarı yüklenemedi. ${errorMessage(e)}');
      }
    });
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await pickImageBytes();
      if (bytes == null) return;
      final image = await compute(encodeLoginArtwork, bytes);
      if (mounted) {
        setState(() {
          _draft = image;
          _changed = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException ? e.message : errorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await saveLoginArtwork(_draft);
      if (mounted) setState(() => _changed = false);
      toastSaved('Giriş görseli güncellendi');
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Giriş Ekranı Görseli',
            style: TextStyle(
              color: t.ink,
              fontSize: AppFontSize.title,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tüm kullanıcıların giriş ekranında gösterilir. Yalnızca super admin değiştirebilir.',
            style: TextStyle(color: t.muted, fontSize: AppFontSize.label),
          ),
          const SizedBox(height: 12),
          Container(
            height: 170,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.border),
            ),
            child: _changed
                ? _draft == null
                      ? Image.asset(
                          'assets/colombia_cafe.png',
                          fit: BoxFit.contain,
                        )
                      : Image.memory(
                          base64Decode(_draft!.split(',').last),
                          fit: BoxFit.contain,
                        )
                : const LoginArt(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _error!,
                style: TextStyle(color: t.danger, fontSize: AppFontSize.label),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Görsel Seç'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _draft = null;
                    _changed = true;
                  }),
            child: const Text('Varsayılan Görsele Dön'),
          ),
          if (_changed)
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_busy ? 'Kaydediliyor...' : 'Görseli Kaydet'),
            ),
        ],
      ),
    );
  }
}
