import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/notify.dart';
import '../core/pdks_export.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/dashboard.dart';
import '../models/pdks.dart';
import '../widgets/swipe_actions.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/dialogs.dart';
import '../widgets/panels.dart';

// Toplu vardiya çizelgesi: Mağazanın tüm ekibi bir arada, haftalık matris
// veya zaman çizelgesi görünümünde. Barista dahil herkes görür.
// Tasarım retail operations standardına göre modernize edildi.

const _gunKisa = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];
const _gunUzun = [
  'Pazar',
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
];

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _gunAdi(String tarih, {bool uzun = false}) {
  final d = DateTime.tryParse('${tarih}T00:00:00Z');
  if (d == null) return '';
  return (uzun ? _gunUzun : _gunKisa)[d.toUtc().weekday % 7];
}

/// Verilen tarihin içinde bulunduğu haftanın PAZARTESİ'si.
DateTime _haftaBasi(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

/// İsimden 2 harfli baş harfler üretir (Örn: "Sena Üstünel" -> "SÜ").
String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts[0].isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
}

/// Rol adı: PDF ile aynı etiket.
String _formatRole(String role) => rosterRoleLabel(role);

/// Role göre avatar arka plan rengi.
Color _avatarBg(String role, AppTokens t) {
  switch (role.toLowerCase()) {
    case 'store_manager':
      return t.primary;
    case 'supervisor':
      return t.primary600;
    case 'senior_barista':
      return t.primaryDark;
    default:
      return t.muted;
  }
}

const _cokMagazaRolleri = {
  'super_admin',
  'operations_manager',
  'regional_manager',
};

