import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/pdks.dart';
import '../widgets/dialogs.dart';
import '../widgets/qr_view.dart';

/// QR kodu gosterir ve kalan sureyi sayar.
///
/// Donen kodun suresi dolunca kod kendiliginden yenilenir: kullanicidan
/// pencereyi kapatip acmasini beklemek gereksiz surtunme.
Future<void> showQrDialog(
  BuildContext context, {
  required String title,
  required QrToken token,
  required Future<QrToken> Function() onRefresh,
  String? note,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _QrDialog(
      title: title,
      initial: token,
      onRefresh: onRefresh,
      note: note,
    ),
  );
}

class _QrDialog extends StatefulWidget {
  const _QrDialog({
    required this.title,
    required this.initial,
    required this.onRefresh,
    this.note,
  });

  final String title;
  final QrToken initial;
  final Future<QrToken> Function() onRefresh;
  final String? note;

  @override
  State<_QrDialog> createState() => _QrDialogState();
}

class _QrDialogState extends State<_QrDialog> {
  late QrToken _token;
  late int _left;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _token = widget.initial;
    _left = _token.expiresIn;
    if (!_token.isStatic) _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        // Sure doldu: yeni token cekilir, sayac yeniden baslar.
        _refresh();
        return;
      }
      setState(() => _left--);
    });
  }

  Future<void> _refresh() async {
    try {
      final next = await widget.onRefresh();
      if (!mounted) return;
      setState(() {
        _token = next;
        _left = next.expiresIn;
      });
    } catch (_) {
      // Yenilenemezse sayac durur; kullanici pencereyi kapatip tekrar acar.
      _timer?.cancel();
      if (mounted) setState(() => _left = 0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return AlertDialog(
      title: Text(widget.title),
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 14 : 40,
        vertical: 24,
      ),
      content: SizedBox(
        width: narrow
            ? MediaQuery.sizeOf(context).width - 2 * 14 - 2 * 24
            : 360,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              QrView(
                data: _token.token,
                size: narrow ? 200 : 240,
                label: _token.isStatic
                    ? 'Sabit kod — yazdırıp iş yerine asabilirsiniz'
                    : _left > 0
                    ? '$_left saniye geçerli'
                    : 'Süresi doldu, yenileniyor...',
              ),
              if (widget.note != null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.note!,
                  style: TextStyle(fontSize: 12, color: t.muted),
                ),
              ],
              if (_token.isStatic) ...[
                const SizedBox(height: 10),
                Text(
                  'Sabit kod yalnızca iş yeri yarıçapı içindeyken geçerlidir.',
                  style: TextStyle(fontSize: 12, color: t.warning),
                ),
              ],
              const SizedBox(height: 10),
              // Kamerasi calismayan cihazda elle girilebilsin.
              LabeledField(
                label: 'Kod metni',
                child: SelectableText(
                  _token.token,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_token.isStatic)
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Yenile'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

/// Izin / saatlik izin / avans talep formu.
Future<bool?> showRequestDialog(BuildContext context, {PdksBalance? balance}) {
  var type = 'IZIN';
  var start = DateTime.now();
  var end = DateTime.now();
  var hourStart = DateTime.now();
  var hourEnd = DateTime.now().add(const Duration(hours: 2));
  final amount = TextEditingController();
  final reason = TextEditingController();

  String d(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}'
      '-${v.month.toString().padLeft(2, '0')}'
      '-${v.day.toString().padLeft(2, '0')}';

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Yeni Talep',
      submitLabel: 'Gönder',
      fields: (context, rebuild) {
        final t = context.tokens;
        return [
          LabeledField(
            label: 'Talep Türü',
            child: DropdownButtonFormField<String>(
              initialValue: type,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'IZIN', child: Text('Yıllık İzin')),
                DropdownMenuItem(
                  value: 'SAATLIK_IZIN',
                  child: Text('Saatlik İzin'),
                ),
                DropdownMenuItem(value: 'AVANS', child: Text('Avans')),
              ],
              onChanged: (v) {
                type = v ?? 'IZIN';
                rebuild();
              },
            ),
          ),
          if (type == 'IZIN') ...[
            FormRow(
              left: LabeledField(
                label: 'Başlangıç',
                child: DateTimeField(
                  value: start,
                  onChanged: (v) {
                    start = v;
                    rebuild();
                  },
                ),
              ),
              right: LabeledField(
                label: 'Bitiş',
                child: DateTimeField(
                  value: end,
                  onChanged: (v) {
                    end = v;
                    rebuild();
                  },
                ),
              ),
            ),
            if (balance != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Kalan hakkınız ${balance.remainingDays} gün. Hafta tatili '
                  'günleri düşülmez, resmi tatiller hesaba katılmaz.',
                  style: TextStyle(fontSize: 12, color: t.muted),
                ),
              ),
          ],
          if (type == 'SAATLIK_IZIN') ...[
            LabeledField(
              label: 'Başlangıç',
              child: DateTimeField(
                value: hourStart,
                onChanged: (v) {
                  hourStart = v;
                  rebuild();
                },
              ),
            ),
            LabeledField(
              label: 'Bitiş',
              hint: 'Aynı gün içinde ve en fazla 12 saat olabilir.',
              child: DateTimeField(
                value: hourEnd,
                onChanged: (v) {
                  hourEnd = v;
                  rebuild();
                },
              ),
            ),
          ],
          if (type == 'AVANS')
            LabeledField(
              label: 'Tutar (₺)',
              hint: balance == null
                  ? null
                  : 'Bu ay kalan limitiniz ${fmtMoney(balance.advanceRemaining)}.',
              child: TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          LabeledField(
            label: 'Gerekçe',
            child: TextField(
              controller: reason,
              maxLines: 2,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ];
      },
      onSubmit: () async {
        final text = reason.text.trim();
        if (text.isEmpty) return 'Gerekçe zorunludur';

        final body = <String, Object?>{'type': type, 'reason': text};
        if (type == 'IZIN') {
          if (d(end).compareTo(d(start)) < 0) {
            return 'Bitiş tarihi başlangıçtan önce olamaz';
          }
          body['start_at'] = d(start);
          body['end_at'] = d(end);
        } else if (type == 'SAATLIK_IZIN') {
          if (!hourEnd.isAfter(hourStart)) {
            return 'Bitiş saati başlangıçtan sonra olmalıdır';
          }
          body['start_at'] = hourStart.toUtc().toIso8601String();
          body['end_at'] = hourEnd.toUtc().toIso8601String();
        } else {
          final n = num.tryParse(amount.text.trim().replaceAll(',', '.'));
          if (n == null || n <= 0) return 'Tutar 0’dan büyük olmalıdır';
          body['amount'] = n;
        }

        try {
          await repo.pdksCreateRequest(body);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Talep reddi. Gerekce zorunlu; sunucu da bos gerekceyi kabul etmiyor.
Future<bool?> showRequestRejectDialog(
  BuildContext context,
  PersonnelRequest request,
) {
  final note = TextEditingController();
  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Talebi Reddet',
      submitLabel: 'Reddet',
      fields: (context, rebuild) {
        final t = context.tokens;
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${request.fullName ?? ''} · ${request.typeLabel}',
              style: TextStyle(fontSize: 13, color: t.muted),
            ),
          ),
          LabeledField(
            label: 'Ret Gerekçesi',
            hint: 'Personel bu gerekçeyi görecek.',
            child: TextField(
              controller: note,
              autofocus: true,
              maxLines: 2,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ];
      },
      onSubmit: () async {
        final text = note.text.trim();
        if (text.isEmpty) return 'Ret gerekçesi zorunludur';
        try {
          await repo.pdksDecideRequest(request.id, false, note: text);
          return null;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Personel ucret ve profil tanimlari.
///
/// Para alanlarinda BOS BIRAKMAK tanimi kaldirir (null gonderilir); SIFIR
/// yazmak "tanimli ama odenmiyor" demektir. Iki durum ayri tutuluyor cunku
/// 0 TL yazmak "ucretsiz calisiyor" anlamina gelirdi.
Future<bool?> showProfileDialog(BuildContext context, PdksProfile p) {
  final hired = TextEditingController(text: p.hiredAt ?? '');
  final izin = TextEditingController(text: _n(p.annualLeaveDays));
  final avans = TextEditingController(text: _n(p.monthlyAdvanceLimit));
  final maas = TextEditingController(
    text: p.monthlySalary == null ? '' : _n(p.monthlySalary!),
  );
  final saatlik = TextEditingController(
    text: p.hourlyRate == null ? '' : _n(p.hourlyRate!),
  );
  final yemek = TextEditingController(
    text: p.mealDaily == null ? '' : _n(p.mealDaily!),
  );

  return showDialog<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: '${p.fullName} — Tanımlar',
      submitLabel: 'Kaydet',
      fields: (context, rebuild) {
        final t = context.tokens;
        return [
          FormRow(
            left: LabeledField(
              label: 'İşe giriş (YYYY-AA-GG)',
              child: TextField(
                controller: hired,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(hintText: 'tanımsız'),
              ),
            ),
            right: LabeledField(
              label: 'Yıllık izin (gün)',
              child: TextField(
                controller: izin,
                keyboardType: TextInputType.number,
              ),
            ),
          ),
          LabeledField(
            label: 'Aylık avans limiti',
            child: TextField(
              controller: avans,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ),
          const Divider(height: 20),
          FormRow(
            left: LabeledField(
              label: 'Aylık brüt maaş',
              child: TextField(
                controller: maas,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(hintText: 'tanımsız'),
              ),
            ),
            right: LabeledField(
              label: 'Saat ücreti',
              child: TextField(
                controller: saatlik,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  hintText: 'aylıktan türetilir',
                ),
              ),
            ),
          ),
          LabeledField(
            label: 'Günlük yemek ücreti',
            child: TextField(
              controller: yemek,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(hintText: 'tanımsız'),
            ),
          ),
          Text(
            'Alanı boş bırakmak tanımı kaldırır. Sıfır yazmak "tanımlı ama '
            'ödenmiyor" demektir. Tutarlar brüt hak ediş hesabında kullanılır; '
            'SGK ve vergi kesintileri hesaplanmaz.',
            style: TextStyle(fontSize: 12, color: t.muted),
          ),
        ];
      },
      onSubmit: () async {
        final tarih = hired.text.trim();
        if (tarih.isNotEmpty &&
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(tarih)) {
          return 'İşe giriş tarihi YYYY-AA-GG biçiminde olmalıdır';
        }
        // Bos = null (tanimi kaldir). Gecersiz sayi = hata.
        double? para(TextEditingController c, String etiket, String? hata) {
          final ham = c.text.trim().replaceAll(',', '.');
          if (ham.isEmpty) return null;
          final n = double.tryParse(ham);
          if (n == null || n < 0) {
            throw _FormHata('$etiket 0 veya daha büyük olmalıdır');
          }
          return n;
        }

        try {
          final gunSayisi = double.tryParse(
            izin.text.trim().replaceAll(',', '.'),
          );
          if (gunSayisi == null || gunSayisi < 0 || gunSayisi > 365) {
            return 'Yıllık izin 0-365 gün arasında olmalıdır';
          }
          await repo.pdksSaveProfile(
            userId: p.userId,
            hiredAt: tarih.isEmpty ? null : tarih,
            annualLeaveDays: gunSayisi,
            monthlyAdvanceLimit: para(avans, 'Avans limiti', null) ?? 0,
            monthlySalary: para(maas, 'Aylık maaş', null),
            hourlyRate: para(saatlik, 'Saat ücreti', null),
            mealDaily: para(yemek, 'Günlük yemek ücreti', null),
          );
          return null;
        } on _FormHata catch (e) {
          return e.mesaj;
        } catch (e) {
          return errorMessage(e);
        }
      },
    ),
  );
}

/// Alan dogrulamasini onSubmit'in string donusune tasimak icin.
class _FormHata implements Exception {
  _FormHata(this.mesaj);
  final String mesaj;
}

/// Ondalik gereksizse tam sayi gosterir: "14" degil "14.0" yazmak alani
/// kirli gosteriyordu.
String _n(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
