import 'package:dio/dio.dart';
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
import '../widgets/dialogs.dart';
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

/// Kategori renkleri ve etiketleri.
///
/// Renk TEK BASINA bilgi tasimasin diye her hucrede kategori etiketi de
/// yaziliyor: renk korlugunde ve yazdirmada renk tek ayirt edici olamaz.
/// React tarafindaki .k-* siniflariyla ayni tonlar; kontrast olculdu
/// (kucuk metin esigi 4.5): sabah 5.57/7.83, gunduz 4.79/7.65,
/// aksam 4.84/7.95, gece 7.57/7.08 (acik/koyu).
({Color zemin, Color metin, String etiket}) _kategoriStili(
  ShiftCategory k,
  AppTokens t,
  bool koyu,
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
  // Mor: dort kategori birbirinden ayirt edilebilsin. Koyu temada zemin
  // onceden birlestirilmis kati renk.
  ShiftCategory.gece => (
    zemin: koyu ? const Color(0xFF252946) : const Color(0xFFEDE9FE),
    metin: koyu ? const Color(0xFFC4B5FD) : const Color(0xFF5B21B6),
    etiket: 'Gece',
  ),
  ShiftCategory.bilinmiyor => (
    zemin: Colors.transparent,
    metin: t.ink,
    etiket: '',
  ),
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
  List<ShiftDef> _vardiyalar = const [];
  // Kaydedilmeyi bekleyen hucre degisiklikleri: "kullaniciId|tarih" -> degisiklik.
  final Map<String, PendingCell> _bekleyen = {};
  bool _kaydediyor = false;
  // Sunucudan 409 ile donen cakismalar.
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

  /// Hucre duzenleme penceresini acar, sonucunda cizelgeyi yeniler.
  Future<void> _hucreDuzenle(RosterPerson kisi, String gun) async {
    // Vardiya listesi ilk duzenlemede bir kez cekiliyor; her hucre acilisinda
    // yeniden istemek gereksiz gidis-donus olurdu.
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

    // Secim SUNUCUDAKI haliyle ayniysa bekleyen listesinden cikar:
    // "degistirdim sonra geri aldim" bir degisiklik degil.
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

  /// Bekleyen degisiklikleri TEK istekte kaydeder.
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

  /// Tek bir bekleyen degisikligi geri alir.
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _veri = null;
        _error = errorMessage(e);
        _loaded = true;
      });
    }
  }

  Future<void> _kaydir(int yon) async {
    // Hafta degistirmek bekleyenleri gorunmez kilar; once sorulur.
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
          // Cakisma paneli: sunucu 409 dondugunde sebepleri ve cikis yollarini
          // gosterir. Hicbir degisiklik kaydedilmedigi acikca yaziyor.
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
                              style: const TextStyle(fontSize: 13),
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
                    style: TextStyle(fontSize: 12, color: context.tokens.muted),
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
            const SizedBox(height: AppTokens.gap),
          ],
        ],
      ),
      children: [
        if (v != null && v.people.isNotEmpty)
          _haftalik
              ? _HaftaTablosu(
                  veri: v,
                  bekleyen: _bekleyen,
                  onHucre: v.canEdit ? _hucreDuzenle : null,
                )
              : _GunListesi(veri: v, gun: _gun),
        // Kaydet cubugu listenin SONUNDA: tablo uzun oldugu icin degisiklik
        // yapildiktan sonra dugmeyi aramak zorunda kalmamali.
        if (_bekleyen.isNotEmpty) ...[
          const SizedBox(height: AppTokens.gap),
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

/// Kisinin planli NET suresi; bekleyen degisiklikler DAHIL.
///
/// Kaydetmeden once toplamin degismesi gerekiyor, aksi halde yonetici
/// yaptigi degisikligin saat etkisini kaydetmeden goremez.
int _planliSure(
  RosterPerson kisi,
  List<String> gunler,
  Map<String, PendingCell> bekleyen,
) {
  var toplam = 0;
  for (final d in gunler) {
    final b = bekleyen[PendingCell.keyOf(kisi.userId, d)];
    if (b != null) {
      // Bekleyen degisiklik o gunun mevcut halini TAMAMEN degistiriyor.
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

  /// Kaydedilmeyi bekleyen degisiklikler; hucreler bunlari gosteriyor.
  final Map<String, PendingCell> bekleyen;

  /// Duzenleme yetkisi varsa hucreye dokunma geri cagrisi.
  final void Function(RosterPerson kisi, String gun)? onHucre;

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
                    _Hucre(
                      hucreler: p.gun(d),
                      tatil: veri.holidays[d],
                      bekleyen: bekleyen[PendingCell.keyOf(p.userId, d)],
                      onTap: onHucre == null ? null : () => onHucre!(p, d),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(
                      fmtDuration(_planliSure(p, veri.dates, bekleyen)),
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
  const _Hucre({required this.hucreler, this.tatil, this.bekleyen, this.onTap});

  final List<RosterCell> hucreler;
  final PublicHoliday? tatil;

  /// Kaydedilmemis degisiklik; varsa hucre bunu gosteriyor.
  final PendingCell? bekleyen;

  /// Duzenleme yetkisi olan kullanicilarda hucre dokunulabilir olur.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final koyu = Theme.of(context).brightness == Brightness.dark;
    final tamTatil = tatil != null && !tatil!.isHalfDay;
    // Bekleyen degisiklik varsa hucre ONU gosteriyor: yonetici tabloyu
    // kurarken sonucu gormeli, kaydettikten sonra degil. Kategori ve uyarilar
    // sunucudan gelmiyor (henuz kaydedilmedi).
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
      govde = Text(
        'RT',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: t.danger,
        ),
      );
    } else if (gosterilen.isEmpty) {
      govde = Text(
        onTap != null ? '+' : '-',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: t.borderStrong,
        ),
      );
    } else if (gosterilen.any((c) => c.isDayOff)) {
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
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in gosterilen) _VardiyaEtiketi(hucre: c, koyu: koyu),
        ],
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
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: t.primary600,
            ),
          ),
        // Yasal uyari: renk tek basina yeterli degil, kisa etiket de yaziliyor.
        if (uyarilar.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              uyarilar.first.etiket,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: t.danger,
              ),
            ),
          ),
      ],
    );

    final kutu = Container(
      decoration: bekleyen != null
          // Kaydedilmemis: birincil renkte cerceve. Renk TEK BASINA yeterli
          // degil, o yuzden icerikte nokta isareti de var.
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
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
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
      // Dokunma hedefi: satir yuksekligi zaten 44+ ama hucre genisligi dar,
      // yine de tum hucre dokunulabilir.
      child: kutu,
    );
  }
}

