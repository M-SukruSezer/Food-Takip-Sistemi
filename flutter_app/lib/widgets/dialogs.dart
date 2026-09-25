import 'package:flutter/material.dart';

import '../core/tokens.dart';

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
  });

  final String title;
  final String submitLabel;

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
    final err = await widget.onSubmit();
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
    return AlertDialog(
      title: Text(widget.title, style: TextStyle(fontSize: narrow ? 17 : 20)),
      titlePadding: EdgeInsets.fromLTRB(
        narrow ? 18 : 24,
        narrow ? 18 : 24,
        narrow ? 18 : 24,
        0,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        narrow ? 18 : 24,
        14,
        narrow ? 18 : 24,
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
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Kaydediliyor...' : widget.submitLabel),
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
    required this.onChanged,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

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
      ),
      onPressed: () async {
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
        onChanged(
          DateTime(date.year, date.month, date.day, time.hour, time.minute),
        );
      },
    );
  }
}
