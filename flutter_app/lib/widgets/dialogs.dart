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
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: t.danger) : null,
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
  final List<Widget> Function(BuildContext context, VoidCallback rebuild) fields;

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
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.ink)),
          const SizedBox(height: 6),
          child,
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, style: TextStyle(fontSize: 12, color: t.muted)),
          ],
        ],
      ),
    );
  }
}

/// Tarih + saat secici. Adjust penceresinde kullanilir.
class DateTimeField extends StatelessWidget {
  const DateTimeField({super.key, required this.value, required this.onChanged});

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
        onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
    );
  }
}
