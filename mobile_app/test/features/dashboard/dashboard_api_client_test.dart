import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/network/auth_session.dart';
import 'package:mobile_app/features/dashboard/data/dashboard_api_client.dart';
import 'package:mobile_app/features/dashboard/domain/dashboard_failure.dart';

/// Exercises the real HTTP request-building logic (path, query params,
/// the Authorization header) against a fake transport
/// (`package:http`'s `MockClient`) — no real backend involved here.
/// See backend/tests/test_dashboard.py for the backend-side endpoint
/// tests this API is already verified against.
void main() {
  setUp(() {
    AuthSession.instance.accessToken = null;
  });

  tearDown(() {
    AuthSession.instance.accessToken = null;
  });

  test('getDistrictDashboard requests the districts path and decodes the body', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'period_start': '2026-11-16', 'period_end': '2026-11-30', 'districts': []}),
        200,
      );
    });

    final result = await DashboardApiClient(httpClient: client).getDistrictDashboard();

    expect(captured!.url.path, '/api/v1/dashboard/districts');
    expect(result['period_start'], '2026-11-16');
    expect(result['districts'], isEmpty);
  });

  test('getDistrictDashboard attaches the date query parameter when given', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'period_start': '2026-11-01', 'period_end': '2026-11-15', 'districts': []}),
        200,
      );
    });

    await DashboardApiClient(httpClient: client).getDistrictDashboard(date: '2026-11-05');

    expect(captured!.url.queryParameters['date'], '2026-11-05');
  });

  test('getDistrictDashboard omits the date parameter when not given', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'period_start': '2026-11-01', 'period_end': '2026-11-15', 'districts': []}),
        200,
      );
    });

    await DashboardApiClient(httpClient: client).getDistrictDashboard();

    expect(captured!.url.queryParameters.containsKey('date'), isFalse);
  });

  test('getEngineerDashboard requests the engineers path', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'period_start': '2026-11-16', 'period_end': '2026-11-30', 'engineers': []}),
        200,
      );
    });

    final result = await DashboardApiClient(httpClient: client).getEngineerDashboard();

    expect(captured!.url.path, '/api/v1/dashboard/engineers');
    expect(result['engineers'], isEmpty);
  });

  test('getPopVisitHistory requests the per-POP visits path', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode([]), 200);
    });

    final result = await DashboardApiClient(httpClient: client).getPopVisitHistory(42);

    expect(captured!.url.path, '/api/v1/dashboard/pops/42/visits');
    expect(result, isEmpty);
  });

  test('attaches Authorization: Bearer <token> when a session token exists', () async {
    AuthSession.instance.accessToken = 'test-jwt-token';
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode([]), 200);
    });

    await DashboardApiClient(httpClient: client).getPopVisitHistory(1);

    expect(captured!.headers['Authorization'], 'Bearer test-jwt-token');
  });

  test('sends no Authorization header when there is no session token', () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode([]), 200);
    });

    await DashboardApiClient(httpClient: client).getPopVisitHistory(1);

    expect(captured!.headers.containsKey('Authorization'), isFalse);
  });

  test('throws DashboardFailure with the backend detail on a 401', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'detail': 'Could not validate credentials.'}), 401),
    );

    await expectLater(
      DashboardApiClient(httpClient: client).getDistrictDashboard(),
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
      DashboardApiClient(httpClient: client).getEngineerDashboard(),
      throwsA(isA<DashboardFailure>()),
    );
  });
}
