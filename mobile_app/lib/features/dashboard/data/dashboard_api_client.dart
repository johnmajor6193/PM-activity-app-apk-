import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/network/api_config.dart';
import '../../../core/network/auth_session.dart';
import '../domain/dashboard_failure.dart';

/// Raw HTTP client for the /api/v1/dashboard endpoints. Kept separate
/// from DashboardRepositoryImpl (./dashboard_repository_impl.dart) so
/// the wire format can change independently of the domain-facing
/// repository — same split as LocationApiClient/LocationRepositoryImpl.
///
/// Attaches the same JWT every other protected call uses
/// (AuthSession, set once at login by DevLoginAuthRepository) — no new
/// authentication mechanism.
class DashboardApiClient {
  DashboardApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<Map<String, dynamic>> getDistrictDashboard({String? date}) async {
    final decoded = await _get(
      '/api/v1/dashboard/districts',
      query: date == null ? null : {'date': date},
    );
    return decoded as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getEngineerDashboard({String? date}) async {
    final decoded = await _get(
      '/api/v1/dashboard/engineers',
      query: date == null ? null : {'date': date},
    );
    return decoded as Map<String, dynamic>;
  }

  Future<List<dynamic>> getPopVisitHistory(int popId) async {
    final decoded = await _get('/api/v1/dashboard/pops/$popId/visits');
    return decoded as List<dynamic>;
  }

  Future<dynamic> _get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);
    final token = AuthSession.instance.accessToken;

    http.Response response;
    try {
      response = await _httpClient.get(
        uri,
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
      );
    } on SocketException {
      throw const DashboardFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    final dynamic decoded = response.body.isNotEmpty ? jsonDecode(response.body) : null;

    if (response.statusCode == 200) {
      return decoded;
    }

    final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
    throw DashboardFailure(detail is String ? detail : 'Request failed. Please try again.');
  }
}
