num? _numOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

num _num(dynamic v) => _numOrNull(v) ?? 0;
int _int(dynamic v) => _num(v).toInt();

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
class PdksStatus {
  const PdksStatus({
    required this.workDate,
    required this.isInside,
    required this.shifts,
    required this.logs,
    this.store,
    this.openSince,
  });

  final String workDate;
  final bool isInside;
  final List<PdksShift> shifts;
  final List<AttendanceLog> logs;
  final PdksStore? store;
  final String? openSince;

  bool get canUseGps =>
      (store?.pdksEnabled ?? false) && (store?.hasLocation ?? false);
  bool get canUseQr => store?.pdksEnabled ?? false;

  factory PdksStatus.fromJson(Map<String, dynamic> j) => PdksStatus(
    workDate: j['work_date'] as String? ?? '',
    isInside: j['is_inside'] == true,
    openSince: j['open_since'] as String?,
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
  });

  final int userId;
  final String fullName;
  final String? role;
  final String? storeName;
  final List<TimesheetDay> days;
  final TimesheetSummary summary;

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
  });

  final String from;
  final String to;
  final List<TimesheetPerson> items;
  final TimesheetSummary total;
  final List<String> notes;

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
  );

  static const empty = TimesheetReport(
    from: '',
    to: '',
    items: [],
    total: TimesheetSummary.empty,
    notes: [],
  );
}
