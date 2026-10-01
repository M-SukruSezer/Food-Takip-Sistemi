import 'package:flutter/material.dart';

import '../core/tokens.dart';
import 'standard_dialog.dart';

export 'standard_dialog.dart'
    show showAppSheet, StandardDialog, DialogActions, ActionTone, InlineError;

/// Ortak onay penceresi. Telefonda alttan panel, geniş ekranda diyalog.
Future<bool?> confirmDialog(
  BuildContext context, {
  required String title,
  required Widget body,
  String confirmLabel = 'Onayla',
  String cancelLabel = 'Vazgeç',
  bool danger = true,
  IconData? icon,
}) {
  return showAppSheet<bool>(
    context: context,
    builder: (ctx) => StandardDialog(
      title: Text(title),
      icon: icon,
      iconColor: danger ? ctx.tokens.dangerText : null,
      maxWidth: AppLayout.dialogMaxWidth,
      footer: DialogActions(
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        tone: danger ? ActionTone.danger : ActionTone.primary,
        onConfirm: () => Navigator.pop(ctx, true),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: ctx.tokens.ink, height: 1.5),
        child: body,
      ),
    ),
  );
}

/// Form penceresi. Hata satır içi gösterilir (API katmanı bu çağrılarda
/// bildirim vermez), başarı mesajını çağıran ekran verir.
///
/// Her zaman [showAppSheet] ile açılır; çerçeve, butonlar ve kaydırma
/// [StandardDialog] tarafından sağlanır.
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
    this.tone = ActionTone.primary,
  });

  final String title;
  final String submitLabel;
  final IconData? headerIcon;
  final String? subtitle;
  final Color? submitColor;
  final Widget? titleWidget;
  final ActionTone tone;

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
    return StandardDialog(
      title: widget.titleWidget ?? Text(widget.title),
      subtitle: widget.subtitle,
      icon: widget.headerIcon,
      busy: _busy,
      footer: DialogActions(
        confirmLabel: widget.submitLabel,
        confirmIcon: Icons.check_circle_outline,
        tone: widget.tone,
        color: widget.submitColor,
        busy: _busy,
        onConfirm: _submit,
      ),
      child: AbsorbPointer(
        absorbing: _busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              InlineError(_error!),
              const SizedBox(height: AppSpacing.md),
            ],
            ...widget.fields(context, () {
              if (mounted) setState(() {});
            }),
          ],
        ),
      ),
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
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelMedium!.copyWith(
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: text.bodySmall!.copyWith(color: t.muted)),
          ],
        ],
      ),
    );
  }
}

/// Iki alani yan yana koyar. Sayisal alanlar kisa oldugu icin cep ekraninda
/// bile rahat sigar ve form yuksekligi yariya iner.
class FormRow extends StatelessWidget {
  const FormRow({
    super.key,
    required this.left,
    this.right,
    this.stackBelow = AppLayout.compactForm,
  });

  final Widget left;

  /// Tek sayida alan kaldiginda bos birakilir; sol alan yarim genislikte durur
  /// ki hizalama bozulmasin.
  final Widget? right;
  final double stackBelow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (right != null && constraints.maxWidth < stackBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, right!],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: right ?? const SizedBox.shrink()),
          ],
        );
      },
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
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
