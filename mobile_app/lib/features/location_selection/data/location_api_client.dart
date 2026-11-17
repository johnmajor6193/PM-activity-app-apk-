import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/network/api_config.dart';
import '../domain/location_failure.dart';

/// Raw HTTP client for the /api/v1/locations endpoints. Kept separate
/// from LocationRepositoryImpl (./location_repository_impl.dart) so the
/// wire format can change independently of the domain-facing repository.
class LocationApiClient {
  LocationApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<List<dynamic>> getDistricts() => _getList('/api/v1/locations/districts');

  Future<List<dynamic>> getBlocks(int districtId) =>
      _getList('/api/v1/locations/districts/$districtId/blocks');

  Future<List<dynamic>> getGps(int blockId) =>
      _getList('/api/v1/locations/blocks/$blockId/gps');

  Future<List<dynamic>> getPops(int gpId, {bool activeOnly = true}) =>
      _getList('/api/v1/locations/gps/$gpId/pops?active_only=$activeOnly');

  Future<Map<String, dynamic>> getPopDetail(int popId) async {
    final decoded = await _get('/api/v1/locations/pops/$popId');
    return decoded as Map<String, dynamic>;
  }

  Future<List<dynamic>> _getList(String path) async {
    final decoded = await _get(path);
    return decoded as List<dynamic>;
  }

  Future<dynamic> _get(String path) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');

    http.Response response;
    try {
      response = await _httpClient.get(uri);
    } on SocketException {
      throw const LocationFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    final dynamic decoded = response.body.isNotEmpty ? jsonDecode(response.body) : null;

    if (response.statusCode == 200) {
      return decoded;
    }

    final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
    throw LocationFailure(detail is String ? detail : 'Request failed. Please try again.');
  }
}
