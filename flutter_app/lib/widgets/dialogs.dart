import 'package:flutter/material.dart';

import '../core/tokens.dart';
import 'mobile_sheet.dart';

/// Ortak onay penceresi. Oneri listesi ve stok ekrani ayni bicimi kullanir.
Future<bool?> confirmDialog(
  BuildContext context, {
  required String title,
  required Widget body,
  String confirmLabel = 'Onayla',
  bool danger = true,
}) {
  final t = context.tokens;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: body),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: t.danger)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Pencere icinde hata satir ici gosterilir (API katmani bu cagrilarda
/// bildirim vermez), basari mesajini cagiran ekran verir.
class FormDialog extends StatefulWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    required this.fields,
    required this.onSubmit,
    this.headerIcon,
    this.subtitle,
    this.submitColor,
    this.titleWidget,
    this.mobileSheet = false,
  });

  final String title;
  final bool mobileSheet;
  final String submitLabel;
  final IconData? headerIcon;
  final String? subtitle;
  final Color? submitColor;
  final Widget? titleWidget;

  /// Alanlari kuran yapici; hata metni ve mesgul durumu dialog tarafindan yonetilir.
  final List<Widget> Function(BuildContext context, VoidCallback rebuild)
  fields;

  /// Basarili olursa null, hata varsa gosterilecek metni dondurur.
  final Future<String?> Function() onSubmit;

  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> {
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? err;
    try {
      err = await widget.onSubmit();
    } catch (_) {
      err = 'İşlem tamamlanamadı. Tekrar deneyin.';
    }
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Cep ekraninda sabit 420 genislik tasiyordu ve dialog tum ekrani
    // kapliyordu. Genislik ekrana gore daralir, kenarda bosluk kalir.
    final screen = MediaQuery.sizeOf(context);
    final narrow = screen.width < 600;
    if (widget.mobileSheet) {
      return MobileSheet(
        title: widget.titleWidget ?? Text(widget.title),
        subtitle: widget.subtitle,
        icon: widget.headerIcon,
        busy: _busy,
        footer: Row(
          children: [
            Expanded(
              flex: 2,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: t.bg,
                  foregroundColor: t.ink,
                  minimumSize: const Size(0, 48),
                ),
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.submitColor ?? t.primary,
                  minimumSize: const Size(0, 48),
                ),
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.check_circle_outline, size: 19),
                label: Text(
                  _busy ? 'Kaydediliyor...' : widget.submitLabel,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
        child: AbsorbPointer(
          absorbing: _busy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: t.danger)),
                ),
              ...widget.fields(context, () {
                if (mounted) setState(() {});
              }),
            ],
          ),
        ),
      );
    }
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title:
          widget.titleWidget ??
          (widget.headerIcon != null || widget.subtitle != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!narrow) ...[
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: t.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                    Row(
                      children: [
                        if (widget.headerIcon != null) ...[
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: t.primarySoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              widget.headerIcon,
                              color: t.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: TextStyle(
                                  fontSize: narrow ? 16 : 18,
                                  fontWeight: FontWeight.w700,
                                  color: t.ink,
                                ),
                              ),
                              if (widget.subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.subtitle!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: t.primary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(context, false),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: t.card,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: t.border.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: t.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Text(
                  widget.title,
                  style: TextStyle(fontSize: narrow ? 17 : 20),
                )),
      titlePadding: EdgeInsets.fromLTRB(
        narrow ? 16 : 24,
        narrow ? 14 : 22,
        narrow ? 16 : 24,
        0,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        narrow ? 16 : 24,
        narrow ? 8 : 14,
        narrow ? 16 : 24,
        0,
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 14 : 40,
        vertical: 24,
      ),
      content: SizedBox(
        // Kenar bosluklari (insetPadding + contentPadding) dusulur, yoksa
        // dialog ekranin tamamini kaplayip kenara yapisiyor.
        width: narrow ? screen.width - 2 * 14 - 2 * 18 : 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: t.dangerSoft,
                    border: Border.all(color: t.danger.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  child: Text(_error!, style: TextStyle(color: t.danger)),
                ),
                const SizedBox(height: 12),
              ],
              ...widget.fields(context, () => setState(() {})),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: const Color(0xFFEFF6FF),
            foregroundColor: const Color(0xFF2563EB),
            side: const BorderSide(color: Color(0xFFBFDBFE)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Vazgeç',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.submitColor ?? t.primary,
            foregroundColor: t.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          onPressed: _busy ? null : _submit,
          child: Text(
            _busy ? 'Kaydediliyor...' : widget.submitLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Etiketli alan sarmalayici.
///
/// Cep ekraninda formlar cok uzundu (olculen: 375x667 telefonda gunluk rapor
/// formu 1011px icerik, 640px kaydirma). Etiket ve bosluklar daraltildi;
/// ikili alanlar icin [FormRow] kullanilir.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          const SizedBox(height: 4),
          child,
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: TextStyle(fontSize: 11, color: t.muted)),
          ],
        ],
      ),
    );
  }
}

/// Iki alani yan yana koyar. Sayisal alanlar kisa oldugu icin cep ekraninda
/// bile rahat sigar ve form yuksekligi yariya iner.
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.left, this.right});

  final Widget left;

  /// Tek sayida alan kaldiginda bos birakilir; sol alan yarim genislikte durur
  /// ki hizalama bozulmasin.
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right ?? const SizedBox.shrink()),
      ],
    );
  }
}

/// Alan listesini ikili satirlara boler.
List<Widget> pairFields(List<Widget> fields) {
  final rows = <Widget>[];
  for (var i = 0; i < fields.length; i += 2) {
    rows.add(
      FormRow(
        left: fields[i],
        right: i + 1 < fields.length ? fields[i + 1] : null,
      ),
    );
  }
  return rows;
}

/// Tarih + saat secici. Adjust penceresinde kullanilir.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    super.key,
    required this.value,
    this.onChanged,
    this.fillColor,
  });

  final DateTime? value;
  final Color? fillColor;
  final ValueChanged<DateTime>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = value == null
        ? 'Seçilmedi'
        : '${value!.day.toString().padLeft(2, '0')}.${value!.month.toString().padLeft(2, '0')}.${value!.year} '
              '${value!.hour.toString().padLeft(2, '0')}:${value!.minute.toString().padLeft(2, '0')}';
    return OutlinedButton.icon(
      icon: const Icon(Icons.event, size: 18),
      label: Align(alignment: Alignment.centerLeft, child: Text(text)),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size(double.infinity, AppTokens.tap),
        foregroundColor: t.ink,
        disabledForegroundColor: t.primaryDark,
        backgroundColor: fillColor ?? t.card,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        side: BorderSide(
          color: fillColor != null ? Colors.transparent : t.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onChanged == null
          ? null
          : () async {
              final base = value ?? DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: base,
                firstDate: DateTime(base.year - 2),
                lastDate: DateTime(base.year + 2),
              );
              if (date == null) return;
              if (!context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
              );
              if (time == null) return;
              onChanged!(
                DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                ),
              );
            },
    );
  }
}
