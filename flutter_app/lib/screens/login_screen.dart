import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/notify.dart';
import '../core/remember.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../widgets/login_art.dart';

/// Giris ekrani. Duzen referans tasarimdan alindi: ustte yuvarlak kose beyaz
/// kart (marka + illustrasyon), altta marka renginde panel (baslik, beyaz hap
/// seklinde alanlar, siyah hap dugme).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _remember = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restoreRemembered();
  }

  /// React'teki "Beni hatirla" ile ayni davranis: yalnizca kullanici adi
  /// saklanir, sifre asla saklanmaz.
  Future<void> _restoreRemembered() async {
    final saved = await rememberedUsername();
    if (!mounted || saved == null) return;
    setState(() {
      _username.text = saved;
      _remember = true;
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Cift gonderim korumasi: Enter'a arka arkaya basmak ikinci istek atmaz.
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.signIn(_username.text.trim(), _password.text);
      await setRememberedUsername(_remember ? _username.text.trim() : null);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = MediaQuery.of(context);

    // Zemin ve uzerindeki yazi temayla gelir: acik temada acik gri + koyu
    // yazi, koyu temada lacivert + acik yazi.
    final panel = t.bg;
    final onPanel = t.ink;

    return Scaffold(
      backgroundColor: panel,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ArtCard(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Hoş geldin!',
                          style: TextStyle(
                            fontSize: 34,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: onPanel,
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (_error != null) ...[
                          _ErrorPill(message: _error!, card: t.card, danger: t.danger),
                          const SizedBox(height: 12),
                        ],
                        _PillField(
                          controller: _username,
                          hint: 'Kullanıcı adı',
                          icon: Icons.person_outline,
                          card: t.card,
                          ink: t.ink,
                          muted: t.muted,
                          border: t.border,
                          accent: t.primary,
                          ring: t.primary.withValues(alpha: 0.35),
                          autofill: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        _PillField(
                          controller: _password,
                          hint: 'Şifre',
                          icon: Icons.lock_outline,
                          card: t.card,
                          ink: t.ink,
                          muted: t.muted,
                          border: t.border,
                          accent: t.primary,
                          ring: t.primary.withValues(alpha: 0.35),
                          autofill: const [AutofillHints.password],
                          obscure: _obscure,
                          onSubmitted: (_) => _submit(),
                          trailing: IconButton(
                            // 44px dokunma hedefi
                            constraints: const BoxConstraints(
                              minWidth: AppTokens.tap,
                              minHeight: AppTokens.tap,
                            ),
                            icon: Icon(
                              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                              color: t.muted,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                            tooltip: 'Şifreyi göster',
                          ),
                        ),
                        const SizedBox(height: 10),
                        // React istemcisiyle ayni duzen: solda "Beni hatirla",
                        // sagda "Sifremi unuttum?".
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: InkWell(
                                onTap: () => setState(() => _remember = !_remember),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: AppTokens.tap,
                                        height: AppTokens.tap,
                                        child: Checkbox(
                                          value: _remember,
                                          onChanged: (v) => setState(() => _remember = v ?? false),
                                          side: BorderSide(color: onPanel, width: 2),
                                          checkColor: panel,
                                          fillColor: WidgetStateProperty.resolveWith(
                                            (states) => states.contains(WidgetState.selected)
                                                ? onPanel
                                                : Colors.transparent,
                                          ),
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(
                                          'Beni hatırla',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: onPanel,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, AppTokens.tap),
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                foregroundColor: onPanel,
                              ),
                              onPressed: () =>
                                  toast('Şifre sıfırlama için yöneticinle iletişime geç'),
                              child: const Text(
                                'Şifremi unuttum?',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Siyah hap dugme: koyu temada ink acik renge dondugu
                        // icin yazi kart rengiyle okunur kalir.
                        SizedBox(
                          height: 56,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: t.ink,
                              foregroundColor: t.card,
                              disabledBackgroundColor: t.ink.withValues(alpha: 0.55),
                              disabledForegroundColor: t.card.withValues(alpha: 0.8),
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            onPressed: _busy ? null : _submit,
                            child: Text(_busy ? 'Giriş yapılıyor...' : 'Giriş Yap'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ustteki beyaz kart: sol ustte marka, ortada illustrasyon.
///
/// Illustrasyon sabit renkli bir raster oldugu icin kart ve marka yazisi
/// temaya gore degismez: koyu temada lacivert kart uzerinde gorselin siyah
/// konturlari kaybolurdu.
class _ArtCard extends StatelessWidget {
  const _ArtCard();

  static const Color _cardColor = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.34).clamp(190.0, 300.0);
    return Container(
      height: height,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        // Kart sabit beyaz; acik temada zemin de acik oldugu icin ince bir
        // cerceve olmadan sinirlari kayboluyor.
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Center(child: LoginArt()),
    );
  }
}

/// Beyaz hap seklinde giris alani; ikon solda, opsiyonel dugme sagda.
///
/// Kendi cercevesi olmadigi icin odaklandiginda hicbir geri bildirim yoktu;
/// klavyeyle gezen kullanici hangi alanda oldugunu goremiyordu. Odakta hap
/// cevresinde halka cizilir.
class _PillField extends StatefulWidget {
  const _PillField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.card,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.ring,
    required this.border,
    this.obscure = false,
    this.trailing,
    this.autofill,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color card;
  final Color ink;
  final Color muted;
  final Color accent;

  /// Odak halkasinin rengi; zemin uzerinde ayrissin diye disaridan verilir.
  final Color ring;

  /// Acik temada zemin de acik oldugu icin hap kendi cercevesiyle ayrisir.
  final Color border;
  final bool obscure;
  final Widget? trailing;
  final Iterable<String>? autofill;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PillField> createState() => _PillFieldState();
}

class _PillFieldState extends State<_PillField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 56,
      decoration: BoxDecoration(
        color: widget.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: widget.border),
        boxShadow: _focus.hasFocus
            ? [BoxShadow(color: widget.ring, spreadRadius: 3, blurRadius: 0)]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Icon(widget.icon, size: 20, color: widget.accent),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              obscureText: widget.obscure,
              autofillHints: widget.autofill,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: widget.ink),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: widget.muted),
                // Hap govdesi Container'da; alanin kendi cercevesi olmamali.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing! else const SizedBox(width: 18),
        ],
      ),
    );
  }
}

/// Panel uzerinde okunur kalsin diye hata beyaz zeminde gosterilir.
class _ErrorPill extends StatelessWidget {
  const _ErrorPill({required this.message, required this.card, required this.danger});

  final String message;
  final Color card;
  final Color danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(color: danger, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
