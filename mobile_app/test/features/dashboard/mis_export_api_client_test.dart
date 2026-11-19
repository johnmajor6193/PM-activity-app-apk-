import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/network/auth_session.dart';
import 'package:mobile_app/features/dashboard/data/mis_export_api_client.dart';
import 'package:mobile_app/features/dashboard/domain/dashboard_failure.dart';

/// Exercises the real HTTP request-building logic (path, query
/// params, the Authorization header) and binary-body handling for
/// `GET /api/v1/mis/export` against a fake transport (`MockClient`) —
/// mirrors dashboard_api_client_test.dart's approach for the existing
/// JSON endpoints; see backend/tests/test_mis_export.py for the
/// backend-side endpoint tests this already-implemented API is
/// verified against.
void main() {
  setUp(() {
    AuthSession.instance.accessToken = null;
  });

  tearDown(() {
    AuthSession.instance.accessToken = null;
  });

  test('downloadXlsx requests the export path with year/month/format=xlsx', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes([1, 2, 3], 200);
    });

    final bytes = await MisExportApiClient(httpClient: client).downloadXlsx(year: 2026, month: 11);

    expect(captured!.url.path, '/api/v1/mis/export');
    expect(captured!.url.queryParameters['year'], '2026');
    expect(captured!.url.queryParameters['month'], '11');
    expect(captured!.url.queryParameters['format'], 'xlsx');
    expect(bytes, [1, 2, 3]);
  });

  test('attaches Authorization: Bearer <token> when a session token exists', () async {
    AuthSession.instance.accessToken = 'test-jwt-token';
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes([], 200);
    });

    await MisExportApiClient(httpClient: client).downloadXlsx(year: 2026, month: 11);

    expect(captured!.headers['Authorization'], 'Bearer test-jwt-token');
  });

  test('sends no Authorization header when there is no session token', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes([], 200);
    });

    await MisExportApiClient(httpClient: client).downloadXlsx(year: 2026, month: 11);

    expect(captured!.headers.containsKey('Authorization'), isFalse);
  });

  test('throws DashboardFailure with the backend detail on a non-200 response', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'detail': 'Could not validate credentials.'}), 401),
    );

    await expectLater(
      MisExportApiClient(httpClient: client).downloadXlsx(year: 2026, month: 11),
      throwsA(
        isA<DashboardFailure>().having(
          (f) => f.message,
          'message',
          'Could not validate credentials.',
        ),
      ),
    );
  });

  test('throws a generic DashboardFailure when the error body has no detail', () async {
    final client = MockClient((request) async => http.Response('', 500));

    await expectLater(
      MisExportApiClient(httpClient: client).downloadXlsx(year: 2026, month: 11),
      throwsA(isA<DashboardFailure>()),
    );
  });
}
