import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/pdks_export.dart';
import '../core/repository.dart';
import '../core/tokens.dart';
import '../models/pdks.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';
import 'pdks_dialogs.dart';

/// Yonetici devam takibi ekrani: anlik durum, talep onayi, puantaj.
///
/// Vardiya tanimi ve magaza ayarlari web arayuzunde; telefonda gunluk
/// operasyon (kim iste, talepler, puantaj) one alindi.
class PdksAdminScreen extends StatefulWidget {
  const PdksAdminScreen({super.key});

  @override
  State<PdksAdminScreen> createState() => _PdksAdminScreenState();
}

enum _Tab { now, requests, timesheet, staff }

class _PdksAdminScreenState extends State<PdksAdminScreen> {
  _Tab _tab = _Tab.now;
  List<PdksProfile> _profiles = const [];
  bool _disa = false;

  PresenceSnapshot _presence = PresenceSnapshot.empty;
  List<PersonnelRequest> _requests = const [];
  TimesheetReport _sheet = TimesheetReport.empty;
  String _requestFilter = 'PENDING';
  int _pendingCount = 0;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  int? _expanded;
  String? _error;
  bool _loaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // "Su an kimler iste" canli olmali.
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_tab == _Tab.now) _loadPresence();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _d(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}'
      '-${v.month.toString().padLeft(2, '0')}'
      '-${v.day.toString().padLeft(2, '0')}';

  Future<void> _load({bool silent = false}) async {
    try {
      await _loadPresence(silent: silent);
      if (!mounted) return;
      setState(() {
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
    _loadRequests();
    _loadSheet();
  }

  Future<void> _loadPresence({bool silent = true}) async {
    final p = await repo.pdksNow(silent: silent);
    if (mounted) setState(() => _presence = p);
  }

  void _loadRequests() {
    repo
        .pdksRequests(status: _requestFilter.isEmpty ? null : _requestFilter)
        .then((r) {
          if (mounted) setState(() => _requests = r);
        })
        .onError((Object _, StackTrace _) {});
    repo
        .pdksRequests(status: 'PENDING')
        .then((r) {
          if (mounted) setState(() => _pendingCount = r.length);
        })
        .onError((Object _, StackTrace _) {});
  }

  void _loadSheet() {
    repo
        .pdksTimesheet(from: _d(_from), to: _d(_to), silent: true)
        .then((s) {
          if (mounted) setState(() => _sheet = s);
        })
        .onError((Object _, StackTrace _) {});
  }

  Future<void> _approve(PersonnelRequest r) async {
    final ok = await confirmDialog(
      context,
      title: 'Talebi Onayla',
      danger: false,
      confirmLabel: 'Onayla',
      body: Text(
        '${r.fullName ?? ''} · ${r.typeLabel}\n'
        '${_detail(r)}\n\n${r.reason}',
      ),
    );
    if (ok != true) return;
    try {
      await repo.pdksDecideRequest(r.id, true);
    } catch (_) {
      // Bildirim API katmanindan gelir.
    }
    _loadRequests();
    _loadSheet();
  }

  Future<void> _reject(PersonnelRequest r) async {
    final ok = await showRequestRejectDialog(context, r);
    if (ok == true) {
      toastSaved('Talep reddedildi');
      _loadRequests();
    }
  }

  static String _detail(PersonnelRequest r) => r.type == 'AVANS'
      ? fmtMoney(r.amount)
      : r.type == 'IZIN'
      ? '${fmtDate(r.startAt)} – ${fmtDate(r.endAt)} (${r.days} gün)'
      : '${fmtDateTime(r.startAt)} · ${r.hours} saat';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return CrudScaffold(
      title: 'Devam Yönetimi',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      emptyText: '',
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<_Tab>(
              segments: [
                const ButtonSegment(value: _Tab.now, label: Text('Anlık')),
                ButtonSegment(
                  value: _Tab.requests,
                  label: Text(
                    _pendingCount > 0
                        ? 'Talepler ($_pendingCount)'
                        : 'Talepler',
                  ),
                ),
                const ButtonSegment(
                  value: _Tab.timesheet,
                  label: Text('Puantaj'),
                ),
                const ButtonSegment(value: _Tab.staff, label: Text('Personel')),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (v) {
                setState(() => _tab = v.first);
                if (_tab == _Tab.now) _loadPresence();
                if (_tab == _Tab.requests) _loadRequests();
                if (_tab == _Tab.timesheet) _loadSheet();
                if (_tab == _Tab.staff) _loadProfiles();
              },
            ),
          ),
          const SizedBox(height: AppTokens.gap),
          if (_tab == _Tab.now)
            AppCard(
              child: Row(
                children: [
                  Icon(Icons.groups_outlined, size: 20, color: t.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Şu an işte: ${_presence.insideCount} kişi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                  ),
                  Text(
                    '60 sn’de yenilenir',
                    style: TextStyle(fontSize: 11, color: t.muted),
                  ),
                ],
              ),
            ),
          if (_tab == _Tab.requests)
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'PENDING', label: Text('Bekleyen')),
                      ButtonSegment(value: 'APPROVED', label: Text('Onaylı')),
                      ButtonSegment(value: '', label: Text('Tümü')),
                    ],
                    selected: {_requestFilter},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) {
                      setState(() => _requestFilter = v.first);
                      _loadRequests();
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Onaylanan izin günlerine vardiya atanmaz ve o günler '
                    'puantajda izin olarak sayılır.',
                    style: TextStyle(fontSize: 12, color: t.muted),
                  ),
                ],
              ),
            ),
          if (_tab == _Tab.timesheet)
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormRow(
                    left: LabeledField(
                      label: 'Başlangıç',
                      child: DateTimeField(
                        value: _from,
                        onChanged: (v) {
                          setState(() => _from = v);
                          _loadSheet();
                        },
                      ),
                    ),
                    right: LabeledField(
                      label: 'Bitiş',
                      child: DateTimeField(
                        value: _to,
                        onChanged: (v) {
                          setState(() => _to = v);
                          _loadSheet();
                        },
                      ),
                    ),
                  ),
                  if (_sheet.total.unscheduledMinutes > 0)
                    Text(
                      '${fmtDuration(_sheet.total.unscheduledMinutes)} çalışma, vardiya '
                      'atanmamış günlerde yapılmış ve sınıflandırılmadı.',
                      style: TextStyle(fontSize: 12, color: t.warning),
                    ),
                  // Aylik puantaj disa aktarma: bordro programina girdi
                  // olacagi icin Excel de sunuluyor.
                  if (_sheet.items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _disa ? null : _excelAktar,
                            icon: const Icon(
                              Icons.table_view_outlined,
                              size: 18,
                            ),
                            label: const Text('Excel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _disa ? null : _pdfAktar,
                            icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 18,
                            ),
                            label: const Text('PDF'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Ucret toplami: yalnizca yetkiliye gonderiliyor.
                  if (_sheet.wagesIncluded &&
                      (_sheet.wageTotal?.defined ?? false)) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 12),
                    Text(
                      'Brüt hak ediş toplamı: '
                      '${fmtMoney(_sheet.wageTotal!.grossTotal ?? 0)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      'maaş ${fmtMoney(_sheet.wageTotal!.salaryTotal ?? 0)}'
                      ' · yemek ${fmtMoney(_sheet.wageTotal!.mealPay ?? 0)}'
                      '${(_sheet.wageTotal!.overtimePay ?? 0) > 0 ? ' · fazla mesai ${fmtMoney(_sheet.wageTotal!.overtimePay!)}' : ''}',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ],
                  ..._sheet.notes.map(
                    (n) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        n,
                        style: TextStyle(fontSize: 11, color: t.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      children: switch (_tab) {
        _Tab.now => _presenceRows(t),
        _Tab.requests => _requestRows(t),
        _Tab.timesheet => _sheetRows(t),
        _Tab.staff => _staffRows(t),
      },
    );
  }

  Future<void> _loadProfiles() async {
    try {
      final p = await repo.pdksProfiles();
      if (mounted) setState(() => _profiles = p);
    } catch (_) {
      // Sessiz: sekme zaten bos liste gosteriyor.
    }
  }

  Future<void> _excelAktar() async {
    setState(() => _disa = true);
    try {
      await exportTimesheetExcel(_sheet);
    } catch (e) {
      toast('Dışa aktarılamadı', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _disa = false);
    }
  }

  Future<void> _pdfAktar() async {
    setState(() => _disa = true);
    try {
      await exportTimesheetPdf(_sheet);
    } catch (e) {
      toast('Dışa aktarılamadı', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _disa = false);
    }
  }

  /// Personel ucret ve profil tanimlari.
  List<Widget> _staffRows(AppTokens t) {
    if (_profiles.isEmpty) {
      return [
        AppCard(
          child: Text(
            'Personel bulunamadı.',
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
        ),
      ];
    }
    return [
      AppCard(
        child: Text(
          'Saat ücreti girilmişse hak ediş ondan hesaplanır; girilmemişse '
          'aylık maaştan türetilir (aylık ÷ 225 saat). Yemek ücreti günlük '
          'tutar × fiilen çalışılan gün sayısıdır.',
          style: TextStyle(fontSize: 12, color: t.muted),
        ),
      ),
      ..._profiles.map(
        (p) => AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.fullName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // null = TANIMSIZ, 0 = tanimli ama odenmiyor.
                      // "0 TL" yazmak "ucretsiz calisiyor" anlamina gelirdi.
                      'Maaş ${p.monthlySalary == null ? '—' : fmtMoney(p.monthlySalary!)}'
                      ' · Saat ${p.hourlyRate != null
                          ? fmtMoney(p.hourlyRate!)
                          : p.effectiveHourlyRate != null
                          ? '${fmtMoney(p.effectiveHourlyRate!)} (türetildi)'
                          : '—'}'
                      ' · Yemek ${p.mealDaily == null ? '—' : fmtMoney(p.mealDaily!)}',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Düzenle',
                onPressed: () => _editProfile(p),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Future<void> _editProfile(PdksProfile p) async {
    final ok = await showProfileDialog(context, p);
    if (ok == true) await _loadProfiles();
  }

  List<Widget> _presenceRows(AppTokens t) {
    final rows = [..._presence.inside, ..._presence.outside];
    if (rows.isEmpty) {
      return [
        AppCard(
          child: Text(
            'Personel bulunamadı.',
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
        ),
      ];
    }
    return rows
        .map(
          (p) => AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: p.isInside ? t.success : t.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.fullName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                      Text(
                        p.lastAt == null
                            ? 'kayıt yok'
                            : '${p.isInside ? 'Giriş' : 'Çıkış'} '
                                  '${fmtDateTime(p.lastAt)}'
                                  '${p.lastMethod != null ? ' · ${p.lastMethod}' : ''}'
                                  '${p.distanceM != null ? ' · ${p.distanceM!.round()} m' : ''}',
                        style: TextStyle(fontSize: 12, color: t.muted),
                      ),
                    ],
                  ),
                ),
                if (p.isInside && p.minutesSince != null)
                  Pill(text: fmtDuration(p.minutesSince!), color: t.success),
              ],
            ),
          ),
        )
        .toList();
  }

  List<Widget> _requestRows(AppTokens t) {
    if (_requests.isEmpty) {
      return [
        AppCard(
          child: Text(
            'Kayıt bulunamadı.',
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
        ),
      ];
    }
    return _requests
        .map(
          (r) => AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.fullName ?? '',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                    ),
                    Pill(
                      text: r.statusLabel,
                      color: r.isPending
                          ? t.warning
                          : r.status == 'APPROVED'
                          ? t.success
                          : t.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${r.typeLabel} · ${_detail(r)}',
                  style: TextStyle(fontSize: 13, color: t.ink),
                ),
                Text(r.reason, style: TextStyle(fontSize: 12, color: t.muted)),
                if (r.decisionNote != null)
                  Text(
                    'Karar notu: ${r.decisionNote}',
                    style: TextStyle(fontSize: 12, color: t.danger),
                  ),
                if (r.isPending) ...[
                  const SizedBox(height: 10),
                  CardActions(
                    children: [
                      FilledButton(
                        onPressed: () => _approve(r),
                        child: const Text('Onayla'),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.danger,
                          side: BorderSide(color: t.danger),
                        ),
                        onPressed: () => _reject(r),
                        child: const Text('Reddet'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        )
        .toList();
  }

  List<Widget> _sheetRows(AppTokens t) {
    if (_sheet.items.isEmpty) {
      return [
        AppCard(
          child: Text(
            'Kayıt bulunamadı.',
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
        ),
      ];
    }
    return _sheet.items.map((it) {
      final s = it.summary;
      final open = _expanded == it.userId;
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    it.fullName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: open ? 'Kapat' : 'Gün gün',
                  onPressed: () =>
                      setState(() => _expanded = open ? null : it.userId),
                  icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _Fig(
                  label: 'Çalışılan',
                  value: fmtDuration(s.workedMinutes),
                  color: t.ink,
                ),
                _Fig(
                  label: 'Fazla mesai',
                  value: fmtDuration(s.overtimeMinutes),
                  color: t.success,
                ),
                _Fig(
                  label: 'Eksik',
                  value: fmtDuration(s.missingMinutes),
                  color: s.missingMinutes > 0 ? t.danger : t.muted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${s.workedDays} gün çalıştı · ${s.leaveDays} gün izin'
              '${s.holidayDays > 0 ? ' · ${s.holidayDays} resmi tatil' : ''}'
              '${s.absentDays > 0 ? ' · ${s.absentDays} gün devamsız' : ''}'
              '${s.lateMinutes > 0 ? ' · ${s.lateMinutes} dk geç' : ''}'
              '${s.deductedBreakMinutes > 0 ? ' · ${s.deductedBreakMinutes} dk mola' : ''}',
              style: TextStyle(fontSize: 12, color: t.muted),
            ),
            // Yasal asgari molanin altinda kalinan gunler (m.68). Dusume etki
            // etmez; uyum sorunu oldugu icin yoneticiye bildiriliyor.
            if (s.breakShortfallDays > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${s.breakShortfallDays} gün yasal asgari mola süresinin altında',
                  style: TextStyle(fontSize: 12, color: t.warningText),
                ),
              ),
            // Ucret hak edisi: sunucu yetki yoksa bu alani HIC gondermiyor.
            if (it.wage != null && it.wage!.defined) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  _Fig(
                    label: 'Maaş',
                    value: fmtMoney(it.wage!.salaryTotal ?? 0),
                    color: t.ink,
                  ),
                  _Fig(
                    label: 'Yemek (${it.wage!.workedDays} gün)',
                    value: it.wage!.mealPay == null
                        ? '—'
                        : fmtMoney(it.wage!.mealPay!),
                    color: t.ink,
                  ),
                  _Fig(
                    label: 'Brüt',
                    value: it.wage!.grossTotal == null
                        ? '—'
                        : fmtMoney(it.wage!.grossTotal!),
                    color: t.primary,
                  ),
                ],
              ),
            ],
            if (open) ...[
              const Divider(height: 20),
              ...it.days.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(
                          fmtDate(d.workDate),
                          style: TextStyle(fontSize: 12, color: t.ink),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          // Resmi tatilde adi gostermek durum listesinden
                          // daha bilgilendirici.
                          d.isHoliday
                              ? (d.holidayName ?? 'Resmi tatil')
                              : d.isDayOff
                              ? 'Hafta tatili'
                              : d.statuses.isEmpty
                              ? (d.shiftNames.join(', ').isEmpty
                                    ? '-'
                                    : d.shiftNames.join(', '))
                              : d.statuses
                                    .map(
                                      (x) =>
                                          x.replaceAll('_', ' ').toLowerCase(),
                                    )
                                    .join(', '),
                          style: TextStyle(
                            fontSize: 11,
                            color: d.isHoliday ? t.danger : t.muted,
                            fontWeight: d.isHoliday
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 62,
                        child: Text(
                          fmtDuration(d.workedMinutes),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, color: t.ink),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          d.overtimeMinutes > 0
                              ? '+${fmtDuration(d.overtimeMinutes)}'
                              : d.missingMinutes > 0
                              ? '-${fmtDuration(d.missingMinutes)}'
                              : '',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: d.overtimeMinutes > 0 ? t.success : t.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }).toList();
  }
}

class _Fig extends StatelessWidget {
  const _Fig({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: t.muted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
