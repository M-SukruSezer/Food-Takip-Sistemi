import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/avatar_image.dart';
import '../core/busy.dart';
import '../core/format.dart';
import '../core/image_pick.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/pdks.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';

/// Taleplerim: personelin tum taleplerini (izin, vardiya takasi, haftalik
/// OFF, rapor) olusturdugu ve durumlarini izledigi modul.
///
/// Takasta karsi taraf olan personel de talebi burada gorur ve onaylar;
/// karar mudurun onayi ile kesinlesir ve cizelge kendiliginden degisir.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<PersonnelRequest> _requests = const [];
  PdksBalance? _balance;
  bool _loaded = false;
  String? _error;
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final r = await repo.pdksRequests(silent: silent);
      if (!mounted) return;
      setState(() {
        _requests = r;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _loaded = true;
      });
      return;
    }
    repo
        .pdksBalance()
        .then((b) {
          if (mounted) setState(() => _balance = b);
        })
        .onError((Object _, StackTrace _) {});
  }

  Future<void> _new() async {
    final ok = await showNewRequestDialog(context, balance: _balance);
    if (ok == true) await _load(silent: true);
  }

  List<PersonnelRequest> get _visible => switch (_filter) {
    'PENDING' => _requests.where((r) => r.isPending).toList(),
    'DONE' => _requests.where((r) => !r.isPending).toList(),
    _ => _requests,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final me = session.user?.id;
    final bekleyen = _requests.where((r) => r.isPending).length;
    final onayimda = _requests
        .where((r) => r.awaitsTarget && r.targetUserId == me)
        .length;

    return CrudScaffold(
      title: 'Taleplerim',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      addLabel: 'Yeni Talep',
      onAdd: _new,
      emptyText: '',
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EqualTileGrid(
            maxColumns: 3,
            children: [
              StatCard(label: 'Bekleyen', value: '$bekleyen'),
              StatCard(
                label: 'Kalan İzin',
                value: _balance == null
                    ? '—'
                    : '${_balance!.remainingDays} gün',
              ),
              StatCard(label: 'Onayımı Bekleyen', value: '$onayimda'),
            ],
          ),
          const SizedBox(height: AppTokens.gap),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _new,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Yeni Talep Oluştur'),
            ),
          ),
          const SizedBox(height: AppTokens.gap),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'ALL', label: Text('Tümü')),
              ButtonSegment(value: 'PENDING', label: Text('Bekleyen')),
              ButtonSegment(value: 'DONE', label: Text('Sonuçlanan')),
            ],
            selected: {_filter},
            onSelectionChanged: (v) => setState(() => _filter = v.first),
          ),
        ],
      ),
      children: [
        if (_visible.isEmpty)
          AppCard(
            child: Text(
              _requests.isEmpty
                  ? 'Henüz talebiniz yok. "Yeni Talep Oluştur" ile izin, '
                        'vardiya takası, OFF günü ya da rapor talebi '
                        'oluşturabilirsiniz.'
                  : 'Bu filtrede talep yok.',
              style: TextStyle(fontSize: AppFontSize.body, color: t.muted),
            ),
          )
        else
          ..._visible.map(
            (r) =>
                RequestCard(request: r, onChanged: () => _load(silent: true)),
          ),
      ],
    );
  }
}

