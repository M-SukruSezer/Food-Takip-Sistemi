import 'api_client.dart';
import 'opts.dart';
import '../models/activity_log.dart';
import '../models/approval.dart';
import '../models/batch.dart';
import '../models/dashboard.dart';
import '../models/movement.dart';
import '../models/petty_cash.dart';
import '../models/product_type.dart';
import '../models/store.dart';
import '../models/user.dart';

/// API cagrilarini tipli hale getirir; ekranlar ham JSON ile ugrasmaz.
class Repository {
  String _q(int? storeId) => storeId == null ? '' : '?storeId=$storeId';

  Future<DashboardData> dashboard({int? storeId, bool silent = false}) async {
    final r = await api.dio.get<Map<String, dynamic>>(
      '/dashboard${_q(storeId)}',
      options: apiOptions(silent: silent),
    );
    return DashboardData.fromJson(r.data!);
  }

  Future<ReportSummary> reportSummary({int? storeId, bool silent = false}) async {
    final r = await api.dio.get<Map<String, dynamic>>(
      '/reports/summary${_q(storeId)}',
      options: apiOptions(silent: silent),
    );
    return ReportSummary.fromJson(r.data!);
  }

  Future<List<SalesPoint>> sales7({int? storeId, bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>(
      '/reports/sales7${_q(storeId)}',
      options: apiOptions(silent: silent),
    );
    return (r.data ?? [])
        .map((e) => SalesPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StatusSlice>> statusBreakdown({int? storeId, bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>(
      '/reports/status${_q(storeId)}',
      options: apiOptions(silent: silent),
    );
    return (r.data ?? [])
        .map((e) => StatusSlice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ProductPerformance> productPerformance({int? storeId, bool silent = false}) async {
    final r = await api.dio.get<Map<String, dynamic>>(
      '/reports/products${_q(storeId)}',
      options: apiOptions(silent: silent),
    );
    return ProductPerformance.fromJson(r.data!);
  }

  Future<int> pendingApprovalCount({bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>(
      '/approvals?status=pending',
      options: apiOptions(silent: silent),
    );
    return (r.data ?? []).length;
  }

  Future<List<Batch>> recommendations({int? storeId, bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>(
      '/recommendations${_q(storeId)}',
      options: apiOptions(silent: silent),
    );
    return (r.data ?? []).map((e) => Batch.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Satis her zaman tam bir adet dusurur.
  Future<void> sellOne(Batch batch) async {
    await api.dio.post(
      '/batches/${batch.id}/sell',
      data: {'quantity': 1},
      options: apiOptions(successMessage: '${batch.productName} — 1 adet satıldı'),
    );
  }

  /// Ikram ayni uc noktayi kullanir; sunucu kind = 'ikram' kaydini ciroya ve
  /// satis adedine saymaz, stoktan yine duser.
  Future<void> ikramOne(Batch batch) async {
    await api.dio.post(
      '/batches/${batch.id}/sell',
      data: {'quantity': 1, 'kind': 'ikram'},
      options: apiOptions(successMessage: '${batch.productName} — 1 adet ikram edildi'),
    );
  }

  Future<void> discardAll(Batch batch, {String reason = 'SKT süresi doldu'}) async {
    await api.dio.post(
      '/batches/${batch.id}/discard',
      data: {'reason': reason},
      options: apiOptions(successMessage: 'Ürün imha edildi'),
    );
  }

  // ---- Urunler / Stok ----

  Future<List<Batch>> batches({required String status, int? storeId, bool silent = false}) async {
    final params = <String>['status=$status'];
    if (storeId != null) params.add('storeId=$storeId');
    final r = await api.dio.get<List<dynamic>>(
      '/batches?${params.join('&')}',
      options: apiOptions(silent: silent),
    );
    return (r.data ?? []).map((e) => Batch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<(Batch, List<SaleRecord>)> batchDetail(int id) async {
    final r = await api.dio.get<Map<String, dynamic>>('/batches/$id', options: apiOptions());
    final data = r.data!;
    final sales = (data['sales'] as List<dynamic>? ?? [])
        .map((e) => SaleRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return (Batch.fromJson(data), sales);
  }

  Future<List<ProductType>> productTypes({int? storeId, bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>(
      '/product-types${_q(storeId)}',
      options: apiOptions(silent: silent),
    );
    return (r.data ?? []).map((e) => ProductType.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createBatch({
    required int productTypeId,
    required int quantity,
    int? storeId,
    String? batchCode,
    String? notes,
  }) async {
    await api.dio.post(
      '/batches',
      data: {
        'product_type_id': productTypeId,
        'quantity': quantity,
        'store_id': ?storeId,
        if (batchCode != null && batchCode.isNotEmpty) 'batch_code': batchCode,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      // Hata pencere icinde gosterilir; basari mesajini ekran verir.
      options: apiOptions(noToast: true),
    );
  }

  Future<Map<String, dynamic>> thaw(int batchId, int quantity) async {
    final r = await api.dio.post<Map<String, dynamic>>(
      '/batches/$batchId/thaw',
      data: {'quantity': quantity},
      options: apiOptions(noToast: true),
    );
    return r.data ?? const {};
  }

  Future<void> completeThaw(Batch batch) async {
    await api.dio.post(
      '/batches/${batch.id}/complete-thaw',
      options: apiOptions(successMessage: '${batch.productName} food dolabına aktarıldı'),
    );
  }

  Future<Map<String, dynamic>> discard(int batchId, {required int quantity, String? reason}) async {
    final r = await api.dio.post<Map<String, dynamic>>(
      '/batches/$batchId/discard',
      data: {'quantity': quantity, 'reason': ?reason},
      options: apiOptions(noToast: true),
    );
    return r.data ?? const {};
  }

  Future<void> addStock(int batchId, int quantity) async {
    await api.dio.post(
      '/batches/$batchId/add-stock',
      data: {'quantity': quantity},
      options: apiOptions(noToast: true),
    );
  }

  Future<void> requestEarlyTransfer(int batchId, String reason) async {
    await api.dio.post(
      '/batches/$batchId/request-early-transfer',
      data: {'reason': reason},
      options: apiOptions(noToast: true),
    );
  }

  Future<List<String>> adjustBatch(int batchId, Map<String, dynamic> payload) async {
    final r = await api.dio.put<Map<String, dynamic>>(
      '/batches/$batchId/adjust',
      data: payload,
      options: apiOptions(noToast: true),
    );
    return ((r.data?['changes'] as List<dynamic>?) ?? []).map((e) => e.toString()).toList();
  }

  // ---- Pasta Cesitleri ----

  Future<void> saveProductType({
    int? id,
    required String name,
    required int sktDays,
    num? unitPrice,
    String? description,
    bool active = true,
    int? storeId,
    bool includeStore = false,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'skt_days': sktDays,
      'unit_price': unitPrice,
      'description': description,
      'active': active,
      if (includeStore) 'store_id': storeId,
    };
    if (id == null) {
      await api.dio.post('/product-types', data: data, options: apiOptions(noToast: true));
    } else {
      await api.dio.put('/product-types/$id', data: data, options: apiOptions(noToast: true));
    }
  }

  Future<void> deleteProductType(ProductType type) async {
    await api.dio.delete(
      '/product-types/${type.id}',
      options: apiOptions(successMessage: 'Çeşit silindi'),
    );
  }

  // ---- Magazalar ----

  Future<List<Store>> storeList({bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>('/stores', options: apiOptions(silent: silent));
    return (r.data ?? []).map((e) => Store.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveStore({
    int? id,
    required String name,
    String? address,
    String? phone,
    bool active = true,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'address': address,
      'phone': phone,
      if (id != null) 'active': active,
    };
    if (id == null) {
      await api.dio.post('/stores', data: data, options: apiOptions(noToast: true));
    } else {
      await api.dio.put('/stores/$id', data: data, options: apiOptions(noToast: true));
    }
  }

  Future<void> deleteStore(Store store) async {
    await api.dio.delete('/stores/${store.id}', options: apiOptions(successMessage: 'Mağaza silindi'));
  }

  // ---- Kullanicilar ----

  Future<List<ManagedUser>> userList({bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>('/users', options: apiOptions(silent: silent));
    return (r.data ?? []).map((e) => ManagedUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createUser({
    required String username,
    required String password,
    required String fullName,
    required String role,
    int? storeId,
    bool active = true,
    List<String>? permissions,
    List<int>? storeIds,
  }) async {
    await api.dio.post(
      '/users',
      data: {
        'username': username,
        'password': password,
        'full_name': fullName,
        'role': role,
        'store_id': ?storeId,
        'active': active,
        'permissions': ?permissions,
        // Cok magazali roller icin sorumluluk listesi.
        'store_ids': ?storeIds,
      },
      options: apiOptions(noToast: true),
    );
  }

  Future<void> updateUser({
    required int id,
    required String fullName,
    required String role,
    bool? active,
    int? storeId,
    bool includeStore = false,
    List<String>? permissions,
    List<int>? storeIds,
  }) async {
    await api.dio.put(
      '/users/$id',
      data: {
        'full_name': fullName,
        'role': role,
        'active': ?active,
        if (includeStore) 'store_id': storeId,
        'permissions': ?permissions,
        'store_ids': ?storeIds,
      },
      options: apiOptions(noToast: true),
    );
  }

  Future<void> toggleUserActive(ManagedUser user) async {
    await api.dio.put(
      '/users/${user.id}',
      data: {'active': !user.active},
      options: apiOptions(
        successMessage: user.active ? 'Kullanıcı pasife alındı' : 'Kullanıcı aktifleştirildi',
      ),
    );
  }

  Future<void> resetUserPassword(int id, String password) async {
    await api.dio.post(
      '/users/$id/password',
      data: {'password': password},
      options: apiOptions(noToast: true),
    );
  }

  Future<void> deleteUser(ManagedUser user) async {
    await api.dio.delete('/users/${user.id}', options: apiOptions(successMessage: 'Kullanıcı silindi'));
  }

  // ---- Petty Cash ----

  Future<PettyCashPage> pettyCash({int? storeId, bool silent = false}) async {
    final r = await api.dio.get<Map<String, dynamic>>(
      '/petty-cash',
      queryParameters: {'storeId': ?storeId?.toString()},
      options: apiOptions(silent: silent),
    );
    return PettyCashPage.fromJson(r.data ?? const {});
  }

  /// Fis gorseli listede tasinmaz, tek tek cekilir.
  Future<String?> pettyCashReceipt(int id) async {
    final r = await api.dio.get<Map<String, dynamic>>(
      '/petty-cash/$id/receipt',
      options: apiOptions(busyMessage: 'Fiş açılıyor...'),
    );
    return r.data?['receipt'] as String?;
  }

  Future<void> addPettyCash({
    required num amount,
    required String description,
    String? receipt,
    DateTime? spentAt,
  }) async {
    await api.dio.post(
      '/petty-cash',
      data: {
        'amount': amount,
        'description': description,
        'receipt': ?receipt,
        'spent_at': ?spentAt?.toUtc().toIso8601String(),
      },
      // Hata pencerede satir ici gosterilir.
      options: apiOptions(noToast: true, busyMessage: 'Masraf kaydediliyor...'),
    );
  }

  Future<void> deletePettyCash(PettyCashExpense expense) async {
    await api.dio.delete(
      '/petty-cash/${expense.id}',
      options: apiOptions(successMessage: 'Masraf silindi'),
    );
  }

  Future<List<PettyCashLimit>> pettyCashLimits({bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>(
      '/petty-cash/limits',
      options: apiOptions(silent: silent),
    );
    return (r.data ?? []).map((e) => PettyCashLimit.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setPettyCashLimit(int storeId, num weeklyAmount) async {
    await api.dio.put(
      '/petty-cash/limits/$storeId',
      data: {'weekly_amount': weeklyAmount},
      options: apiOptions(noToast: true),
    );
  }

  // ---- Profil ----

  Future<void> changeOwnPassword(String current, String next) async {
    await api.dio.post(
      '/auth/password',
      data: {'current': current, 'next': next},
      // Hata form icinde gosterilir.
      options: apiOptions(noToast: true),
    );
  }

  /// Profil fotosu kaydeder ya da (avatar null ise) kaldirir; sunucunun
  /// sakladigi son degeri doner.
  Future<String?> saveAvatar(String? avatar) async {
    final r = await api.dio.post<Map<String, dynamic>>(
      '/auth/avatar',
      data: {'avatar': avatar},
      options: apiOptions(
        successMessage: avatar == null
            ? 'Profil fotoğrafı kaldırıldı'
            : 'Profil fotoğrafı güncellendi',
      ),
    );
    return r.data?['avatar'] as String?;
  }

  Future<AppUser> me() async {
    final r = await api.dio.get<Map<String, dynamic>>(
      '/auth/me',
      options: apiOptions(silent: true),
    );
    return AppUser.fromJson(r.data!);
  }

  // ---- Erken aktarim onaylari ----

  Future<List<TransferApproval>> approvals({
    String? status,
    int? storeId,
    bool silent = false,
  }) async {
    final r = await api.dio.get<List<dynamic>>(
      '/approvals',
      queryParameters: {
        'status': ?status,
        'storeId': ?storeId?.toString(),
      },
      options: apiOptions(silent: silent),
    );
    return (r.data ?? [])
        .map((e) => TransferApproval.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> approveTransfer(TransferApproval item) async {
    await api.dio.post(
      '/approvals/${item.id}/approve',
      options: apiOptions(
        successMessage: '${item.productName ?? 'Ürün'} food dolabına alındı, SKT başladı',
      ),
    );
  }

  Future<void> rejectTransfer(TransferApproval item, String? note) async {
    await api.dio.post(
      '/approvals/${item.id}/reject',
      data: {'note': ?note},
      // Hata pencerede satir ici gosterilir.
      options: apiOptions(noToast: true),
    );
  }

  // ---- Hareket raporu (satis + ikram + imha) ----

  /// [kinds] bos verilirse sunucu tum turleri doner. Tarihler gun bazindadir
  /// (YYYY-MM-DD); sunucu bitis gununu tamamen dahil eder.
  Future<MovementReport> movements({
    DateTime? from,
    DateTime? to,
    int? productTypeId,
    List<String> kinds = const [],
    int? storeId,
    bool silent = false,
  }) async {
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final r = await api.dio.get<Map<String, dynamic>>(
      '/reports/movements',
      queryParameters: {
        'from': ?(from == null ? null : day(from)),
        'to': ?(to == null ? null : day(to)),
        'productTypeId': ?productTypeId?.toString(),
        'kind': ?(kinds.isEmpty ? null : kinds.join(',')),
        'storeId': ?storeId?.toString(),
      },
      options: apiOptions(silent: silent),
    );
    return MovementReport.fromJson(r.data ?? const {});
  }

  // ---- Satis gecmisi ve hareket kayitlari ----

  Future<List<SaleRecord>> sales({int? storeId, bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>(
      '/sales',
      queryParameters: {'storeId': ?storeId?.toString()},
      options: apiOptions(silent: silent),
    );
    return (r.data ?? []).map((e) => SaleRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ActivityLog>> logs({bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>('/logs', options: apiOptions(silent: silent));
    return (r.data ?? []).map((e) => ActivityLog.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<StoreOption>> stores({bool silent = false}) async {
    final r = await api.dio.get<List<dynamic>>(
      '/stores',
      options: apiOptions(silent: silent),
    );
    return (r.data ?? [])
        .map((e) => StoreOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final repo = Repository();
