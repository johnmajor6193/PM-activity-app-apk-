import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/network/api_config.dart';
import '../domain/auth_failure.dart';

/// Raw HTTP client for the auth endpoints. Kept separate from
/// [DevLoginAuthRepository] (../data/dev_login_auth_repository.dart) so the
/// wire format can change independently of the domain-facing repository.
class AuthApiClient {
  AuthApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  /// POSTs to /api/v1/auth/login and returns the decoded JSON body.
  /// Throws [AuthFailure] with a user-facing message on any error.
  Future<Map<String, dynamic>> login({
    required String employeeId,
    required String mobileNumber,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/auth/login');

    http.Response response;
    try {
      response = await _httpClient.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'employee_id': employeeId,
          'mobile_number': mobileNumber,
        }),
      );
    } on SocketException {
      throw const AuthFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    final Map<String, dynamic> body = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode == 200) {
      return body;
    }

    throw AuthFailure(_extractErrorMessage(body));
  }

  String _extractErrorMessage(Map<String, dynamic> body) {
    final detail = body['detail'];
    if (detail is String) {
      return detail;
    }
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] is String) {
        return first['msg'] as String;
      }
    }
    return 'Login failed. Please try again.';
  }
}
