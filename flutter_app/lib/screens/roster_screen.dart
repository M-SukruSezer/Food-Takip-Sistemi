import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/api_client.dart';
import '../core/notify.dart';
import '../core/pdks_export.dart';
import '../core/repository.dart';
import '../core/session.dart';
import '../core/tokens.dart';
import '../models/pdks.dart';
import '../models/dashboard.dart';
import '../widgets/crud_scaffold.dart';
import '../widgets/panels.dart';

// Toplu vardiya cizelgesi: magazanin TUM ekibi bir arada, haftalik ya da
// gunluk. Barista dahil herkes goruyor — kimin ne zaman calistigi ekibin
// gunluk olarak ihtiyac duydugu bilgi. Duzenleme Devam Yonetimi'nde kaliyor.

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

/// Verilen tarihin icinde bulundugu haftanin PAZARTESI'si.
/// Turkiye'de is haftasi pazartesi basliyor.
DateTime _haftaBasi(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

const _cokMagazaRolleri = {
  'super_admin',
  'operations_manager',
  'regional_manager',
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
  List<StoreOption> _magazalar = const [];
  int? _storeId;
  bool _loaded = false;
  String _error = '';
  bool _disa = false;

  bool get _cokMagaza => _cokMagazaRolleri.contains(session.user?.role ?? '');

  String get _from => _haftalik ? _iso(_anchor) : _gun;
  String get _to =>
      _haftalik ? _iso(_anchor.add(const Duration(days: 6))) : _gun;

  @override
  void initState() {
    super.initState();
    _load();
    if (_cokMagaza) {
      // stores() yalnizca erisilebilir magazalari donduruyor; ayri bir aktiflik
      // suzgeci gerekmiyor.
      repo
          .stores(silent: true)
          .then((m) {
            if (mounted) setState(() => _magazalar = m);
          })
          .onError((Object _, StackTrace _) {});
    }
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _veri = null;
        _error = errorMessage(e);
        _loaded = true;
      });
    }
  }

  void _kaydir(int yon) {
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

  Future<void> _pdf() async {
    final v = _veri;
    if (v == null || v.people.isEmpty) {
      toast('Dışa aktarılacak kayıt yok', kind: ToastKind.error);
      return;
    }
    setState(() => _disa = true);
    try {
      await exportRosterPdf(v);
    } catch (e) {
      toast('Dışa aktarılamadı', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _disa = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _veri;
    return CrudScaffold(
      title: 'Vardiya Çizelgesi',
      loaded: _loaded,
      error: _error,
      onRetry: () => _load(),
      onRefresh: () => _load(silent: true),
      emptyText: '',
      // PDF dugmesi CrudScaffold'un ekleme yuvasinda: ayri bir eylem cubugu
      // yuvasi yok ve cizelgede "yeni kayit" islemi zaten bulunmuyor.
      addLabel: v != null && v.canEdit && _haftalik ? 'PDF' : null,
      onAdd: v != null && v.canEdit && _haftalik && !_disa ? _pdf : null,
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filtreler(
            haftalik: _haftalik,
            baslik: _haftalik
                ? '${fmtDate(_from)} – ${fmtDate(_to)}'
                : '${fmtDate(_gun)} ${_gunAdi(_gun, uzun: true)}',
            magazalar: _cokMagaza ? _magazalar : const [],
            storeId: _storeId,
            onMod: (h) {
              setState(() => _haftalik = h);
              _load(silent: true);
            },
            onKaydir: _kaydir,
            onMagaza: (id) {
              setState(() => _storeId = id);
              _load(silent: true);
            },
          ),
          const SizedBox(height: AppTokens.gap),
        ],
      ),
      children: [
        if (v != null && v.people.isNotEmpty)
          _haftalik ? _HaftaTablosu(veri: v) : _GunListesi(veri: v, gun: _gun),
      ],
    );
  }
}

class _Filtreler extends StatelessWidget {
  const _Filtreler({
    required this.haftalik,
    required this.baslik,
    required this.magazalar,
    required this.storeId,
    required this.onMod,
    required this.onKaydir,
    required this.onMagaza,
  });