/// Kategori renkleri ve etiketleri.
({Color zemin, Color metin, String etiket}) _kategoriStili(
  ShiftCategory k,
  AppTokens t,
) => switch (k) {
  ShiftCategory.sabah => (
    zemin: t.infoSoft,
    metin: t.infoText,
    etiket: 'Sabah',
  ),
  ShiftCategory.gunduz => (
    zemin: t.successSoft,
    metin: t.okText,
    etiket: 'Gündüz',
  ),
  ShiftCategory.aksam => (
    zemin: t.warningSoft,
    metin: t.warningText,
    etiket: 'Akşam',
  ),
  ShiftCategory.kapanis => (zemin: t.ink, metin: t.card, etiket: 'Kapanış'),
  ShiftCategory.bilinmiyor => (zemin: t.bg, metin: t.ink, etiket: ''),
};

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  bool _haftalik = true;
  DateTime _anchor = _haftaBasi(DateTime.now());
  String _gun = _iso(DateTime.now());
  Roster? _veri;

  /// Planin altindaki notlar: magaza basina, haftalar arasinda sabit kalir.
  List<RosterNote> _notlar = const [];
  List<StoreOption> _magazalar = const [];
  int? _storeId;
  bool _loaded = false;
  String _error = '';
  bool _disa = false;
  bool _paylasiyor = false;
  List<ShiftDef> _vardiyalar = const [];
  final Map<String, PendingCell> _bekleyen = {};
  bool _kaydediyor = false;
  List<Map<String, dynamic>> _cakismalar = const [];

  bool get _cokMagaza => _cokMagazaRolleri.contains(session.user?.role ?? '');

  String get _from => _haftalik ? _iso(_anchor) : _gun;
  String get _to =>
      _haftalik ? _iso(_anchor.add(const Duration(days: 6))) : _gun;

  @override
  void initState() {
    super.initState();
    _load();
    if (_cokMagaza) {
      repo
          .stores(silent: true)
          .then((m) {
            if (mounted) setState(() => _magazalar = m);
          })
          .onError((Object _, StackTrace _) {});
    }
  }

  Future<void> _hucreDuzenle(RosterPerson kisi, String gun) async {
    if (_vardiyalar.isEmpty) {
      try {
        _vardiyalar = (await repo.pdksShifts()).where((v) => v.active).toList();
      } catch (e) {
        if (mounted) toast(errorMessage(e), kind: ToastKind.error);
        return;
      }
    }
    if (!mounted) return;
    final anahtar = PendingCell.keyOf(kisi.userId, gun);
    final secim = await showRosterCellDialog(
      context,
      kisi: kisi,
      gun: gun,
      vardiyalar: _vardiyalar,
      bekleyen: _bekleyen[anahtar],
    );
    if (secim == null || !mounted) return;

    final mevcut = kisi.gun(gun);
    final suAnkiTatil = mevcut.any((c) => c.isDayOff);
    final suAnkiId = mevcut
        .where((c) => !c.isDayOff)
        .map((c) => c.shiftId)
        .firstOrNull;
    final ayni = secim.isDayOff
        ? suAnkiTatil
        : (secim.shiftId == suAnkiId && !suAnkiTatil);

    setState(() {
      _cakismalar = const [];
      if (ayni) {
        _bekleyen.remove(anahtar);
      } else {
        _bekleyen[anahtar] = PendingCell(
          userId: kisi.userId,
          fullName: kisi.fullName,
          workDate: gun,
          isDayOff: secim.isDayOff,
          shift: secim.shift,
        );
      }
    });
  }

  Future<void> _kaydet({bool force = false}) async {
    if (_bekleyen.isEmpty) return;
    setState(() {
      _kaydediyor = true;
      _cakismalar = const [];
    });
    try {
      final sonuc = await repo.pdksSaveCells(
        changes: _bekleyen.values.map((b) => b.toJson()).toList(),
        force: force,
      );
      final kayitli = (sonuc['saved'] as num?)?.toInt() ?? 0;
      final zorlanan = (sonuc['forced'] as num?)?.toInt() ?? 0;
      if (mounted) {
        toastSaved(
          '$kayitli değişiklik kaydedildi'
          '${zorlanan > 0 ? ' ($zorlanan tanesi çakışmaya rağmen)' : ''}',
        );
        setState(_bekleyen.clear);
      }
      await _load(silent: true);
    } on DioException catch (e) {
      final veri = e.response?.data;
      if (e.response?.statusCode == 409 &&
          veri is Map &&
          veri['code'] == 'SHIFT_CONFLICT') {
        if (mounted) {
          setState(() {
            _cakismalar = ((veri['conflicts'] as List<dynamic>?) ?? [])
                .map((x) => (x as Map).cast<String, dynamic>())
                .toList();
          });
          toast(
            veri['error'] as String? ?? 'Çakışma var',
            kind: ToastKind.error,
          );
        }
      } else if (mounted) {
        toast(errorMessage(e), kind: ToastKind.error);
      }
    } catch (e) {
      if (mounted) toast(errorMessage(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _kaydediyor = false);
    }
  }

  void _bekleyeniKaldir(String anahtar) {
    setState(() {
      _bekleyen.remove(anahtar);
      _cakismalar = const [];
    });
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final r = await repo.pdksRoster(
        from: _from,
        to: _to,
        storeId: _storeId,
        silent: silent,
      );
      if (!mounted) return;
      setState(() {
        _veri = r;
        _error = '';
        _loaded = true;
      });
      _loadNotlar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _veri = null;
        _error = errorMessage(e);
        _loaded = true;
      });
    }
  }

  /// Notlarin magazasi: secili magaza ya da kullanicinin kendi magazasi.
  int? get _notMagaza => _storeId ?? session.user?.storeId;

  Future<void> _loadNotlar() async {
    if (!_haftalik || _notMagaza == null) {
      if (_notlar.isNotEmpty && mounted) setState(() => _notlar = const []);
      return;
    }
    try {
      final n = await repo.rosterNotes(from: _from, storeId: _storeId);
      if (mounted) setState(() => _notlar = n);
    } catch (_) {
      // Notlar ikincil: gelmezse cizelge yine gorunur.
    }
  }

  Future<void> _notYaz([RosterNote? not]) async {
    final ctrl = TextEditingController(text: not?.body ?? '');
    final ok = await showAppSheet<bool>(
      context: context,
      builder: (ctx) => FormDialog(
        title: not == null ? 'Plan Notu Ekle' : 'Notu Düzenle',
        headerIcon: Icons.sticky_note_2_outlined,
        submitLabel: 'Kaydet',
        fields: (context, rebuild) => [
          LabeledField(
            label: 'Not',
            hint: 'Not silinene kadar her haftanın planı altında görünür ve PDF\'e eklenir.',
            child: TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 4,
              maxLength: 1000,
              style: const TextStyle(fontSize: AppFontSize.title),
            ),
          ),
        ],
        onSubmit: () async {
          final text = ctrl.text.trim();
          if (text.isEmpty) return 'Not boş olamaz';
          try {
            if (not == null) {
              await repo.addRosterNote(
                from: _from,
                body: text,
                storeId: _storeId,
              );
            } else {
              await repo.updateRosterNote(not.id, text);
            }
            return null;
          } catch (e) {
            return errorMessage(e);
          }
        },
      ),
    );
    if (ok == true) {
      toastSaved(not == null ? 'Not eklendi' : 'Not güncellendi');
      await _loadNotlar();
    }
  }

  Future<void> _notSil(RosterNote not) async {
    final ok = await confirmDialog(
      context,
      title: 'Notu Sil',
      confirmLabel: 'Sil',
      body: Text(not.body),
    );
    if (ok != true) return;
    try {
      await repo.deleteRosterNote(not.id);
    } catch (_) {
      return;
    }
    await _loadNotlar();
  }

  Future<void> _kaydir(int yon) async {
    if (_bekleyen.isNotEmpty) {
      final devam = await confirmDialog(
        context,
        title: 'Kaydedilmemiş değişiklik',
        body: Text(
          '${_bekleyen.length} değişiklik kaydedilmedi. '
          'Hafta değiştirirseniz kaybolur.',
        ),
        confirmLabel: 'Devam et',
      );
      if (devam != true || !mounted) return;
      setState(() {
        _bekleyen.clear();
        _cakismalar = const [];
      });
    }
    setState(() {
      if (_haftalik) {
        _anchor = _anchor.add(Duration(days: 7 * yon));
      } else {
        _gun = _iso(
          DateTime.parse('${_gun}T00:00:00').add(Duration(days: yon)),
        );
      }
    });
    _load(silent: true);
  }

  Future<void> _paylas() async {
    final v = _veri;
    if (v == null || v.people.isEmpty) {
      toast('Paylaşılacak plan yok', kind: ToastKind.error);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Planı ekiple paylaş',
      confirmLabel: 'Paylaş',
      body: Text(
        '${fmtDate(v.from)} – ${fmtDate(v.to)} haftasının planı ekibe '
        'bildirilecek. Herkes kendi vardiyalarının özetini bildirim olarak '
        'alacak.',
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _paylasiyor = true);
    try {
      final adet = await repo.pdksPublishRoster(from: v.from, to: v.to);
      toastSaved('Plan $adet kişiyle paylaşıldı');
    } catch (e) {
      toast(errorMessage(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _paylasiyor = false);
    }
  }

  Future<void> _pdf() async {
    final v = _veri;
    if (v == null || v.people.isEmpty) {
      toast('Dışa aktarılacak kayıt yok', kind: ToastKind.error);
      return;
    }
    setState(() => _disa = true);
    try {
      await exportRosterPdf(v, notes: [for (final n in _notlar) n.body]);
    } catch (e) {
      toast('Dışa aktarılamadı', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _disa = false);
    }
  }

  /// Paylaşım, düzenleme ve dışa aktarma yalnızca mağaza müdürüne açık.
  bool get _magazaMuduru => session.user?.role == 'store_manager';

  @override
  Widget build(BuildContext context) {
    final v = _veri;
    final t = context.tokens;

    final dateRangeLabel = _haftalik
        ? '${fmtDate(_from)} - ${fmtDate(_to)}'
        : '${fmtDate(_gun)} ${_gunAdi(_gun, uzun: true)}';

    return CrudScaffold(
      title: 'Vardiya Çizelgesi',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      emptyText: '',
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 2. Segmented Toggle Control: Zaman Çizelgesi vs Haftalık Matris
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (_haftalik) {
                        setState(() => _haftalik = false);
                        _load(silent: true);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_haftalik ? t.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: !_haftalik
                            ? [
                                BoxShadow(
                                  color: t.primary.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_view_day_rounded,
                            size: 18,
                            color: !_haftalik ? t.onPrimary : t.muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Zaman Çizelgesi',
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w600,
                              color: !_haftalik ? t.onPrimary : t.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (!_haftalik) {
                        setState(() => _haftalik = true);
                        _load(silent: true);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _haftalik ? t.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _haftalik
                            ? [
                                BoxShadow(
                                  color: t.primary.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.view_comfy_rounded,
                            size: 18,
                            color: _haftalik ? t.onPrimary : t.muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Haftalık Matris',
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w600,
                              color: _haftalik ? t.onPrimary : t.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Hafta Kaydırma Satırı
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => _kaydir(-1),
                icon: const Icon(Icons.chevron_left_rounded, size: 24),
                tooltip: 'Önceki',
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  dateRangeLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSize.body,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _kaydir(1),
                icon: const Icon(Icons.chevron_right_rounded, size: 24),
                tooltip: 'Sonraki',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Cok magazali rollerde magaza secici.
          if (_cokMagaza && _magazalar.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: context.tokens.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.tokens.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _storeId,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, size: 18),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text(
                          'Tüm Mağazalar',
                          style: TextStyle(fontSize: AppFontSize.caption),
                        ),
                      ),
                      for (final m in _magazalar)
                        DropdownMenuItem(
                          value: m.id,
                          child: Text(
                            m.name,
                            style: const TextStyle(
                              fontSize: AppFontSize.caption,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      setState(() => _storeId = id);
                      _load(silent: true);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 4. Quick KPI Metric Bar: Toplam, Ortalama, Açık Vardiya, Değişim/İzin
          if (v != null) _KpiMetricBar(veri: v),
          const SizedBox(height: 10),

          // Çakışma paneli
          if (_cakismalar.isNotEmpty) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_cakismalar.length} hücrede çakışma var; '
                    'hiçbir değişiklik kaydedilmedi.',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: context.tokens.danger,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final c in _cakismalar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${c['full_name']} — ${fmtDate(c['work_date'] as String? ?? '')}'
                              ': ${c['label']}',
                              style: const TextStyle(
                                fontSize: AppFontSize.body,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _bekleyeniKaldir(
                              PendingCell.keyOf(
                                (c['user_id'] as num).toInt(),
                                c['work_date'] as String,
                              ),
                            ),
                            child: const Text('geri al'),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    'Yine de kaydederseniz çakışan atamalar hareket '
                    'kayıtlarına "çakışmaya rağmen atandı" olarak yazılır.',
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: context.tokens.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => setState(() => _cakismalar = const []),
                        child: const Text('Kapat'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _kaydediyor
                            ? null
                            : () => _kaydet(force: true),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.tokens.dangerStrong,
                        ),
                        child: const Text('Yine de kaydet'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
      children: [
        if (v != null && v.people.isNotEmpty) ...[
          if (_haftalik)
            _HaftaTablosu(
              veri: v,
              bekleyen: _bekleyen,
              onHucre: v.canEdit ? _hucreDuzenle : null,
            )
          else
            _GunListesi(veri: v, gun: _gun),

          const SizedBox(height: 12),

          // Plan notlari: herkes okur, yonetici ekler; kayit soldan saga
          // kaydirilinca Duzenle / Sil acilir.
          if (_haftalik) ...[
            _NotlarKarti(
              notlar: _notlar,
              magazaSecili: _notMagaza != null,
              duzenlenebilir: v.canEdit,
              onEkle: () => _notYaz(),
              onDuzenle: _notYaz,
              onSil: _notSil,
            ),
            const SizedBox(height: 12),
          ],

          // Ekiple Paylas + PDF Indir (yalnizca magaza muduru).
          if (_magazaMuduru)
            _BottomActions(
              paylasiyor: _paylasiyor,
              disaAktariyor: _disa,
              bekleyenVar: _bekleyen.isNotEmpty,
              onPaylas: _paylas,
              onPdf: _pdf,
            ),
          const SizedBox(height: 8),
        ],

        // Kaydet Çubuğu
        if (_bekleyen.isNotEmpty) ...[
          const SizedBox(height: 8),
          _KaydetCubugu(
            adet: _bekleyen.length,
            kaydediyor: _kaydediyor,
            onKaydet: () => _kaydet(),
            onVazgec: () async {
              final ok = await confirmDialog(
                context,
                title: 'Değişiklikleri geri al',
                body: Text('${_bekleyen.length} değişiklik geri alınacak.'),
                confirmLabel: 'Geri al',
              );
              if (ok == true && mounted) {
                setState(() {
                  _bekleyen.clear();
                  _cakismalar = const [];
                });
              }
            },
          ),
        ],
      ],
    );
  }
}

/// 4-Kolon KPI Metrik Çubuğu: Toplam, Ortalama, Açık Vardiya, Değişim/İzin
class _KpiMetricBar extends StatelessWidget {
  const _KpiMetricBar({required this.veri});

  final Roster veri;

  @override
  Widget build(BuildContext context) {
    final totalHours = (veri.totalPlannedMinutes / 60).toStringAsFixed(0);
    final avgHours = veri.people.isEmpty
        ? '0.0'
        : (veri.totalPlannedMinutes / veri.people.length / 60).toStringAsFixed(
            1,
          );

    var unassignedCount = 0;
    var dayOffCount = 0;
    for (final p in veri.people) {
      for (final d in veri.dates) {
        final cells = p.gun(d);
        if (cells.isEmpty) {
          unassignedCount++;
        } else if (cells.any((c) => c.isDayOff)) {
          dayOffCount++;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: context.tokens.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.tokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _KpiCol(
              baslik: 'Toplam',
              deger: '${totalHours}s',
              degerRenk: context.tokens.primary,
              alt: 'Hedef %100',
              altRenk: context.tokens.okText,
            ),
          ),
          _divider(context),
          Expanded(
            child: _KpiCol(
              baslik: 'Ortalama',
              deger: '${avgHours}s',
              degerRenk: context.tokens.ink,
              alt: 'Kişi başı',
              altRenk: context.tokens.muted,
            ),
          ),
          _divider(context),
          Expanded(
            child: _KpiCol(
              baslik: 'Açık Vardiya',
              deger: '$unassignedCount',
              degerRenk: unassignedCount == 0
                  ? context.tokens.okText
                  : context.tokens.danger,
              alt: unassignedCount == 0 ? 'Eksiksiz' : '$unassignedCount Boş',
              altRenk: unassignedCount == 0
                  ? context.tokens.okText
                  : context.tokens.danger,
            ),
          ),
          _divider(context),
          Expanded(
            child: _KpiCol(
              baslik: 'Değişim/İzin',
              deger: '$dayOffCount',
              degerRenk: context.tokens.success,
              alt: 'Onaylı',
              altRenk: context.tokens.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Container(width: 1, height: 32, color: context.tokens.border);
}

class _KpiCol extends StatelessWidget {
  const _KpiCol({
    required this.baslik,
    required this.deger,
    required this.degerRenk,
    required this.alt,
    required this.altRenk,
  });

  final String baslik;
  final String deger;
  final Color degerRenk;
  final String alt;
  final Color altRenk;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          baslik,
          style: TextStyle(
            fontSize: AppFontSize.micro,
            fontWeight: FontWeight.w500,
            color: context.tokens.muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          deger,
          style: TextStyle(
            fontSize: AppFontSize.title,
            fontWeight: FontWeight.w800,
            color: degerRenk,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          alt,
          style: TextStyle(
            fontSize: AppFontSize.micro,
            fontWeight: FontWeight.w600,
            color: altRenk,
          ),
        ),
      ],
    );
  }
}

/// Kisinin planli NET suresi; bekleyen degisiklikler DAHIL.
int _planliSure(
  RosterPerson kisi,
  List<String> gunler,
  Map<String, PendingCell> bekleyen,
) {
  var toplam = 0;
  for (final d in gunler) {
    final b = bekleyen[PendingCell.keyOf(kisi.userId, d)];
    if (b != null) {
      toplam += b.netMinutes;
    } else {
      toplam += kisi.gun(d).fold(0, (a, c) => a + c.minutes);
    }
  }
  return toplam;
}

class _HaftaTablosu extends StatelessWidget {
  const _HaftaTablosu({
    required this.veri,
    this.bekleyen = const {},
    this.onHucre,
  });

  final Roster veri;
  final Map<String, PendingCell> bekleyen;
  final void Function(RosterPerson kisi, String gun)? onHucre;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Gün kolonları + Planlı toplam kolonu
    final colWidths = <int, TableColumnWidth>{0: const FixedColumnWidth(165)};
    for (var i = 1; i <= veri.dates.length; i++) {
      colWidths[i] = const FixedColumnWidth(78);
    }
    colWidths[veri.dates.length + 1] = const FixedColumnWidth(72);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tablo başlığı & "Görünümü Sabitle"
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Haftalık Personel Matrisi',
                    style: TextStyle(
                      fontSize: AppFontSize.title,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: context.tokens.success,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${veri.people.length}',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: FontWeight.w700,
                        color: context.tokens.foregroundOn(
                          context.tokens.success,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    'Görünümü Sabitle',
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w600,
                      color: context.tokens.primary,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(
                    Icons.push_pin_outlined,
                    size: 14,
                    color: context.tokens.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Matris Kartı & Yatay Kaydırma
        Container(
          decoration: BoxDecoration(
            color: context.tokens.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.tokens.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const FixedColumnWidth(78),
              columnWidths: colWidths,
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                // 1. Başlık Satırı
                TableRow(
                  decoration: BoxDecoration(color: context.tokens.bg),
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      child: Text(
                        'Personel & Rol',
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w800,
                          color: context.tokens.ink,
                        ),
                      ),
                    ),
                    for (final d in veri.dates)
                      _TarihBasligi(
                        gunAdi: _gunAdi(d),
                        tarih: '${d.substring(8)}.${d.substring(5, 7)}',
                        tatil: veri.holidays[d] != null,
                        haftaSonu:
                            d == veri.dates.last ||
                            (veri.dates.length >= 2 &&
                                d == veri.dates[veri.dates.length - 2]),
                      ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Planlı',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          fontWeight: FontWeight.w800,
                          color: context.tokens.muted,
                        ),
                      ),
                    ),
                  ],
                ),

                // 2. Personel Satırları
                for (var i = 0; i < veri.people.length; i++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: i.isEven
                          ? Colors.transparent
                          : (context.tokens.bg),
                      border: Border(
                        bottom: BorderSide(
                          color: context.tokens.border,
                          width: 0.5,
                        ),
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 6,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _avatarBg(veri.people[i].role, t),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _initials(veri.people[i].fullName),
                                style: TextStyle(
                                  color: t.foregroundOn(
                                    _avatarBg(veri.people[i].role, t),
                                  ),
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    veri.people[i].fullName,
                                    style: const TextStyle(
                                      fontSize: AppFontSize.caption,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatRole(veri.people[i].role),
                                    style: TextStyle(
                                      fontSize: AppFontSize.micro,
                                      color: t.muted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final d in veri.dates)
                        _Hucre(
                          hucreler: veri.people[i].gun(d),
                          tatil: veri.holidays[d],
                          bekleyen:
                              bekleyen[PendingCell.keyOf(
                                veri.people[i].userId,
                                d,
                              )],
                          onTap: onHucre == null
                              ? null
                              : () => onHucre!(veri.people[i], d),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Text(
                          fmtDuration(
                            _planliSure(veri.people[i], veri.dates, bekleyen),
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: AppFontSize.caption,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),

                // 3. Alt Kadro Gücü / Çalışan Sayısı Satırı
                TableRow(
                  decoration: BoxDecoration(
                    color: context.tokens.border.withValues(alpha: 0.6),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.engineering_outlined,
                            size: 18,
                            color: t.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Kadro Gücü',
                                  style: TextStyle(
                                    fontSize: AppFontSize.caption,
                                    fontWeight: FontWeight.w800,
                                    color: t.ink,
                                  ),
                                ),
                                Text(
                                  'Çalışan sayısı',
                                  style: TextStyle(
                                    fontSize: AppFontSize.micro,
                                    fontWeight: FontWeight.w600,
                                    color: t.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final d in veri.dates)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 3,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.tokens.card,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${veri.gunToplam(d).working} Kişi',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: AppFontSize.caption,
                                  fontWeight: FontWeight.w800,
                                  color: context.tokens.primary,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                rosterStaffingLabel(veri.gunToplam(d).working),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: AppFontSize.micro,
                                  fontWeight: FontWeight.w600,
                                  color: context.tokens.okText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                        fmtDuration(veri.totalPlannedMinutes),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w800,
                          color: context.tokens.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TarihBasligi extends StatelessWidget {
  const _TarihBasligi({
    required this.gunAdi,
    required this.tarih,
    required this.tatil,
    required this.haftaSonu,
  });

  final String gunAdi;
  final String tarih;
  final bool tatil;
  final bool haftaSonu;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final primaryColor = t.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            gunAdi,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontWeight: FontWeight.w700,
              color: tatil ? t.danger : (haftaSonu ? primaryColor : t.ink),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            tarih,
            style: TextStyle(
              fontSize: AppFontSize.micro,
              fontWeight: haftaSonu ? FontWeight.w600 : FontWeight.w400,
              color: tatil ? t.danger : (haftaSonu ? primaryColor : t.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hucre extends StatelessWidget {
  const _Hucre({required this.hucreler, this.tatil, this.bekleyen, this.onTap});

  final List<RosterCell> hucreler;
  final PublicHoliday? tatil;
  final PendingCell? bekleyen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tamTatil = tatil != null && !tatil!.isHalfDay;

    final gosterilen = bekleyen == null
        ? hucreler
        : bekleyen!.isDayOff
        ? const [RosterCell(isDayOff: true)]
        : bekleyen!.shift == null
        ? const <RosterCell>[]
        : [
            RosterCell(
              shiftId: bekleyen!.shift!.id,
              shiftName: bekleyen!.shift!.name,
              startTime: bekleyen!.shift!.startTime,
              endTime: bekleyen!.shift!.endTime,
              breakDurationMinutes: bekleyen!.shift!.breakMinutes,
              minutes: bekleyen!.shift!.netMinutes,
              spanMinutes: bekleyen!.shift!.spanMinutes,
              crossesMidnight:
                  bekleyen!.shift!.endTime.compareTo(
                    bekleyen!.shift!.startTime,
                  ) <=
                  0,
            ),
          ];
    final uyarilar = gosterilen.expand((c) => c.warnings).toList();

    Widget govde;
    if (tamTatil) {
      govde = Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        decoration: BoxDecoration(
          color: context.tokens.dangerSoft,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'RT',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.label,
                fontWeight: FontWeight.w800,
                color: t.danger,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Tatil',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFontSize.micro,
                  fontWeight: FontWeight.w600,
                  color: t.danger,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (gosterilen.isEmpty) {
      govde = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          onTap != null ? '+' : '-',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppFontSize.bodyLarge,
            fontWeight: FontWeight.w700,
            color: t.borderStrong,
          ),
        ),
      );
    } else if (gosterilen.any((c) => c.isDayOff)) {
      final rapor = gosterilen.any((c) => c.isRapor);
      govde = Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        decoration: BoxDecoration(
          color: context.tokens.dangerSoft.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rapor ? 'RAPOR' : 'OFF',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.caption,
                fontWeight: FontWeight.w800,
                color: context.tokens.dangerText,
              ),
            ),
            SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                rapor ? 'Raporlu' : 'Hafta Tatili',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFontSize.micro,
                  fontWeight: FontWeight.w600,
                  color: context.tokens.dangerText,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      govde = Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final c in gosterilen) _VardiyaEtiketi(hucre: c)],
      );
    }

    final icerik = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        govde,
        if (bekleyen != null)
          Text(
            '•',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1,
              fontSize: AppFontSize.bodyLarge,
              fontWeight: FontWeight.w900,
              color: t.primary600,
            ),
          ),
        if (uyarilar.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              uyarilar.first.etiket,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.micro,
                fontWeight: FontWeight.w800,
                color: t.danger,
              ),
            ),
          ),
      ],
    );

    final kutu = Container(
      decoration: bekleyen != null
          ? BoxDecoration(
              border: Border.all(color: t.primary600, width: 2),
              borderRadius: BorderRadius.circular(8),
            )
          : uyarilar.isEmpty
          ? null
          : BoxDecoration(
              border: Border.all(color: t.danger, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: icerik,
    );

    if (onTap == null || tamTatil) {
      return Tooltip(
        message: tamTatil
            ? (tatil!.name)
            : uyarilar.map((u) => u.aciklama ?? u.etiket).join('\n'),
        triggerMode: uyarilar.isEmpty && !tamTatil
            ? TooltipTriggerMode.manual
            : TooltipTriggerMode.longPress,
        child: kutu,
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: kutu,
    );
  }
}

/// Tek vardiya etiketi: saat + kategori adı, modern renkler ile.
class _VardiyaEtiketi extends StatelessWidget {
  const _VardiyaEtiketi({required this.hucre});

  final RosterCell hucre;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final st = _kategoriStili(hucre.category, t);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: hucre.crossesMidnight ? context.tokens.ink : st.zemin,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hucre.saatAraligi,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.micro,
              fontWeight: FontWeight.w700,
              color: hucre.crossesMidnight ? context.tokens.card : st.metin,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (st.etiket.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              st.etiket,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.micro,
                fontWeight: FontWeight.w700,
                color: hucre.crossesMidnight
                    ? context.tokens.card.withValues(alpha: 0.85)
                    : st.metin,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.paylasiyor,
    required this.disaAktariyor,
    required this.bekleyenVar,
    required this.onPaylas,
    required this.onPdf,
  });

  final bool paylasiyor;
  final bool disaAktariyor;
  final bool bekleyenVar;
  final VoidCallback onPaylas;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: (paylasiyor || bekleyenVar) ? null : onPaylas,
                icon: Icon(
                  paylasiyor ? Icons.hourglass_top : Icons.groups_outlined,
                  size: 20,
                ),
                label: Text(paylasiyor ? 'Paylaşılıyor...' : 'Ekiple Paylaş'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: disaAktariyor ? null : onPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                label: Text(disaAktariyor ? 'Hazırlanıyor...' : 'PDF İndir'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
        if (bekleyenVar)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Paylaşmadan önce değişiklikleri kaydedin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSize.label,
                color: context.tokens.muted,
              ),
            ),
          ),
      ],
    );
  }
}

/// Haftalik plan notlari karti.
class _NotlarKarti extends StatelessWidget {
  const _NotlarKarti({
    required this.notlar,
    required this.magazaSecili,
    required this.duzenlenebilir,
    required this.onEkle,
    required this.onDuzenle,
    required this.onSil,
  });

  final List<RosterNote> notlar;
  final bool magazaSecili;
  final bool duzenlenebilir;
  final VoidCallback onEkle;
  final ValueChanged<RosterNote> onDuzenle;
  final ValueChanged<RosterNote> onSil;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.sticky_note_2_outlined, size: 20, color: t.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Plan Notları',
                  style: TextStyle(
                    fontSize: AppFontSize.bodyLarge,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
              if (duzenlenebilir && magazaSecili)
                TextButton.icon(
                  onPressed: onEkle,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Not Ekle'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (!magazaSecili)
            Text(
              'Notları görmek için bir mağaza seçin.',
              style: TextStyle(fontSize: AppFontSize.body, color: t.muted),
            )
          else if (notlar.isEmpty)
            Text(
              'Henüz plan notu yok.',
              style: TextStyle(fontSize: AppFontSize.body, color: t.muted),
            )
          else
            for (final n in notlar)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SwipeActions(
                  actions: [
                    if (duzenlenebilir) ...[
                      SwipeAction(
                        label: 'Düzenle',
                        icon: Icons.edit_outlined,
                        color: t.primary,
                        onTap: () => onDuzenle(n),
                      ),
                      SwipeAction(
                        label: 'Sil',
                        icon: Icons.delete_outline,
                        color: t.danger,
                        onTap: () => onSil(n),
                      ),
                    ],
                  ],
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.bg,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: t.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.body,
                          style: TextStyle(
                            fontSize: AppFontSize.body,
                            color: t.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            n.createdByName ?? 'bilinmiyor',
                            if (n.createdAt != null) fmtDateTime(n.createdAt),
                            if (n.updatedAt != null) 'düzenlendi',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: AppFontSize.caption,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Zaman Çizelgesi (Günlük Görünüm)
class _GunListesi extends StatelessWidget {
  const _GunListesi({required this.veri, required this.gun});

  final Roster veri;
  final String gun;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tatil = veri.holidays[gun];
    final calisan = veri.people
        .where((p) => p.gun(gun).any((c) => !c.isDayOff))
        .toList();
    final tatilde = veri.people
        .where((p) => p.gun(gun).any((c) => c.isDayOff))
        .toList();
    final bos = veri.people.where((p) => p.gun(gun).isEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tatil != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.gap),
            child: AppCard(
              child: Text(
                '${tatil.name}${tatil.isHalfDay ? ' (yarım gün)' : ''} — resmi tatil.',
                style: TextStyle(fontWeight: FontWeight.w700, color: t.danger),
              ),
            ),
          ),
        AppCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Sayi(etiket: 'Çalışan', deger: '${calisan.length}'),
              _Sayi(etiket: 'Hafta tatili', deger: '${tatilde.length}'),
              _Sayi(etiket: 'Atanmamış', deger: '${bos.length}'),
              _Sayi(
                etiket: 'Planlı',
                deger: fmtDuration(veri.gunToplam(gun).minutes),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.gap),
        if (calisan.isEmpty)
          AppCard(
            child: Text(
              'Bu gün çalışan personel yok.',
              style: TextStyle(color: t.muted),
            ),
          ),
        for (final p in calisan)
          for (final c in p.gun(gun).where((x) => !x.isDayOff))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _avatarBg(p.role, t),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initials(p.fullName),
                        style: TextStyle(
                          color: t.foregroundOn(_avatarBg(p.role, t)),
                          fontSize: AppFontSize.label,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${c.shiftName ?? '-'} · ${c.saatAraligi}'
                            '${c.breakDurationMinutes > 0 ? ' · ${c.breakDurationMinutes} dk mola' : ''}',
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              color: t.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (c.crossesMidnight)
                      Pill(text: 'kapanış', color: t.warning),
                    const SizedBox(width: 6),
                    Text(
                      fmtDuration(c.minutes),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
        if (tatilde.isNotEmpty || bos.isNotEmpty) ...[
          const SizedBox(height: 4),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tatilde.isNotEmpty)
                  Text(
                    'Hafta tatili: ${tatilde.map((p) => p.fullName).join(', ')}',
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: t.muted,
                    ),
                  ),
                if (bos.isNotEmpty) ...[
                  if (tatilde.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    'Vardiya atanmamış: ${bos.map((p) => p.fullName).join(', ')}',
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: t.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Sayi extends StatelessWidget {
  const _Sayi({required this.etiket, required this.deger});

  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Text(
          etiket,
          style: TextStyle(fontSize: AppFontSize.caption, color: t.muted),
        ),
        const SizedBox(height: 2),
        Text(deger, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

/// Hücre seçim sonucu.
typedef CellChoice = ({bool isDayOff, int? shiftId, ShiftDef? shift});

/// Tek hücre seçimi diyaloğu: Bir personelin bir günü.
Future<CellChoice?> showRosterCellDialog(
  BuildContext context, {
  required RosterPerson kisi,
  required String gun,
  required List<ShiftDef> vardiyalar,
  PendingCell? bekleyen,
}) async {
  final mevcut = kisi.gun(gun);
  final tatilVar = mevcut.any((c) => c.isDayOff);
  final mevcutId = mevcut
      .where((c) => !c.isDayOff)
      .map((c) => c.shiftId)
      .firstOrNull;
  int? secim = bekleyen != null
      ? (bekleyen.isDayOff ? -1 : bekleyen.shiftId)
      : (tatilVar ? -1 : mevcutId);

  CellChoice? sonuc;
  final onaylandi = await showAppSheet<bool>(
    context: context,
    builder: (ctx) => FormDialog(
      title: '${kisi.fullName} — ${fmtDate(gun)} ${_gunAdi(gun, uzun: true)}',
      submitLabel: 'Tabloya işle',
      fields: (context, rebuild) {
        final t = context.tokens;
        Widget secenek({
          required int? deger,
          required String baslik,
          required String alt,
          String? uyari,
        }) {
          final secili = secim == deger;
          return InkWell(
            onTap: () {
              secim = deger;
              rebuild();
            },
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              constraints: const BoxConstraints(minHeight: AppTokens.tap),
              decoration: BoxDecoration(
                color: secili ? t.primarySoft : null,
                border: Border.all(
                  color: secili ? t.primary600 : t.borderStrong,
                  width: secili ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Row(
                children: [
                  Icon(
                    secili
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: secili ? t.primary600 : t.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          baslik,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          alt,
                          style: TextStyle(
                            fontSize: AppFontSize.label,
                            color: t.muted,
                          ),
                        ),
                        if (uyari != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            uyari,
                            style: TextStyle(
                              fontSize: AppFontSize.label,
                              fontWeight: FontWeight.w700,
                              color: t.danger,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return [
          for (final v in vardiyalar)
            secenek(
              deger: v.id,
              baslik: v.name,
              alt:
                  '${v.saatAraligi} · net ${fmtDuration(v.netMinutes)}'
                  '${v.breakMinutes > 0 ? ' · ${v.breakMinutes} dk mola' : ''}',
              uyari: v.warning,
            ),
          secenek(
            deger: -1,
            baslik: 'Hafta tatili',
            alt: 'Planlı süre sayılmaz',
          ),
          secenek(deger: null, baslik: 'Boş bırak', alt: 'Atama silinir'),
        ];
      },
      onSubmit: () async {
        sonuc = (
          isDayOff: secim == -1,
          shiftId: (secim == null || secim == -1) ? null : secim,
          shift: (secim == null || secim == -1)
              ? null
              : vardiyalar.where((v) => v.id == secim).firstOrNull,
        );
        return null;
      },
    ),
  );
  return onaylandi == true ? sonuc : null;
}

/// Bekleyen değişiklik sayısını ve kaydet/vazgeç düğmelerini gösteren çubuk.
class _KaydetCubugu extends StatelessWidget {
  const _KaydetCubugu({
    required this.adet,
    required this.kaydediyor,
    required this.onKaydet,
    required this.onVazgec,
  });

  final int adet;
  final bool kaydediyor;
  final VoidCallback onKaydet;
  final VoidCallback onVazgec;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.primarySoft,
        border: Border.all(color: t.primary600),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        children: [
          Icon(Icons.save_outlined, size: 18, color: t.primary600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$adet değişiklik kaydedilmeyi bekliyor',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          OutlinedButton(
            onPressed: kaydediyor ? null : onVazgec,
            child: const Text('Vazgeç'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: kaydediyor ? null : onKaydet,
            child: Text(kaydediyor ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
      ),
    );
  }
}