/// Tek talep karti: tur, ozet, durum ve personelin yapabilecegi islemler
/// (geri alma, takasi onaylama, rapor gorselini acma).
class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.request,
    required this.onChanged,
  });

  final PersonnelRequest request;
  final VoidCallback onChanged;

  Future<void> _cancel(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Talebi Geri Al',
      confirmLabel: 'Geri Al',
      body: Text('${request.typeLabel} talebiniz geri alınacak.'),
    );
    if (ok != true) return;
    try {
      await repo.pdksCancelRequest(request.id);
    } catch (_) {
      // Bildirim API katmanindan gelir.
    }
    onChanged();
  }

  Future<void> _confirm(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Takası Onayla',
      confirmLabel: 'Onayla',
      body: Text(
        '${request.fullName ?? 'Personel'} ile ${requestSummary(request)} '
        'takası onaylanacak. Son karar mağaza müdürünün.',
      ),
    );
    if (ok != true) return;
    try {
      await repo.pdksConfirmRequest(request.id);
    } catch (_) {}
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = request;
    final me = session.user?.id;
    final mine = r.userId == null || r.userId == me;
    final iAmTarget = r.targetUserId != null && r.targetUserId == me;

    final color = r.isPending
        ? t.warning
        : r.status == 'APPROVED'
        ? t.success
        : t.danger;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(requestTypeIcon(r.type), size: 20, color: t.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.typeLabel,
                  style: TextStyle(
                    fontSize: AppFontSize.bodyLarge,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
              Pill(text: r.statusLabel, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            requestSummary(r),
            style: TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w500,
              color: t.ink,
            ),
          ),
          if (r.type == 'VARDIYA_TAKAS')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                mine
                    ? 'Takas: ${r.targetName ?? '—'}'
                    : 'Talep eden: ${r.fullName ?? '—'}',
                style: TextStyle(fontSize: AppFontSize.label, color: t.muted),
              ),
            ),
          if (r.reason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              r.reason,
              style: TextStyle(fontSize: AppFontSize.label, color: t.muted),
            ),
          ],
          if (r.decisionNote != null) ...[
            const SizedBox(height: 2),
            Text(
              'Karar notu: ${r.decisionNote}',
              style: TextStyle(fontSize: AppFontSize.label, color: t.danger),
            ),
          ],
          if (r.hasAttachment ||
              (r.isPending && mine) ||
              (r.awaitsTarget && iAmTarget)) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (r.hasAttachment)
                  TextButton.icon(
                    onPressed: () => showRequestAttachment(context, r),
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('Raporu Gör'),
                  ),
                if (r.awaitsTarget && iAmTarget)
                  FilledButton.icon(
                    onPressed: () => _confirm(context),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Takası Onayla'),
                  ),
                if (r.isPending && mine)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: t.danger),
                    onPressed: () => _cancel(context),
                    child: const Text('Geri Al'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

IconData requestTypeIcon(String type) => switch (type) {
  'IZIN' => Icons.beach_access_outlined,
  'SAATLIK_IZIN' => Icons.schedule,
  'VARDIYA_TAKAS' => Icons.swap_horiz,
  'VARDIYA_DEVIR' => Icons.forward,
  'HAFTALIK_OFF' => Icons.event_busy_outlined,
  'RAPOR' => Icons.medical_services_outlined,
  _ => Icons.description_outlined,
};

/// Talebin tek satirlik ozeti.
String requestSummary(PersonnelRequest r) => switch (r.type) {
  'IZIN' => '${fmtDate(r.startAt)} – ${fmtDate(r.endAt)} (${r.days} gün)',
  'SAATLIK_IZIN' => '${fmtDateTime(r.startAt)} · ${r.hours} saat',
  'VARDIYA_TAKAS' =>
    r.targetShiftDate != null && r.targetShiftDate != r.shiftDate
        ? '${_gun(r.shiftDate)} ↔ ${_gun(r.targetShiftDate)} vardiyaları'
        : '${_gun(r.shiftDate)} vardiyası',
  'VARDIYA_DEVIR' => '${_gun(r.shiftDate)} vardiyası',
  'HAFTALIK_OFF' =>
    r.targetShiftDate != null
        ? 'OFF günü ${_gun(r.targetShiftDate)} → ${_gun(r.shiftDate)}'
        : '${_gun(r.shiftDate)} OFF günü',
  'RAPOR' =>
    r.startAt == r.endAt
        ? '${fmtDate(r.startAt)} (1 gün)'
        : '${fmtDate(r.startAt)} – ${fmtDate(r.endAt)} (${r.days} gün)',
  _ => '',
};

const _kisaGun = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

/// 'YYYY-MM-DD' -> 'Pzt 06.10'
String _gun(String? ymdText) {
  final d = DateTime.tryParse(ymdText ?? '');
  if (d == null) return ymdText ?? '—';
  return '${_kisaGun[d.weekday - 1]} '
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
}

/// Rapor gorselini tam ekran acar.
Future<void> showRequestAttachment(
  BuildContext context,
  PersonnelRequest r,
) async {
  String? url;
  try {
    url = await repo.pdksRequestAttachment(r.id);
  } catch (_) {
    return;
  }
  if (url == null || !context.mounted) return;
  final bytes = base64Decode(url.split(',').last);
  await showAppSheet<void>(
    context: context,
    builder: (ctx) => StandardDialog(
      title: const Text('Rapor Görseli'),
      subtitle: '${r.fullName ?? ''} · ${requestSummary(r)}',
      child: InteractiveViewer(
        maxScale: 5,
        child: Image.memory(bytes, fit: BoxFit.contain),
      ),
    ),
  );
}

/// Yeni talep formu: yillik/saatlik izin, vardiya takasi, haftalik OFF, rapor.
///
/// Takas ve OFF icin personelin onumuzdeki vardiyalari onceden yuklenir; gun
/// bir listeden secilir, yanlis gun yazma ihtimali kalmaz.
Future<bool?> showNewRequestDialog(
  BuildContext context, {
  PdksBalance? balance,
  String initialType = 'IZIN',
}) async {
  final today = DateTime.now();
  final from = DateTime(today.year, today.month, today.day);
  var colleagues = const <Colleague>[];
  var mine = const <ShiftAssignment>[];
  busy.begin();
  try {
    final results = await Future.wait([
      repo.pdksColleagues().onError((Object _, StackTrace _) => const []),
      repo
          .pdksAssignments(
            from: ymd(from),
            to: ymd(from.add(const Duration(days: 42))),
          )
          .onError((Object _, StackTrace _) => const []),
    ]);
    colleagues = results[0] as List<Colleague>;
    mine = results[1] as List<ShiftAssignment>;
  } finally {
    busy.end();
  }
  if (!context.mounted) return null;

  final myShifts = mine.where((a) => !a.isDayOff).toList();
  final myOffs = mine.where((a) => a.isDayOff).toList();

  var type = initialType;
  var start = today;
  var end = today;
  var hourStart = today;
  var hourEnd = today.add(const Duration(hours: 2));
  String? myShiftDate = myShifts.isEmpty ? null : myShifts.first.workDate;
  int? targetId = colleagues.isEmpty ? null : colleagues.first.id;
  var sameDay = true;
  DateTime? targetDate;
  var offDate = from.add(const Duration(days: 1));
  String? oldOff;
  var raporFrom = from;
  var raporTo = from;
  String? raporUrl;
  Uint8List? raporPreview;
  String? imageError;
  final reason = TextEditingController();

  String mondayOf(DateTime d) => ymd(d.subtract(Duration(days: d.weekday - 1)));

  String shiftLabel(ShiftAssignment a) {
    final saat = a.startTime == null ? '' : ' ${a.startTime}–${a.endTime}';
    return '${_gun(a.workDate)} · ${a.shiftName ?? 'Vardiya'}$saat';
  }

  return showAppSheet<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: 'Yeni Talep',
      submitLabel: 'Gönder',
      fields: (context, rebuild) {
        final t = context.tokens;
        TextStyle hint() =>
            TextStyle(fontSize: AppFontSize.label, color: t.muted);

        Future<void> pick({required bool camera}) async {
          imageError = null;
          try {
            final bytes = await pickImageBytes(fromCamera: camera);
            if (bytes != null) {
              raporUrl = encodeReceipt(bytes);
              raporPreview = base64Decode(raporUrl!.split(',').last);
            }
          } on FormatException catch (e) {
            imageError = e.message;
          } catch (e) {
            imageError = 'Görsel alınamadı: $e';
          }
          rebuild();
        }

        final offWeek = mondayOf(offDate);
        final weekOffs = myOffs
            .where(
              (a) =>
                  a.workDate != ymd(offDate) &&
                  mondayOf(DateTime.parse(a.workDate)) == offWeek,
            )
            .toList();
        if (oldOff != null && !weekOffs.any((a) => a.workDate == oldOff)) {
          oldOff = null;
        }

        return [
          LabeledField(
            label: 'Talep Türü',
            child: DropdownButtonFormField<String>(
              initialValue: type,
              isExpanded: true,
              items: [
                for (final k in const [
                  'IZIN',
                  'SAATLIK_IZIN',
                  'VARDIYA_TAKAS',
                  'HAFTALIK_OFF',
                  'RAPOR',
                ])
                  DropdownMenuItem(
                    value: k,
                    child: Row(
                      children: [
                        Icon(requestTypeIcon(k), size: 18),
                        const SizedBox(width: 8),
                        Text(requestTypeLabel(k)),
                      ],
                    ),
                  ),
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
                child: DateOnlyField(
                  value: start,
                  onChanged: (v) {
                    start = v;
                    rebuild();
                  },
                ),
              ),
              right: LabeledField(
                label: 'Bitiş',
                child: DateOnlyField(
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
                  'Kalan hakkınız ${balance.remainingDays} gün.',
                  style: hint(),
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
          if (type == 'VARDIYA_TAKAS') ...[
            if (myShifts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Önümüzdeki günlerde size atanmış bir vardiya yok; '
                  'takas için önce çizelgede vardiyanız olmalı.',
                  style: hint(),
                ),
              )
            else
              LabeledField(
                label: 'Devredeceğim Vardiya',
                child: DropdownButtonFormField<String>(
                  initialValue: myShiftDate,
                  isExpanded: true,
                  items: [
                    for (final a in myShifts)
                      DropdownMenuItem(
                        value: a.workDate,
                        child: Text(
                          shiftLabel(a),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    myShiftDate = v;
                    rebuild();
                  },
                ),
              ),
            LabeledField(
              label: 'Takas Yapılacak Partner',
              child: DropdownButtonFormField<int>(
                initialValue: targetId,
                isExpanded: true,
                items: [
                  for (final c in colleagues)
                    DropdownMenuItem(value: c.id, child: Text(c.fullName)),
                ],
                onChanged: (v) {
                  targetId = v;
                  rebuild();
                },
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: sameDay,
              title: const Text('Aynı gün içinde takas'),
              subtitle: Text(
                sameDay
                    ? 'O günkü vardiyalarınız yer değiştirir.'
                    : 'Partnerin seçtiğiniz gündeki vardiyasını alırsınız.',
                style: hint(),
              ),
              onChanged: (v) {
                sameDay = v;
                rebuild();
              },
            ),
            if (!sameDay)
              LabeledField(
                label: 'Partnerin Vardiya Günü',
                child: DateOnlyField(
                  value: targetDate,
                  firstDate: from,
                  onChanged: (v) {
                    targetDate = v;
                    rebuild();
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Önce partneriniz onaylar, ardından mağaza müdürü. Onayla '
                'birlikte haftalık çizelge otomatik güncellenir.',
                style: hint(),
              ),
            ),
          ],
          if (type == 'HAFTALIK_OFF') ...[
            LabeledField(
              label: 'İstediğim OFF Günü',
              child: DateOnlyField(
                value: offDate,
                firstDate: from,
                onChanged: (v) {
                  offDate = v;
                  rebuild();
                },
              ),
            ),
            LabeledField(
              label: 'Bu Haftaki Mevcut OFF Günüm',
              hint: 'Seçerseniz iki gün yer değiştirir.',
              child: DropdownButtonFormField<String?>(
                key: ValueKey('off-$offWeek'),
                initialValue: oldOff,
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Değiştirme, yalnızca OFF ekle'),
                  ),
                  for (final a in weekOffs)
                    DropdownMenuItem<String?>(
                      value: a.workDate,
                      child: Text('${_gun(a.workDate)} · OFF'),
                    ),
                ],
                onChanged: (v) {
                  oldOff = v;
                  rebuild();
                },
              ),
            ),
          ],
          if (type == 'RAPOR') ...[
            FormRow(
              left: LabeledField(
                label: 'Rapor Başlangıcı',
                child: DateOnlyField(
                  value: raporFrom,
                  onChanged: (v) {
                    raporFrom = v;
                    rebuild();
                  },
                ),
              ),
              right: LabeledField(
                label: 'Rapor Bitişi',
                child: DateOnlyField(
                  value: raporTo,
                  onChanged: (v) {
                    raporTo = v;
                    rebuild();
                  },
                ),
              ),
            ),
            LabeledField(
              label: 'Rapor Görseli',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (raporPreview != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Image.memory(
                          raporPreview!,
                          height: 160,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pick(camera: false),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galeriden'),
                        ),
                      ),
                      if (cameraAvailable()) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pick(camera: true),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Fotoğraf Çek'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (imageError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        imageError!,
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          color: t.danger,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          LabeledField(
            label: type == 'HAFTALIK_OFF' || type == 'RAPOR'
                ? 'Açıklama (isteğe bağlı)'
                : 'Gerekçe',
            child: TextField(
              controller: reason,
              maxLines: 2,
              style: const TextStyle(fontSize: AppFontSize.title),
            ),
          ),
        ];
      },
      onSubmit: () async {
        final text = reason.text.trim();
        final optional = type == 'HAFTALIK_OFF' || type == 'RAPOR';
        if (text.isEmpty && !optional) return 'Gerekçe zorunludur';

        final body = <String, Object?>{'type': type, 'reason': text};
        switch (type) {
          case 'IZIN':
            if (ymd(end).compareTo(ymd(start)) < 0) {
              return 'Bitiş tarihi başlangıçtan önce olamaz';
            }
            body['start_at'] = ymd(start);
            body['end_at'] = ymd(end);
          case 'SAATLIK_IZIN':
            if (!hourEnd.isAfter(hourStart)) {
              return 'Bitiş saati başlangıçtan sonra olmalıdır';
            }
            body['start_at'] = hourStart.toUtc().toIso8601String();
            body['end_at'] = hourEnd.toUtc().toIso8601String();
          case 'VARDIYA_TAKAS':
            if (myShiftDate == null) return 'Devredeceğiniz vardiyayı seçin';
            if (targetId == null) return 'Takas yapılacak partneri seçin';
            body['shift_date'] = myShiftDate;
            body['target_user_id'] = targetId;
            if (!sameDay) {
              if (targetDate == null) return 'Partnerin vardiya gününü seçin';
              body['target_shift_date'] = ymd(targetDate!);
            }
          case 'HAFTALIK_OFF':
            body['shift_date'] = ymd(offDate);
            if (oldOff != null) body['target_shift_date'] = oldOff;
          case 'RAPOR':
            if (ymd(raporTo).compareTo(ymd(raporFrom)) < 0) {
              return 'Bitiş tarihi başlangıçtan önce olamaz';
            }
            if (raporUrl == null) {
              return 'Rapor görselini galeriden seçin ya da fotoğrafını çekin';
            }
            body['start_at'] = ymd(raporFrom);
            body['end_at'] = ymd(raporTo);
            body['attachment'] = raporUrl;
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

/// Yalnizca tarih secen alan (saat sorulmaz).
class DateOnlyField extends StatelessWidget {
  const DateOnlyField({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final v = value;
    final text = v == null
        ? 'Tarih seçin'
        : '${_kisaGun[v.weekday - 1]} '
              '${v.day.toString().padLeft(2, '0')}.'
              '${v.month.toString().padLeft(2, '0')}.${v.year}';
    return OutlinedButton.icon(
      icon: const Icon(Icons.event, size: 18),
      label: Align(alignment: Alignment.centerLeft, child: Text(text)),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size(double.infinity, AppTokens.tap),
        foregroundColor: t.ink,
        backgroundColor: t.card,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        side: BorderSide(color: t.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      onPressed: () async {
        final now = DateTime.now();
        final first = firstDate ?? DateTime(now.year - 1);
        var initial = v ?? now;
        if (initial.isBefore(first)) initial = first;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: first,
          lastDate: DateTime(now.year + 1, 12, 31),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
