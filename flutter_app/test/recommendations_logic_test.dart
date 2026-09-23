import 'package:flutter_test/flutter_test.dart';
import 'package:foodtakip/core/format.dart';
import 'package:foodtakip/models/batch.dart';

Batch _b(String name, String urgency, int remaining, {num? price, String? store}) =>
    Batch.fromJson({
      'id': name.hashCode.abs() % 1000,
      'product_name': name,
      'quantity': remaining,
      'remaining': remaining,
      'status': 'food_cabinet',
      'urgency': urgency,
      'remaining_hours': urgency == 'expired' ? 0 : 53,
      'days_left': 3,
      'product_unit_price': price,
      'store_name': store,
      'skt_end': '2026-09-23T10:00:00.000Z',
    });

/// Ekranda kullanilan suzme ve toplama mantigi.
List<Batch> filtre(List<Batch> items, String search) {
  final q = normalizeSearch(search.trim());
  if (q.isEmpty) return items;
  return items
      .where((b) =>
          normalizeSearch(b.productName).contains(q) ||
          normalizeSearch(b.storeName).contains(q))
      .toList();
}

int topla(Iterable<Batch> list) => list.fold<int>(0, (a, b) => a + b.remaining);

void main() {
  final items = [
    _b('BROWNİE CHEESECAKE', 'expired', 1),
    _b('LATTE PASTA', 'critical', 1),
    _b('YULAFLI ÜZÜMLÜ COOKİE', 'critical', 2),
    _b('DEREOTLU PEYNİRLİ POĞAÇA', 'normal', 3, price: 45),
    _b('ÇİKOLATALI BROWNİE', 'normal', 2, store: 'Merkez Mağaza'),
  ];

  test('Batch esleme fiyati ve aciliyeti okur', () {
    final b = items[3];
    expect(b.productName, 'DEREOTLU PEYNİRLİ POĞAÇA');
    expect(b.hasPrice, isTrue);
    expect(b.productUnitPrice, 45);
    expect(items[0].isExpired, isTrue);
    expect(items[1].hasPrice, isFalse);
  });

  test('arama Turkce karakter yazmadan da bulur', () {
    expect(filtre(items, 'pogaca').single.productName, 'DEREOTLU PEYNİRLİ POĞAÇA');
    expect(filtre(items, 'uzumlu').single.productName, 'YULAFLI ÜZÜMLÜ COOKİE');
    expect(filtre(items, 'cikolata').single.productName, 'ÇİKOLATALI BROWNİE');
    expect(filtre(items, 'merkez').single.productName, 'ÇİKOLATALI BROWNİE');
    expect(filtre(items, '').length, 5);
    expect(filtre(items, 'bulunmayan'), isEmpty);
  });

  test('kademe sayaclari aramaya gore hesaplanir', () {
    final tumu = items;
    final kritik = tumu.where((b) => b.urgency == 'critical' || b.isExpired);
    expect(topla(kritik), 4);
    expect(topla(tumu.where((b) => b.urgency == 'normal')), 5);

    // Arama etkinken sayaclar da suzulmus listeye gore.
    final suzulmus = filtre(tumu, 'cookie');
    expect(topla(suzulmus.where((b) => b.urgency == 'critical')), 2);
    expect(topla(suzulmus.where((b) => b.urgency == 'normal')), 0);
  });

  test('SKT uyarisi aramadan etkilenmez: her zaman tum listeye bakar', () {
    final suzulmus = filtre(items, 'pogaca');
    // Suzulmus listede SKT gecmis urun yok ama uyari tum dolaba bakmali.
    expect(suzulmus.where((b) => b.isExpired), isEmpty);
    expect(topla(items.where((b) => b.isExpired)), 1);
  });
}
