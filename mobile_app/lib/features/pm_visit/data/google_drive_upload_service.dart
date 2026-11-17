import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/network/api_config.dart';
import '../domain/entities/pm_photo_record.dart';
import '../domain/entities/pm_visit.dart';
import '../domain/entities/photo_category.dart';
import '../domain/pm_visit_failure.dart';
import '../domain/services/drive_upload_service.dart';

/// Real [DriveUploadService]: uploads a visit's confirmed photos to
/// Google Drive via the backend's upload endpoint
/// (`POST /api/v1/visits/{visitId}/sync`) — **not** directly from this
/// device. Google service-account credentials never exist on the
/// phone; the backend holds them and performs the actual Drive calls
/// (see `backend/app/services/drive/`).
///
/// Only the GPS-**watermarked** copy of each photo
/// (`PmPhotoRecord.watermarkedFilePath`) is sent. The plain original
/// (`localFilePath`) is never uploaded — it stays device-local per the
/// existing offline-storage design.
class GoogleDriveUploadService implements DriveUploadService {
  GoogleDriveUploadService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  Future<void> uploadVisit(PmVisit visit, List<PmPhotoRecord> photos) async {
    final photosByCategory = {for (final photo in photos) photo.category: photo};
    for (final category in mandatoryPhotoCategories) {
      final photo = photosByCategory[category];
      if (photo == null || photo.watermarkedFilePath == null) {
        throw PmVisitFailure(
          'Missing watermarked photo for ${category.label}; cannot sync an incomplete visit.',
        );
      }
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/visits/${visit.id}/sync');
    final request = http.MultipartRequest('POST', uri)
      ..fields['visit_metadata'] = jsonEncode({
        'visit_id': visit.id,
        'employee_id': visit.employeeId,
        'pop_id': visit.popId,
        'pop_code': visit.popCode,
        'district': visit.districtName,
        'block': visit.blockName,
        'gp': visit.gpName,
        'visit_date': _dateOnly(visit.startedAt),
      });

    final photosMetadata = <Map<String, dynamic>>[];
    for (final category in mandatoryPhotoCategories) {
      final photo = photosByCategory[category]!;
      photosMetadata.add({
        'category': photo.category.storageKey,
        'captured_at': photo.capturedAt.toIso8601String(),
        'latitude': photo.gps.latitude,
        'longitude': photo.gps.longitude,
        'accuracy_m': photo.gps.accuracyMeters,
      });
      request.files.add(
        await http.MultipartFile.fromPath('files', photo.watermarkedFilePath!),
      );
    }
    request.fields['photos_metadata'] = jsonEncode(photosMetadata);

    http.StreamedResponse streamed;
    try {
      streamed = await _httpClient.send(request);
    } on SocketException {
      throw const PmVisitFailure(
        'Could not reach the sync server. Check your connection and try again.',
      );
    }
    final response = await http.Response.fromStream(streamed);

    final Map<String, dynamic> body = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw PmVisitFailure(_extractErrorMessage(body));
    }
    if (body['status'] != 'synced') {
      throw PmVisitFailure(_extractErrorMessage(body));
    }
  }

  String _extractErrorMessage(Map<String, dynamic> body) {
    final message = body['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
    final detail = body['detail'];
    if (detail is String) {
      return detail;
    }
    return 'Google Drive upload failed. Please try again.';
  }

  String _dateOnly(DateTime dateTime) {
    final local = dateTime.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