  final bool haftalik;
  final String baslik;
  final List<StoreOption> magazalar;
  final int? storeId;
  final ValueChanged<bool> onMod;
  final ValueChanged<int> onKaydir;
  final ValueChanged<int?> onMagaza;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Haftalık')),
              ButtonSegment(value: false, label: Text('Günlük')),
            ],
            selected: {haftalik},
            onSelectionChanged: (s) => onMod(s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                onPressed: () => onKaydir(-1),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Önceki',
              ),
              Expanded(
                child: Text(
                  baslik,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: () => onKaydir(1),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Sonraki',
              ),
            ],
          ),
          if (magazalar.isNotEmpty) ...[
            const SizedBox(height: 6),
            DropdownButtonFormField<int?>(
              initialValue: storeId,
              decoration: const InputDecoration(
                labelText: 'Mağaza',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tümü')),
                for (final m in magazalar)
                  DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: onMagaza,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'HT hafta tatili · RT resmi tatil · 🌙 gece vardiyası',
            style: TextStyle(fontSize: 11, color: t.muted),
          ),
        ],
      ),
    );
  }
}

class _HaftaTablosu extends StatelessWidget {
  const _HaftaTablosu({required this.veri});

  final Roster veri;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      // 7 gun + isim telefon genisligine sigmiyor; yatay kaydirma sart.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const FixedColumnWidth(74),
          columnWidths: const {0: FixedColumnWidth(150)},
          border: TableBorder(horizontalInside: BorderSide(color: t.border)),
          children: [
            TableRow(
              children: [
                _Baslik(metin: 'Personel', sola: true),
                for (final d in veri.dates)
                  _Baslik(
                    metin:
                        '${_gunAdi(d)}\n${d.substring(8)}.${d.substring(5, 7)}',
                    tatil: veri.holidays[d] != null,
                  ),
                const _Baslik(metin: 'Planlı'),
              ],
            ),
            for (final p in veri.people)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 9,
                      horizontal: 4,
                    ),
                    child: Text(
                      p.fullName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final d in veri.dates)
                    _Hucre(hucreler: p.gun(d), tatil: veri.holidays[d]),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(
                      fmtDuration(p.plannedMinutes),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 9,
                    horizontal: 4,
                  ),
                  child: Text(
                    'Çalışan sayısı',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t.muted,
                    ),
                  ),
                ),
                for (final d in veri.dates)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(
                      '${veri.gunToplam(d).working}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    fmtDuration(veri.totalPlannedMinutes),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik({required this.metin, this.sola = false, this.tatil = false});

  final String metin;
  final bool sola;
  final bool tatil;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        metin,
        textAlign: sola ? TextAlign.left : TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          // Resmi tatil sutunu: dangerText kucuk yazida 4.5+ kontrast.
          color: tatil ? t.danger : t.muted,
        ),
      ),
    );
  }
}

class _Hucre extends StatelessWidget {
  const _Hucre({required this.hucreler, this.tatil});

  final List<RosterCell> hucreler;
  final PublicHoliday? tatil;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tamTatil = tatil != null && !tatil!.isHalfDay;
    Widget govde;
    if (tamTatil) {
      govde = Text(
        'RT',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: t.danger,
        ),
      );
    } else if (hucreler.isEmpty) {
      govde = Text(
        '-',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: t.border),
      );
    } else if (hucreler.any((c) => c.isDayOff)) {
      govde = Text(
        'HT',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: t.muted,
        ),
      );
    } else {
      govde = Column(
        children: [
          for (final c in hucreler)
            Text(
              '${c.saatAraligi}${c.crossesMidnight ? ' 🌙' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
      child: govde,
    );
  }
}

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
                            style: TextStyle(fontSize: 12, color: t.muted),
                          ),
                        ],
                      ),
                    ),
                    if (c.crossesMidnight) Pill(text: 'gece', color: t.warning),
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
                    style: TextStyle(fontSize: 12, color: t.muted),
                  ),
                if (bos.isNotEmpty) ...[
                  if (tatilde.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    'Vardiya atanmamış: ${bos.map((p) => p.fullName).join(', ')}',
                    style: TextStyle(fontSize: 12, color: t.muted),
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
        Text(etiket, style: TextStyle(fontSize: 11, color: t.muted)),
        const SizedBox(height: 2),
        Text(deger, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