/// Tek vardiya etiketi: saat + kategori adi, kategori rengiyle.
class _VardiyaEtiketi extends StatelessWidget {
  const _VardiyaEtiketi({required this.hucre, required this.koyu});

  final RosterCell hucre;
  final bool koyu;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final st = _kategoriStili(hucre.category, t, koyu);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: st.zemin,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${hucre.saatAraligi}${hucre.crossesMidnight ? ' 🌙' : ''}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: st.metin,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (st.etiket.isNotEmpty)
            Text(
              st.etiket,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: st.metin,
              ),
            ),
        ],
      ),
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

/// Hucre secim sonucu.
typedef CellChoice = ({bool isDayOff, int? shiftId, ShiftDef? shift});

/// Tek hucre secimi: bir personelin bir gunu.
///
/// Sunucuya GITMIYOR. Secim ust bilesende birikiyor ve tum degisiklikler tek
/// "Kaydet" ile gonderiliyor; cakisma kontrolu de o an sunucuda yapiliyor.
/// Kontrolu burada da yapmak iki yerin zamanla ayrismasi demekti.
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
  // null = bos birak, -1 = hafta tatili, digerleri vardiya kimligi.
  // Bekleyen degisiklik varsa ONU gosteriyoruz; yoksa sunucudaki hali.
  int? secim = bekleyen != null
      ? (bekleyen.isDayOff ? -1 : bekleyen.shiftId)
      : (tatilVar ? -1 : mevcutId);

  // Secim BURADA yakalaniyor, onSubmit icinde pop EDILMIYOR.
  //
  // Olculdu: onSubmit icinde Navigator.pop cagrildiginda FormDialog ayni
  // karede mounted'i hala true gorup IKINCI kez pop ediyor ve alttaki ekrani
  // da kapatiyordu. Pop'u FormDialog'a birakip sonucu disarida tutmak bu
  // yarisi ortadan kaldiriyor.
  CellChoice? sonuc;
  final onaylandi = await showDialog<bool>(
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
                          style: TextStyle(fontSize: 12, color: t.muted),
                        ),
                        if (uyari != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            uyari,
                            style: TextStyle(
                              fontSize: 12,
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
      // Kaydetme yok: secim disariya aktariliyor, pencereyi FormDialog kapatiyor.
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

/// Bekleyen degisiklik sayisini ve kaydet/vazgec dugmelerini gosteren cubuk.
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
