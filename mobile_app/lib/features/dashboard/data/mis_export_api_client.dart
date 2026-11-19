import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/network/api_config.dart';
import '../../../core/network/auth_session.dart';
import '../domain/dashboard_failure.dart';

/// Thin HTTP client for the backend's already-implemented
/// `GET /api/v1/mis/export` endpoint (see
/// backend/app/api/v1/endpoints/mis.py). Kept separate from
/// [DashboardApiClient] because that endpoint always JSON-decodes its
/// response body, which doesn't work for this endpoint's binary
/// (.xlsx) body — the auth/session handling is identical, reused as-is
/// via [AuthSession], not reimplemented.
class MisExportApiClient {
  MisExportApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  /// Downloads the Excel (.xlsx) MIS report for [year]/[month]. Throws
  /// [DashboardFailure] with a user-facing message on any failure.
  Future<List<int>> downloadXlsx({required int year, required int month}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/mis/export').replace(
      queryParameters: {'year': '$year', 'month': '$month', 'format': 'xlsx'},
    );
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

    if (response.statusCode == 200) {
      return response.bodyBytes;
    }

    throw DashboardFailure(_errorMessage(response));
  }

  String _errorMessage(http.Response response) {
    if (response.body.isEmpty) {
      return 'Could not download the MIS report. Please try again.';
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } catch (_) {
      // Error body wasn't JSON — fall through to the generic message.
    }
    return 'Could not download the MIS report. Please try again.';
  }
}
