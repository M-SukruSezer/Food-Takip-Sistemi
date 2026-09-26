num? _numOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

num _num(dynamic v) => _numOrNull(v) ?? 0;
int _int(dynamic v) => _num(v).toInt();

/// Para ve oran alanlari icin: null KORUNUR.
///
/// _num gibi 0'a dusurmek "tanimsiz ucret" ile "sifir ucret" arasini yok
/// ederdi; sunucu tarafinda ayni hata olculdu ve herkesin hak edisini
/// sifirliyordu.
double? _dbl(dynamic v) => _numOrNull(v)?.toDouble();

/// Magazanin PDKS ayarlari (personelin gordugu kadari).
///
/// QR sirri BURADA YOK: sunucu hicbir cevapta dondurmuyor.
class PdksStore {
  const PdksStore({
    required this.id,
    required this.name,
    required this.pdksEnabled,
    required this.qrMode,
    required this.geofenceRadiusM,
    required this.hasLocation,
    this.latitude,
    this.longitude,
  });

  final int id;
  final String name;
  final bool pdksEnabled;
  final String qrMode;
  final int geofenceRadiusM;
  final bool hasLocation;
  final num? latitude;
  final num? longitude;

  bool get isStaticQr => qrMode == 'static';

  factory PdksStore.fromJson(Map<String, dynamic> j) => PdksStore(
    id: _int(j['id']),
    name: j['name'] as String? ?? '',
    pdksEnabled: j['pdks_enabled'] == true,
    qrMode: j['qr_mode'] as String? ?? 'rotating',
    geofenceRadiusM: _int(j['geofence_radius_m']),
    hasLocation: j['has_location'] == true,
    latitude: _numOrNull(j['latitude']),
    longitude: _numOrNull(j['longitude']),
  );
}

/// Gunun vardiyasi.
class PdksShift {
  const PdksShift({
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.isDayOff,
    this.breakMinutes = 0,
    this.lateToleranceMinutes = 0,
  });

  final String name;
  final String startTime;
  final String endTime;
  final bool isDayOff;
  final int breakMinutes;
  final int lateToleranceMinutes;

  /// Bitis <= baslangic ise vardiya gece yarisini gecer.
  bool get crossesMidnight =>
      startTime.isNotEmpty &&
      endTime.isNotEmpty &&
      endTime.compareTo(startTime) <= 0;

  factory PdksShift.fromJson(Map<String, dynamic> j) => PdksShift(
    name: j['name'] as String? ?? '',
    startTime: j['start_time'] as String? ?? '',
    endTime: j['end_time'] as String? ?? '',
    isDayOff: j['is_day_off'] == true,
    breakMinutes: _int(j['break_duration_minutes']),
    lateToleranceMinutes: _int(j['late_tolerance_minutes']),
  );
}

/// Atanabilir vardiya TANIMI.
///
/// PdksShift'ten ayri: o "bugun bana atanmis vardiya" gorunumu ve kimlik
/// tasimiyor. Bu model cizelgede hucreye atama yaparken secim listesini
/// besliyor, o yuzden id ve aktiflik gerekiyor.
class ShiftDef {
  const ShiftDef({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.breakMinutes = 0,
    this.storeId,
    this.storeName,
    this.active = true,
  });

  final int id;
  final String name;
  final String startTime;
  final String endTime;
  final int breakMinutes;
  final int? storeId;
  final String? storeName;
  final bool active;

  String get saatAraligi {
    final b = startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
    final e = endTime.length >= 5 ? endTime.substring(0, 5) : endTime;
    return '$b–$e';
  }

  /// Vardiyanin brut suresi (dakika); gece yarisini gecebilir.
  int get spanMinutes {
    int? dk(String v) {
      if (v.length < 5) return null;
      final s = int.tryParse(v.substring(0, 2));
      final d = int.tryParse(v.substring(3, 5));
      return (s == null || d == null) ? null : s * 60 + d;
    }

    final b = dk(startTime);
    final e = dk(endTime);
    if (b == null || e == null) return 0;
    return e > b ? e - b : 24 * 60 - b + e;
  }

  /// 4857 m.68 asgari ara dinlenmesi.
  int get legalBreak {
    final s = spanMinutes;
    if (s <= 240) return 15;
    if (s <= 450) return 30;
    return 60;
  }

  /// NET calisma: mola dusulmus. Sunucudaki netDakika ile ayni kural
  /// (tanimli ile yasal asgarinin kucugu dusulur).
  int get netMinutes {
    final s = spanMinutes;
    if (s <= 0) return 0;
    final d = breakMinutes <= 0
        ? 0
        : (breakMinutes < legalBreak ? breakMinutes : legalBreak);
    return s - d;
  }

  /// Secim listesinde gosterilen kisa yasal uyari; yoksa null.
  String? get warning {
    final s = spanMinutes;
    if (s <= 0) return null;
    if (s > 11 * 60) return '11 saat aşımı (m.63)';
    if (breakMinutes < legalBreak) return 'mola en az $legalBreak dk (m.68)';
    return null;
  }

