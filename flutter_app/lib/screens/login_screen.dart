import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/notify.dart';
import '../core/remember.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../widgets/login_art.dart';
import '../core/login_branding.dart';

import 'package:flutter/services.dart';

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
    loadLoginArtwork().catchError((Object _) {});
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
    // Bos alan dogrulamasi: gereksiz ag istegi atmasin.
    final user = _username.text.trim();
    final pass = _password.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Kullanıcı adı ve şifre boş bırakılamaz.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.signIn(user, pass);
      await setRememberedUsername(_remember ? user : null);
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Zemin ve uzerindeki yazi temayla gelir: acik temada acik gri + koyu
    // yazi, koyu temada lacivert + acik yazi.
    final panel = t.bg;
    final onPanel = t.ink;

    return Scaffold(
      backgroundColor: panel,
      body: AutofillGroup(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Art(),
                    Container(
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(32),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 16,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Hoş geldin!',
                            style: TextStyle(
                              fontSize: 28,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: onPanel,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Lütfen hesabınıza giriş yapın',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: t.muted,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_error != null) ...[
                            _ErrorPill(
                              message: _error!,
                              card: t.card,
                              danger: t.danger,
                            ),
                            const SizedBox(height: 12),
                          ],
                          _PillField(
                            controller: _username,
                            hint: 'Kullanıcı adı',
                            icon: Icons.alternate_email_rounded,
                            card: t.bg,
                            ink: t.ink,
                            muted: t.muted,
                            border: t.border.withValues(alpha: 0.6),
                            accent: t.primary,
                            ring: t.primary.withValues(alpha: 0.35),
                            autofill: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          _PillField(
                            controller: _password,
                            hint: 'Şifre',
                            icon: Icons.shield_outlined,
                            card: t.bg,
                            ink: t.ink,
                            muted: t.muted,
                            border: t.border.withValues(alpha: 0.6),
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
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                                color: t.muted,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
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
                                  onTap: () =>
                                      setState(() => _remember = !_remember),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: AppTokens.tap,
                                          height: AppTokens.tap,
                                          child: Checkbox(
                                            value: _remember,
                                            onChanged: (v) => setState(
                                              () => _remember = v ?? false,
                                            ),
                                            side: BorderSide(
                                              color: t.border,
                                              width: 1.5,
                                            ),
                                            activeColor: t.primary,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                          ),
                                        ),
                                        Flexible(
                                          child: Text(
                                            'Beni hatırla',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  foregroundColor: t.primary,
                                ),
                                onPressed: () => toast(
                                  'Şifre sıfırlama için yöneticinle iletişime geç',
                                ),
                                child: const Text(
                                  'Şifremi unuttum?',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Siyah hap dugme: koyu temada ink acik renge dondugu
                          // icin yazi kart rengiyle okunur kalir.
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF115E59),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: t.ink.withValues(
                                  alpha: 0.55,
                                ),
                                disabledForegroundColor: t.card.withValues(
                                  alpha: 0.8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .labelLarge!
                                    .copyWith(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              onPressed: _busy ? null : _submit,
                              child: Text(
                                _busy ? 'Giriş yapılıyor...' : 'Giriş Yap',
                              ),
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
      ),
    );
  }
}

/// Ustteki illustrasyon. Kart yok: gorsel dogrudan sayfa zemini uzerinde
/// duruyor.
///
/// Koyu temada gorselin siyah konturlari lacivert zeminle birlesiyordu; bu
/// yuzden yalnizca koyu temada arkasina acik bir daire konur. Acik temada
/// zemin zaten aciktir, daireye gerek yok.
class _Art extends StatelessWidget {
  const _Art();

  /// Daire, gorselin kare kutusu kadar; gorsel biraz iceri alinir ki en
  /// distaki parmak uclari dairenin kenarina dayanmasin.
  static const double _inset = 0.045;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final height = keyboardOpen
        ? 80.0
        : (media.size.height * .27).clamp(140.0, 240.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: SizedBox(
        height: height,
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              padding: dark ? EdgeInsets.all(height * _inset) : EdgeInsets.zero,
              decoration: dark
                  ? const BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      shape: BoxShape.circle,
                    )
                  : null,
              child: const LoginArt(),
            ),
          ),
        ),
      ),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _focus.hasFocus ? widget.accent : widget.border,
          width: _focus.hasFocus ? 1.5 : 1.0,
        ),
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
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: widget.autofill,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: widget.ink,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: widget.muted,
                ),
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
          if (widget.trailing != null)
            widget.trailing!
          else
            const SizedBox(width: 18),
        ],
      ),
    );
  }
}

/// Panel uzerinde okunur kalsin diye hata beyaz zeminde gosterilir.
class _ErrorPill extends StatelessWidget {
  const _ErrorPill({
    required this.message,
    required this.card,
    required this.danger,
  });

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
            child: Text(
              message,
              style: TextStyle(
                color: danger,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
