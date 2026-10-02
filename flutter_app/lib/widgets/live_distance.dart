import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/tokens.dart';

/// Mağazaya canlı uzaklık durumu.
sealed class DistanceState {
  const DistanceState();
}

class DistanceLoading extends DistanceState {
  const DistanceLoading();
}

class DistanceUnavailable extends DistanceState {
  const DistanceUnavailable(this.reason);
  final String reason;
}

class DistanceKnown extends DistanceState {
  const DistanceKnown(this.meters, this.accuracy);
  final double meters;
  final double accuracy;
}

/// "42 m" / "1,2 km".
String formatDistance(double m) => m < 1000
    ? '${m.round()} m'
    : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

/// Cihaz konumunu ekran açıkken canlı izleyip mağazaya uzaklığı verir.
///
/// KVKK: konum yalnızca bu ekran açıkken cihazda kullanılır, sunucuya
/// gönderilmez; ekran kapanınca izleme durur. Giriş/çıkış kaydındaki konum
/// yine okutma anında ayrıca alınır.
class LiveStoreDistance extends StatefulWidget {
  const LiveStoreDistance({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.builder,
  });

  final double? latitude;
  final double? longitude;
  final Widget Function(BuildContext context, DistanceState state) builder;

  @override
  State<LiveStoreDistance> createState() => _LiveStoreDistanceState();
}

class _LiveStoreDistanceState extends State<LiveStoreDistance> {
  DistanceState _state = const DistanceLoading();
  StreamSubscription<Position>? _sub;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(LiveStoreDistance old) {
    super.didUpdateWidget(old);
    if (old.latitude != widget.latitude || old.longitude != widget.longitude) {
      _sub?.cancel();
      _start();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _set(DistanceState s) {
    if (mounted) setState(() => _state = s);
  }

  void _onPosition(Position p) {
    final lat = widget.latitude;
    final lng = widget.longitude;
    if (lat == null || lng == null) return;
    final m = Geolocator.distanceBetween(p.latitude, p.longitude, lat, lng);
    _set(DistanceKnown(m, p.accuracy));
  }

  Future<void> _start() async {
    if (widget.latitude == null || widget.longitude == null) {
      _set(const DistanceUnavailable('Mağaza konumu tanımlı değil'));
      return;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _set(const DistanceUnavailable('Konum servisi kapalı'));
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _set(const DistanceUnavailable('Konum izni yok'));
        return;
      }
      _sub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 3,
            ),
          ).listen(
            _onPosition,
            onError: (_) => _set(const DistanceUnavailable('Konum alınamadı')),
          );
    } catch (_) {
      // Eklentisi olmayan platform (masaüstü, test) ya da izin hatası.
      _set(const DistanceUnavailable('Konum alınamadı'));
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _state);
}

/// Hazır gösterim: "GPS: 42 m · sınır 100 m" — sınır içinde yeşil, dışında
/// uyarı renginde.
class LiveDistanceLabel extends StatelessWidget {
  const LiveDistanceLabel({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    this.prefix = 'GPS: ',
    this.showRadius = true,
    this.fontSize = AppFontSize.label,
  });

  final double? latitude;
  final double? longitude;
  final int radiusM;
  final String prefix;
  final bool showRadius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LiveStoreDistance(
      latitude: latitude,
      longitude: longitude,
      builder: (context, state) {
        final (text, color, icon) = switch (state) {
          DistanceLoading() => (
            '${prefix}konum alınıyor…',
            t.muted,
            Icons.gps_not_fixed,
          ),
          DistanceUnavailable(:final reason) => (
            '$prefix$reason',
            t.muted,
            Icons.gps_off,
          ),
          DistanceKnown(:final meters) => (
            '$prefix${formatDistance(meters)}'
                '${showRadius ? ' · sınır $radiusM m' : ''}',
            meters <= radiusM ? t.success : t.warning,
            Icons.gps_fixed,
          ),
        };
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: fontSize + 3, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