  factory ShiftDef.fromJson(Map<String, dynamic> j) => ShiftDef(
    id: _int(j['id']),
    name: j['name'] as String? ?? '',
    startTime: j['start_time'] as String? ?? '',
    endTime: j['end_time'] as String? ?? '',
    breakMinutes: _int(j['break_duration_minutes']),
    storeId: j['store_id'] == null ? null : _int(j['store_id']),
    storeName: j['store_name'] as String?,
    active: j['active'] == null ? true : _int(j['active']) == 1,
  );
}

/// Tek devam kaydi.
class AttendanceLog {
  const AttendanceLog({
    required this.id,
    required this.type,
    required this.method,
    required this.occurredAt,
    this.distanceM,
    this.isValidLocation,
  });

  final int id;
  final String type;
  final String method;
  final String occurredAt;
  final num? distanceM;
  final int? isValidLocation;

  bool get isEntry => type == 'GIRIS';
  String get typeLabel => isEntry ? 'Giriş' : 'Çıkış';

  factory AttendanceLog.fromJson(Map<String, dynamic> j) => AttendanceLog(
    id: _int(j['id']),
    type: j['type'] as String? ?? '',
    method: j['method'] as String? ?? '',
    occurredAt: j['occurred_at'] as String? ?? '',
    distanceM: _numOrNull(j['distance_m']),
    isValidLocation: j['is_valid_location'] == null
        ? null
        : _int(j['is_valid_location']),
  );
}

/// Personelin anlik durumu.
/// Dort adimli akistaki durum. Sunucu 'state' alanini kendisi bildiriyor;
/// kurali istemcide tekrar yazmak iki tarafin ayrismasi demekti.
enum PdksState { disarida, iceride, molada }

class PdksStatus {
  const PdksStatus({
    required this.workDate,
    required this.isInside,
    required this.shifts,
    required this.logs,
    this.store,
    this.openSince,
    this.state = PdksState.disarida,
    this.onBreak = false,
    this.breakSince,
    this.breakMinutesToday = 0,
    this.canCheckIn = false,
    this.canCheckOut = false,
    this.canBreakStart = false,
    this.canBreakEnd = false,
  });

  final String workDate;

  /// Molada olan personel de ICERIDE sayilir: mesai devam ediyor.
  final bool isInside;
  final List<PdksShift> shifts;
  final List<AttendanceLog> logs;
  final PdksStore? store;
  final String? openSince;
  final PdksState state;
  final bool onBreak;
  final String? breakSince;

  /// Bu is gununde biriken mola suresi; acik mola sayilmaz.
  final int breakMinutesToday;

  // Sunucunun bildirdigi izinli sonraki adimlar.
  final bool canCheckIn;
  final bool canCheckOut;
  final bool canBreakStart;
  final bool canBreakEnd;

  bool get canUseGps =>
      (store?.pdksEnabled ?? false) && (store?.hasLocation ?? false);
  bool get canUseQr => store?.pdksEnabled ?? false;

