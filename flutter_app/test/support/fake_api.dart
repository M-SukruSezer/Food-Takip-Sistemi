import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:foodtakip/core/api_client.dart';
import 'package:foodtakip/core/session.dart';
import 'package:foodtakip/core/tokens.dart';
import 'package:foodtakip/models/user.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Ekran testleri canli veriyle degil sabit govdelerle calisir: boylece urun
/// verisine dokunmadan hem bicim hem yetki kurallari dogrulanabilir.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes);

  /// `<METOD> <yol>` -> govde
  final Map<String, Object?> routes;

  /// Cagrilan uclar; bir islemin sunucuya hic gitmedigini dogrulamak icin.
  final List<String> calls = [];

  /// Yazma isteklerinin govdeleri, `<METOD> <yol>` anahtariyla.
  final Map<String, Object?> bodies = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final query = options.uri.query;
    final key = '${options.method} ${options.path}${query.isEmpty ? '' : '?$query'}';
    calls.add(key);
    if (options.data != null) bodies[key] = options.data;

    // Bazi repo cagrilari sorguyu yolun icine gomuyor ('/approvals?status=..').
    // Esleme her zaman sorgusuz yol uzerinden yapilir.
    final path = options.path.split('?').first;
    final body = routes['${options.method} $path'];
    if (body == null) {
      return ResponseBody.fromString(
        jsonEncode({'error': 'Tanımsız uç: $key'}),
        404,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Ekrani gercek tema ile, sayfa kenar boslugu dahil kurar.
Widget host(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(Brightness.light),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(12), child: child),
    ),
  );
}

/// Varsayilan yetkiler sunucudaki DEFAULT_PERMISSIONS ile ayni: yeni kullanici
/// imha ve ikram yapabilir. Yetkisiz durumu test etmek icin bos liste verilir.
void signInAs(
  String role, {
  int? storeId,
  int id = 1,
  List<String> permissions = const ['discard', 'ikram'],
}) {
  session.updateUser(AppUser(
    id: id,
    username: 'test',
    fullName: 'Test Kullanici',
    role: role,
    storeId: storeId,
    permissions: permissions,
  ));
}

/// Testin kendi adaptorunu takar, sonunda geri alir.
FakeAdapter installFakeApi(Map<String, Object?> routes) {
  final adapter = FakeAdapter(routes);
  api.dio.httpClientAdapter = adapter;
  return adapter;
}

/// main.dart'in yaptigi yerel veri kurulumu; tarih bicimleri testte de gerekir.
void initTestFormatting() => initializeDateFormatting('tr_TR');