  factory PdksStatus.fromJson(Map<String, dynamic> j) => PdksStatus(
    workDate: j['work_date'] as String? ?? '',
    isInside: j['is_inside'] == true,
    openSince: j['open_since'] as String?,
    state: switch (j['state']) {
      'MOLADA' => PdksState.molada,
      'ICERIDE' => PdksState.iceride,
      _ => PdksState.disarida,
    },
    onBreak: j['on_break'] == true,
    breakSince: j['break_since'] as String?,
    breakMinutesToday: (j['break_minutes_today'] as num?)?.round() ?? 0,
    canCheckIn: (j['can'] as Map<String, dynamic>?)?['check_in'] == true,
    canCheckOut: (j['can'] as Map<String, dynamic>?)?['check_out'] == true,
    canBreakStart: (j['can'] as Map<String, dynamic>?)?['break_start'] == true,
    canBreakEnd: (j['can'] as Map<String, dynamic>?)?['break_end'] == true,
    store: j['store'] == null
        ? null
        : PdksStore.fromJson(j['store'] as Map<String, dynamic>),
    shifts: ((j['shifts'] as List<dynamic>?) ?? [])
        .map((e) => PdksShift.fromJson(e as Map<String, dynamic>))
        .toList(),
    logs: ((j['logs'] as List<dynamic>?) ?? [])
        .map((e) => AttendanceLog.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  static const empty = PdksStatus(
    workDate: '',
    isInside: false,
    shifts: [],
    logs: [],
  );
}

/// Kioskta ya da personelin telefonunda gosterilecek QR kodu.
class QrToken {
  const QrToken({
    required this.token,
    required this.expiresIn,
    required this.windowSeconds,
    this.mode,
  });

  final String token;
  final int expiresIn;
  final int windowSeconds;

  /// 'rotating' | 'static' — sabit kod sure doldurmaz.
  final String? mode;

  bool get isStatic => mode == 'static';

  factory QrToken.fromJson(Map<String, dynamic> j) => QrToken(
    token: j['token'] as String? ?? '',
    expiresIn: _int(j['expires_in']),
    windowSeconds: _int(j['window_seconds']),
    mode: j['mode'] as String?,
  );
}

/// Izin ve avans bakiyesi.
class PdksBalance {
  const PdksBalance({
    required this.entitlementDays,
    required this.usedDays,
    required this.pendingDays,
    required this.remainingDays,
    required this.advanceLimit,
    required this.advanceUsed,
    required this.advancePending,
    required this.advanceRemaining,
    required this.hourlyUsedHours,
    required this.leaveYearFrom,
    required this.leaveYearTo,
    required this.notes,
  });

  final num entitlementDays;
  final num usedDays;
  final num pendingDays;
  final num remainingDays;
  final num advanceLimit;
  final num advanceUsed;
  final num advancePending;
  final num advanceRemaining;
  final num hourlyUsedHours;
  final String leaveYearFrom;
  final String leaveYearTo;

  /// Sunucudan gelen uyarilar (orn. resmi tatillerin dusulmedigi).
  final List<String> notes;

  factory PdksBalance.fromJson(Map<String, dynamic> j) {
    final leave = (j['leave'] as Map<String, dynamic>?) ?? const {};
    final adv = (j['advance'] as Map<String, dynamic>?) ?? const {};
    final hourly = (j['hourly_leave'] as Map<String, dynamic>?) ?? const {};
    final year = (j['leave_year'] as Map<String, dynamic>?) ?? const {};
    return PdksBalance(
      entitlementDays: _num(leave['entitlement_days']),
      usedDays: _num(leave['used_days']),
      pendingDays: _num(leave['pending_days']),
      remainingDays: _num(leave['remaining_days']),
      advanceLimit: _num(adv['monthly_limit']),
      advanceUsed: _num(adv['used']),
      advancePending: _num(adv['pending']),
      advanceRemaining: _num(adv['remaining']),
      hourlyUsedHours: _num(hourly['used_hours']),
      leaveYearFrom: year['from'] as String? ?? '',
      leaveYearTo: year['to'] as String? ?? '',
      notes: ((j['notes'] as List<dynamic>?) ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Izin / saatlik izin / avans talebi.
class PersonnelRequest {
  const PersonnelRequest({
    required this.id,
    required this.type,
    required this.status,
    required this.reason,
    this.fullName,
    this.startAt,
    this.endAt,
    this.days,
    this.hours,
    this.amount,
    this.managerName,
    this.decisionNote,
  });

  final int id;
  final String type;
  final String status;
  final String reason;
  final String? fullName;
  final String? startAt;
  final String? endAt;
  final num? days;
  final num? hours;
  final num? amount;
  final String? managerName;
  final String? decisionNote;

  bool get isPending => status == 'PENDING';

  String get typeLabel => switch (type) {
    'IZIN' => 'Yıllık İzin',
    'SAATLIK_IZIN' => 'Saatlik İzin',
    _ => 'Avans',
  };

  String get statusLabel => switch (status) {
    'PENDING' => 'Bekliyor',
    'APPROVED' => 'Onaylandı',
    'REJECTED' => 'Reddedildi',
    _ => 'İptal',
  };

  factory PersonnelRequest.fromJson(Map<String, dynamic> j) => PersonnelRequest(
    id: _int(j['id']),
    type: j['type'] as String? ?? '',
    status: j['status'] as String? ?? 'PENDING',
    reason: j['reason'] as String? ?? '',
    fullName: j['full_name'] as String?,
    startAt: j['start_at'] as String?,
    endAt: j['end_at'] as String?,
    days: _numOrNull(j['days']),
    hours: _numOrNull(j['hours']),
    amount: _numOrNull(j['amount']),
    managerName: j['manager_name'] as String?,
    decisionNote: j['decision_note'] as String?,
  );
}

/// Vardiya atamasi (takvim icin).
class ShiftAssignment {
  const ShiftAssignment({
    required this.id,
    required this.userId,
    required this.workDate,
    required this.isDayOff,
    this.shiftName,
    this.startTime,
    this.endTime,
    this.fullName,
  });

  final int id;
  final int userId;
  final String workDate;
  final bool isDayOff;
  final String? shiftName;
  final String? startTime;
  final String? endTime;
  final String? fullName;

  factory ShiftAssignment.fromJson(Map<String, dynamic> j) => ShiftAssignment(
    id: _int(j['id']),
    userId: _int(j['user_id']),
    workDate: j['work_date'] as String? ?? '',
    isDayOff: j['is_day_off'] == true,
    shiftName: j['shift_name'] as String?,
    startTime: j['start_time'] as String?,
    endTime: j['end_time'] as String?,
    fullName: j['full_name'] as String?,
  );
}

/// Resmi tatil.
class PublicHoliday {
  const PublicHoliday({
    required this.id,
    required this.date,
    required this.name,
    required this.isHalfDay,
    this.storeId,
    this.storeName,
  });

  final int id;
  final String date;
  final String name;

  /// Arefe gibi yarim tatil: izin hesabinda 0,5 gun sayilir.
  final bool isHalfDay;

  /// null = tum magazalar.
  final int? storeId;
  final String? storeName;

  bool get isStoreSpecific => storeId != null;

  factory PublicHoliday.fromJson(Map<String, dynamic> j) => PublicHoliday(
    id: _int(j['id']),
    date: j['holiday_date'] as String? ?? '',
    name: j['name'] as String? ?? '',
    isHalfDay: j['is_half_day'] == true || j['is_half_day'] == 1,
    storeId: j['store_id'] == null ? null : _int(j['store_id']),
    storeName: j['store_name'] as String?,
  );
}

/// Tatil listesini gune gore haritalar.
///
/// Magazaya ozel kayit geneli gecersiz kilar — sunucu tarafindaki holidayMap
/// ile ayni kural; iki tarafin ayrismamasi icin burada da uygulaniyor.
Map<String, PublicHoliday> holidayMap(List<PublicHoliday> list) {
  final out = <String, PublicHoliday>{};
  for (final h in list) {
    final existing = out[h.date];
    if (existing != null && existing.isStoreSpecific && !h.isStoreSpecific) {
      continue;
    }
    out[h.date] = h;
  }
  return out;
}

/// "Su an kimler iste" satiri.
class PresenceRow {
  const PresenceRow({
    required this.userId,
    required this.fullName,
    required this.role,
    this.lastType,
    this.lastMethod,
    this.lastAt,
    this.minutesSince,
    this.distanceM,
    this.storeName,
  });

  final int userId;
  final String fullName;
  final String role;
  final String? lastType;
  final String? lastMethod;
  final String? lastAt;
  final int? minutesSince;
  final num? distanceM;
  final String? storeName;

  bool get isInside => lastType == 'GIRIS';

  factory PresenceRow.fromJson(Map<String, dynamic> j) => PresenceRow(
    userId: _int(j['user_id']),
    fullName: j['full_name'] as String? ?? '',
    role: j['role'] as String? ?? '',
    lastType: j['last_type'] as String?,
    lastMethod: j['last_method'] as String?,
    lastAt: j['last_at'] as String?,
    minutesSince: j['minutes_since'] == null ? null : _int(j['minutes_since']),
    distanceM: _numOrNull(j['distance_m']),
    storeName: j['store_name'] as String?,
  );
}

class PresenceSnapshot {
  const PresenceSnapshot({
    required this.insideCount,
    required this.inside,
    required this.outside,
  });

  final int insideCount;
  final List<PresenceRow> inside;
  final List<PresenceRow> outside;

  factory PresenceSnapshot.fromJson(Map<String, dynamic> j) => PresenceSnapshot(
    insideCount: _int(j['inside_count']),
    inside: ((j['inside'] as List<dynamic>?) ?? [])
        .map((e) => PresenceRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    outside: ((j['outside'] as List<dynamic>?) ?? [])
        .map((e) => PresenceRow.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  static const empty = PresenceSnapshot(
    insideCount: 0,
    inside: [],
    outside: [],
  );
}

/// Puantajda bir gun.
class TimesheetDay {
  const TimesheetDay({
    required this.workDate,
    required this.presenceMinutes,
    required this.workedMinutes,
    required this.scheduledMinutes,
    required this.overtimeMinutes,
    required this.missingMinutes,
    required this.lateMinutes,
    required this.isDayOff,
    required this.onLeave,
    required this.statuses,
    required this.shiftNames,
    this.isHoliday = false,
    this.holidayName,
    this.riskFlags = const [],
    this.deductedBreakMinutes = 0,
    this.recordedBreakMinutes = 0,
    this.hasBreakRecords = false,
    this.breakShortfallMinutes = 0,
  });

  final String workDate;
  final int presenceMinutes;
  final int workedMinutes;
  final int scheduledMinutes;
  final int overtimeMinutes;
  final int missingMinutes;
  final int lateMinutes;
  final bool isDayOff;
  final bool onLeave;
  final List<String> statuses;
  final List<String> shiftNames;

  /// Resmi tatil: planli sure sifirdir, calisma tamamen fazla mesai.
  final bool isHoliday;
  final String? holidayName;

  /// O gunun kayitlarinda biriken cihaz uyarilari (root, gelistirici modu,
  /// kontrol edilemedi). Islemi ENGELLEYEN bayraklar hic kayit yazmadigi icin
  /// burada gorunmez.
  final List<String> riskFlags;

  /// Gunden dusulen mola. Mola kaydi varsa fiili, yoksa tanimli/yasal kucugu.
  final int deductedBreakMinutes;
  final int recordedBreakMinutes;
  final bool hasBreakRecords;

  /// Yasal asgari ara dinlenmesinin (m.68) altinda kalan sure. Dusume etki
  /// etmez; ihlal olarak bildirilir.
  final int breakShortfallMinutes;

  factory TimesheetDay.fromJson(Map<String, dynamic> j) => TimesheetDay(
    workDate: j['work_date'] as String? ?? '',
    presenceMinutes: _int(j['presence_minutes']),
    workedMinutes: _int(j['worked_minutes']),
    scheduledMinutes: _int(j['scheduled_minutes']),
    overtimeMinutes: _int(j['overtime_minutes']),
    missingMinutes: _int(j['missing_minutes']),
    lateMinutes: _int(j['late_minutes']),
    isDayOff: j['is_day_off'] == true,
    onLeave: j['on_leave'] == true,
    statuses: ((j['statuses'] as List<dynamic>?) ?? [])
        .map((e) => e.toString())
        .toList(),
    shiftNames: ((j['shift_names'] as List<dynamic>?) ?? [])
        .map((e) => e.toString())
        .toList(),
    isHoliday: j['is_holiday'] == true,
    holidayName: j['holiday_name'] as String?,
    riskFlags: ((j['risk_flags'] as List<dynamic>?) ?? [])
        .map((e) => e.toString())
        .toList(),
    deductedBreakMinutes: _int(j['deducted_break_minutes']),
    recordedBreakMinutes: _int(j['recorded_break_minutes']),
    hasBreakRecords: j['has_break_records'] == true,
    breakShortfallMinutes: _int(j['break_shortfall_minutes']),
  );
}

class TimesheetSummary {
  const TimesheetSummary({
    required this.days,
    required this.workedDays,
    required this.absentDays,
    required this.leaveDays,
    required this.holidayDays,
    required this.workedMinutes,
    required this.scheduledMinutes,
    required this.overtimeMinutes,
    required this.missingMinutes,
    required this.lateMinutes,
    required this.unscheduledMinutes,
    this.flaggedDays = 0,
    this.deductedBreakMinutes = 0,
    this.recordedBreakMinutes = 0,
    this.breakShortfallDays = 0,
  });

  final int days;
  final int workedDays;
  final int absentDays;
  final int leaveDays;
  final int holidayDays;
  final int workedMinutes;
  final int scheduledMinutes;
  final int overtimeMinutes;
  final int missingMinutes;
  final int lateMinutes;

  /// Vardiya atanmamis gunlerin calismasi: siniflandirilmadigi icin ayri.
  final int unscheduledMinutes;

  /// En az bir cihaz uyarisi tasiyan gun sayisi.
  final int flaggedDays;

  final int deductedBreakMinutes;
  final int recordedBreakMinutes;

  /// Yasal asgari molanin altinda kalinan gun sayisi (m.68).
  final int breakShortfallDays;

  factory TimesheetSummary.fromJson(Map<String, dynamic> j) => TimesheetSummary(
    days: _int(j['days']),
    workedDays: _int(j['worked_days']),
    absentDays: _int(j['absent_days']),
    leaveDays: _int(j['leave_days']),
    holidayDays: _int(j['holiday_days']),
    workedMinutes: _int(j['worked_minutes']),
    scheduledMinutes: _int(j['scheduled_minutes']),
    overtimeMinutes: _int(j['overtime_minutes']),
    missingMinutes: _int(j['missing_minutes']),
    lateMinutes: _int(j['late_minutes']),
    unscheduledMinutes: _int(j['unscheduled_minutes']),
    flaggedDays: _int(j['flagged_days']),
    deductedBreakMinutes: _int(j['deducted_break_minutes']),
    recordedBreakMinutes: _int(j['recorded_break_minutes']),
    breakShortfallDays: _int(j['break_shortfall_days']),
  );

  static const empty = TimesheetSummary(
    days: 0,
    workedDays: 0,
    absentDays: 0,
    leaveDays: 0,
    holidayDays: 0,
    workedMinutes: 0,
    scheduledMinutes: 0,
    overtimeMinutes: 0,
    missingMinutes: 0,
    lateMinutes: 0,
    unscheduledMinutes: 0,
  );
}

class TimesheetPerson {
  const TimesheetPerson({
    required this.userId,
    required this.fullName,
    required this.days,
    required this.summary,
    this.role,
    this.storeName,
    this.wage,
  });

  final int userId;
  final String fullName;
  final String? role;
  final String? storeName;
  final List<TimesheetDay> days;
  final TimesheetSummary summary;

  /// Ucret hak edisi. Sunucu yalnizca yetkiliye gonderiyor; yetki yoksa
  /// alan HIC gelmez ve bu null kalir.
  final WageLine? wage;

  factory TimesheetPerson.fromJson(Map<String, dynamic> j) {
    final u = (j['user'] as Map<String, dynamic>?) ?? const {};
    return TimesheetPerson(
      userId: _int(u['id']),
      fullName: u['full_name'] as String? ?? '',
      role: u['role'] as String?,
      storeName: u['store_name'] as String?,
      days: ((j['days'] as List<dynamic>?) ?? [])
          .map((e) => TimesheetDay.fromJson(e as Map<String, dynamic>))
          .toList(),
      summary: j['summary'] == null
          ? TimesheetSummary.empty
          : TimesheetSummary.fromJson(j['summary'] as Map<String, dynamic>),
      wage: j['wage'] == null
          ? null
          : WageLine.fromJson(j['wage'] as Map<String, dynamic>),
    );
  }
}

class TimesheetReport {
  const TimesheetReport({
    required this.from,
    required this.to,
    required this.items,
    required this.total,
    required this.notes,
    this.wagesIncluded = false,
    this.wageTotal,
  });

  final String from;
  final String to;
  final List<TimesheetPerson> items;
  final TimesheetSummary total;
  final List<String> notes;

  /// Sunucu ucret alanlarini gonderdi mi. Arayuz sutunlari buna gore ciziyor;
  /// yetki yoksa ucret sutunu HIC olusturulmuyor.
  final bool wagesIncluded;

  /// Kisilerin hak edislerinin toplami. Birlesik ozetten yeniden
  /// hesaplanamaz: her kisinin saat ucreti farkli.
  final WageLine? wageTotal;

  factory TimesheetReport.fromJson(Map<String, dynamic> j) => TimesheetReport(
    from: j['from'] as String? ?? '',
    to: j['to'] as String? ?? '',
    items: ((j['items'] as List<dynamic>?) ?? [])
        .map((e) => TimesheetPerson.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: j['total'] == null
        ? TimesheetSummary.empty
        : TimesheetSummary.fromJson(j['total'] as Map<String, dynamic>),
    notes: ((j['notes'] as List<dynamic>?) ?? [])
        .map((e) => e.toString())
        .toList(),
    wagesIncluded: j['wages_included'] == true,
    wageTotal: j['wage_total'] == null
        ? null
        : WageLine.fromJson(j['wage_total'] as Map<String, dynamic>),
  );

  static const empty = TimesheetReport(
    from: '',
    to: '',
    items: [],
    total: TimesheetSummary.empty,
    notes: [],
  );
}

/// Ucret hak edisi. Sunucu bunu YALNIZCA yetkiliye gonderiyor; alan hic
/// gelmezse null kalir ve arayuz ucret sutunlarini hic cizmez.
///
/// BORDRO DEGIL: brut hak edistir, SGK ve vergi kesintisi icermez.
class WageLine {
  const WageLine({
    required this.defined,
    this.basis,
    this.hourlyRate,
    this.monthlySalary,
    this.mealDaily,
    this.normalMinutes = 0,
    this.normalPay,
    this.overtimeMinutes = 0,
    this.overtimeMultiplier = 1.5,
    this.overtimePay,
    this.leaveMinutes = 0,
    this.leavePay,
    this.workedDays = 0,
    this.mealPay,
    this.grossTotal,
  });

  /// Ucret ya da yemek tanimli mi. false ise tutarlar null; "0 TL" yazmak
  /// "ucretsiz calisiyor" anlamina gelirdi.
  final bool defined;

  /// 'hourly' (dogrudan girilmis) ya da 'monthly' (aylikdan turetilmis).
  final String? basis;
  final double? hourlyRate;
  final double? monthlySalary;
  final double? mealDaily;
  final int normalMinutes;
  final double? normalPay;
  final int overtimeMinutes;
  final double overtimeMultiplier;
  final double? overtimePay;
  final int leaveMinutes;
  final double? leavePay;
  final int workedDays;
  final double? mealPay;
  final double? grossTotal;

  /// Maas satiri: normal + fazla mesai + izin. Yemek ayri gosteriliyor.
  double? get salaryTotal {
    if (normalPay == null && overtimePay == null && leavePay == null) {
      return null;
    }
    return (normalPay ?? 0) + (overtimePay ?? 0) + (leavePay ?? 0);
  }

  factory WageLine.fromJson(Map<String, dynamic> j) => WageLine(
    defined: j['defined'] == true,
    basis: j['basis'] as String?,
    hourlyRate: _dbl(j['hourly_rate']),
    monthlySalary: _dbl(j['monthly_salary']),
    mealDaily: _dbl(j['meal_daily']),
    normalMinutes: _int(j['normal_minutes']),
    normalPay: _dbl(j['normal_pay']),
    overtimeMinutes: _int(j['overtime_minutes']),
    overtimeMultiplier: _dbl(j['overtime_multiplier']) ?? 1.5,
    overtimePay: _dbl(j['overtime_pay']),
    leaveMinutes: _int(j['leave_minutes']),
    leavePay: _dbl(j['leave_pay']),
    workedDays: _int(j['worked_days']),
    mealPay: _dbl(j['meal_pay']),
    grossTotal: _dbl(j['gross_total']),
  );
}

/// Personel ucret ve profil tanimlari.
class PdksProfile {
  const PdksProfile({
    required this.userId,
    required this.fullName,
    required this.role,
    this.storeId,
    this.storeName,
    this.hiredAt,
    this.annualLeaveDays = 14,
    this.monthlyAdvanceLimit = 0,
    this.weeklyOffDays = const [0],
    this.monthlySalary,
    this.hourlyRate,
    this.mealDaily,
    this.effectiveHourlyRate,
    this.wageBasis,
  });

  final int userId;
  final String fullName;
  final String role;
  final int? storeId;
  final String? storeName;
  final String? hiredAt;
  final double annualLeaveDays;
  final double monthlyAdvanceLimit;
  final List<int> weeklyOffDays;

  /// null = TANIMSIZ, 0 = tanimli ama odenmiyor. Ikisi ayri.
  final double? monthlySalary;
  final double? hourlyRate;
  final double? mealDaily;
  final double? effectiveHourlyRate;
  final String? wageBasis;

  factory PdksProfile.fromJson(Map<String, dynamic> j) => PdksProfile(
    userId: _int(j['user_id']),
    fullName: j['full_name'] as String? ?? '',
    role: j['role'] as String? ?? '',
    storeId: j['store_id'] == null ? null : _int(j['store_id']),
    storeName: j['store_name'] as String?,
    hiredAt: j['hired_at'] as String?,
    annualLeaveDays: _dbl(j['annual_leave_days']) ?? 14,
    monthlyAdvanceLimit: _dbl(j['monthly_advance_limit']) ?? 0,
    weeklyOffDays: ((j['weekly_off_days'] as List<dynamic>?) ?? [0])
        .map((e) => _int(e))
        .toList(),
    monthlySalary: _dbl(j['monthly_salary']),
    hourlyRate: _dbl(j['hourly_rate']),
    mealDaily: _dbl(j['meal_daily']),
    effectiveHourlyRate: _dbl(j['effective_hourly_rate']),
    wageBasis: j['wage_basis'] as String?,
  );
}

/// Cizelgede bir gunun bir hucresi. Bolunmus vardiyada birden fazla olabilir.
/// Vardiya kategorisi. Siniflandirma SUNUCUDA 4857 sayili Kanun'a gore
/// yapiliyor (m.69 gece donemi 20:00-06:00); istemci yalnizca rengi seciyor.
enum ShiftCategory { sabah, gunduz, aksam, gece, bilinmiyor }

ShiftCategory shiftCategoryOf(String? v) => switch (v) {
  'sabah' => ShiftCategory.sabah,
  'gunduz' => ShiftCategory.gunduz,
  'aksam' => ShiftCategory.aksam,
  'gece' => ShiftCategory.gece,
  _ => ShiftCategory.bilinmiyor,
};

/// Yasal sinir uyarisi (4857 m.63 / m.68 / m.69).
class ShiftWarning {
  const ShiftWarning({required this.kod, required this.etiket, this.aciklama});

  final String kod;

  /// Hucrede gosterilen kisa etiket. Renk TEK BASINA bilgi tasimasin diye
  /// uyarinin yazili karsiligi da her zaman cizilir.
  final String etiket;
  final String? aciklama;

  factory ShiftWarning.fromJson(Map<String, dynamic> j) => ShiftWarning(
    kod: j['kod'] as String? ?? '',
    etiket: j['etiket'] as String? ?? '',
    aciklama: j['aciklama'] as String?,
  );
}

class RosterCell {
  const RosterCell({
    this.assignmentId,
    this.shiftId,
    this.shiftName,
    this.startTime,
    this.endTime,
    this.breakDurationMinutes = 0,
    this.isDayOff = false,
    this.crossesMidnight = false,
    this.minutes = 0,
    this.spanMinutes = 0,
    this.category = ShiftCategory.bilinmiyor,
    this.nightMinutes = 0,
    this.warnings = const [],
  });

  /// Atama kaydinin kimligi; hucre duzenlemesinde kullaniliyor.
  final int? assignmentId;
  final int? shiftId;
  final String? shiftName;
  final String? startTime;
  final String? endTime;
  final int breakDurationMinutes;
  final bool isDayOff;

  /// 22:00-06:00 gibi gece vardiyasi; cizelgede ertesi gune sarkar.
  final bool crossesMidnight;

  /// NET calisma suresi: ara dinlenmesi DUSULMUS. Cizelgede "planlanan
  /// calisma saati" molayi icermiyor.
  final int minutes;

  /// Molali toplam sure; "08:00-16:30" araliginin kendisi.
  final int spanMinutes;
  final ShiftCategory category;
  final int nightMinutes;
  final List<ShiftWarning> warnings;

  String get saatAraligi {
    final b = (startTime ?? '');
    final e = (endTime ?? '');
    if (b.isEmpty || e.isEmpty) return '';
    return '${b.length >= 5 ? b.substring(0, 5) : b}'
        '–${e.length >= 5 ? e.substring(0, 5) : e}';
  }

  factory RosterCell.fromJson(Map<String, dynamic> j) => RosterCell(
    assignmentId: j['assignment_id'] == null ? null : _int(j['assignment_id']),
    shiftId: j['shift_id'] == null ? null : _int(j['shift_id']),
    shiftName: j['shift_name'] as String?,
    startTime: j['start_time'] as String?,
    endTime: j['end_time'] as String?,
    breakDurationMinutes: _int(j['break_duration_minutes']),
    isDayOff: j['is_day_off'] == true,
    crossesMidnight: j['crosses_midnight'] == true,
    minutes: _int(j['minutes']),
    spanMinutes: _int(j['span_minutes']),
    category: shiftCategoryOf(j['category'] as String?),
    nightMinutes: _int(j['night_minutes']),
    warnings: ((j['warnings'] as List<dynamic>?) ?? [])
        .map((e) => ShiftWarning.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class RosterPerson {
  const RosterPerson({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.cells,
    this.storeName,
    this.plannedMinutes = 0,
    this.shiftDays = 0,
    this.dayOffDays = 0,
    this.unassignedDays = 0,
  });

  final int userId;
  final String fullName;
  final String role;

  /// Tarih -> o gunun vardiyalari. Bos liste = atama yok.
  final Map<String, List<RosterCell>> cells;
  final String? storeName;
  final int plannedMinutes;
  final int shiftDays;
  final int dayOffDays;
  final int unassignedDays;

  List<RosterCell> gun(String tarih) => cells[tarih] ?? const [];

  factory RosterPerson.fromJson(Map<String, dynamic> j) {
    final u = (j['user'] as Map<String, dynamic>?) ?? const {};
    final raw = (j['cells'] as Map<String, dynamic>?) ?? const {};
    return RosterPerson(
      userId: _int(u['id']),
      fullName: u['full_name'] as String? ?? '',
      role: u['role'] as String? ?? '',
      storeName: u['store_name'] as String?,
      cells: {
        for (final e in raw.entries)
          e.key: ((e.value as List<dynamic>?) ?? [])
              .map((c) => RosterCell.fromJson(c as Map<String, dynamic>))
              .toList(),
      },
      plannedMinutes: _int(j['planned_minutes']),
      shiftDays: _int(j['shift_days']),
      dayOffDays: _int(j['day_off_days']),
      unassignedDays: _int(j['unassigned_days']),
    );
  }
}

class RosterDayTotal {
  const RosterDayTotal({
    this.working = 0,
    this.dayOff = 0,
    this.unassigned = 0,
    this.minutes = 0,
  });

  final int working;
  final int dayOff;
  final int unassigned;
  final int minutes;

  factory RosterDayTotal.fromJson(Map<String, dynamic> j) => RosterDayTotal(
    working: _int(j['working']),
    dayOff: _int(j['day_off']),
    unassigned: _int(j['unassigned']),
    minutes: _int(j['minutes']),
  );
}

/// Toplu vardiya cizelgesi. Ucret ya da puantaj verisi ICERMEZ.
class Roster {
  const Roster({
    required this.from,
    required this.to,
    required this.dates,
    required this.people,
    required this.totals,
    required this.holidays,
    this.storeName,
    this.canEdit = false,
  });

  final String from;
  final String to;
  final List<String> dates;
  final List<RosterPerson> people;
  final Map<String, RosterDayTotal> totals;
  final Map<String, PublicHoliday> holidays;
  final String? storeName;

  /// Cizelgeyi degistirebilen roller; arayuz dugmeleri buna gore cizilir.
  final bool canEdit;

  int get totalPlannedMinutes => people.fold(0, (a, p) => a + p.plannedMinutes);

  RosterDayTotal gunToplam(String tarih) =>
      totals[tarih] ?? const RosterDayTotal();

  factory Roster.fromJson(Map<String, dynamic> j) => Roster(
    from: j['from'] as String? ?? '',
    to: j['to'] as String? ?? '',
    dates: ((j['dates'] as List<dynamic>?) ?? [])
        .map((e) => e.toString())
        .toList(),
    people: ((j['people'] as List<dynamic>?) ?? [])
        .map((e) => RosterPerson.fromJson(e as Map<String, dynamic>))
        .toList(),
    totals: {
      for (final e in ((j['totals'] as Map<String, dynamic>?) ?? {}).entries)
        e.key: RosterDayTotal.fromJson(e.value as Map<String, dynamic>),
    },
    holidays: {
      for (final e in ((j['holidays'] as Map<String, dynamic>?) ?? {}).entries)
        e.key: PublicHoliday.fromJson({
          'holiday_date': e.key,
          ...(e.value as Map<String, dynamic>),
        }),
    },
    storeName: j['store'] as String?,
    canEdit: j['can_edit'] == true,
  );
}

/// Devam takibindeki dort adim.
enum PdksPunch {
  checkIn('check-in', 'Giriş kaydedildi'),
  checkOut('check-out', 'Çıkış kaydedildi'),
  breakStart('break-start', 'Mola başladı'),
  breakEnd('break-end', 'Mola bitti');

  const PdksPunch(this.yol, this.mesaj);

  /// Uc noktanin yol parcasi.
  final String yol;

  /// Basarili islem bildirimi.
  final String mesaj;
}
