import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/features/pm_visit/data/google_drive_upload_service.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/gps_reading.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/pm_photo_record.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/pm_visit.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/photo_category.dart';
import 'package:mobile_app/features/pm_visit/domain/pm_visit_failure.dart';

/// These tests exercise the real HTTP request-building logic (fields,
/// multipart files, error handling) against a fake transport
/// (`package:http`'s `MockClient`) — there is no real backend here, so
/// nothing in this file touches an actual server or Google Drive. See
/// backend/tests/test_drive_sync.py for the backend-side endpoint
/// tests, and the top-level report for what remains untested without
/// real Google credentials.
void main() {
  late Directory tempDir;
  late PmVisit visit;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('drive_upload_test_');
    visit = PmVisit(
      id: 'visit-1',
      employeeId: 'ENG001',
      popId: 7,
      popCode: 'POP-00125',
      districtName: 'Chennai',
      blockName: 'Sholinganallur',
      gpName: 'Semmancheri GP',
      startedAt: DateTime(2026, 11, 17, 9, 0, 0),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<List<PmPhotoRecord>> buildPhotosWithRealFiles() async {
    final photos = <PmPhotoRecord>[];
    for (final category in mandatoryPhotoCategories) {
      final originalPath = '${tempDir.path}/${category.storageKey}.jpg';
      final watermarkedPath = '${tempDir.path}/${category.storageKey}_watermarked.jpg';
      await File(originalPath).writeAsBytes(utf8.encode('ORIGINAL_CONTENT_MARKER_${category.storageKey}'));
      await File(watermarkedPath).writeAsBytes(
        utf8.encode('WATERMARKED_CONTENT_MARKER_${category.storageKey}'),
      );
      photos.add(
        PmPhotoRecord(
          visitId: 'visit-1',
          popId: 7,
          category: category,
          localFilePath: originalPath,
          watermarkedFilePath: watermarkedPath,
          capturedAt: DateTime(2026, 11, 17, 17, 25, 42),
          gps: const GpsReading(latitude: 11.123456, longitude: 77.654321, accuracyMeters: 4.2),
        ),
      );
    }
    return photos;
  }

  test('sends only the watermarked files, never the plain originals', () async {
    http.BaseRequest? captured;
    List<int>? capturedBody;
    final client = MockClient.streaming((request, bodyStream) async {
      captured = request;
      capturedBody = await bodyStream.toBytes();
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'status': 'synced', 'photos': []}))),
        200,
      );
    });

    final service = GoogleDriveUploadService(httpClient: client);
    final photos = await buildPhotosWithRealFiles();

    await service.uploadVisit(visit, photos);

    expect(captured, isA<http.MultipartRequest>());
    final multipart = captured! as http.MultipartRequest;
    expect(multipart.files.length, 5);

    final bodyText = latin1.decode(capturedBody!, allowInvalid: true);
    for (final category in mandatoryPhotoCategories) {
      expect(bodyText, contains('WATERMARKED_CONTENT_MARKER_${category.storageKey}'));
      expect(bodyText, isNot(contains('ORIGINAL_CONTENT_MARKER_${category.storageKey}')));
    }
  });

  test('sends visit and per-photo metadata matching the visit/photo records', () async {
    http.MultipartRequest? captured;
    final client = MockClient.streaming((request, bodyStream) async {
      captured = request as http.MultipartRequest;
      await bodyStream.drain<void>();
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'status': 'synced', 'photos': []}))),
        200,
      );
    });

    final service = GoogleDriveUploadService(httpClient: client);
    final photos = await buildPhotosWithRealFiles();

    await service.uploadVisit(visit, photos);

    final visitMetadata = jsonDecode(captured!.fields['visit_metadata']!) as Map<String, dynamic>;
    expect(visitMetadata['visit_id'], 'visit-1');
    expect(visitMetadata['employee_id'], 'ENG001');
    expect(visitMetadata['pop_id'], 7);
    expect(visitMetadata['pop_code'], 'POP-00125');
    expect(visitMetadata['district'], 'Chennai');
    expect(visitMetadata['block'], 'Sholinganallur');
    expect(visitMetadata['gp'], 'Semmancheri GP');
    expect(visitMetadata['visit_date'], '2026-11-17');

    final photosMetadata = jsonDecode(captured!.fields['photos_metadata']!) as List<dynamic>;
    expect(photosMetadata.length, 5);
    final popRackEntry = photosMetadata.firstWhere((p) => p['category'] == 'pop_rack') as Map;
    expect(popRackEntry['latitude'], 11.123456);
    expect(popRackEntry['longitude'], 77.654321);
    expect(popRackEntry['accuracy_m'], 4.2);
  });

  test('throws when the backend reports a failure', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(jsonEncode({'status': 'failed', 'message': 'Google Drive is not configured.'})),
        ),
        200,
      );
    });

    final service = GoogleDriveUploadService(httpClient: client);
    final photos = await buildPhotosWithRealFiles();

    await expectLater(
      service.uploadVisit(visit, photos),
      throwsA(
        isA<PmVisitFailure>().having((f) => f.message, 'message', contains('not configured')),
      ),
    );
  });

  test('throws when the backend returns a non-200 response', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(Stream.value(utf8.encode('{"detail": "Server error"}')), 500);
    });

    final service = GoogleDriveUploadService(httpClient: client);
    final photos = await buildPhotosWithRealFiles();

    await expectLater(service.uploadVisit(visit, photos), throwsA(isA<PmVisitFailure>()));
  });

  test('refuses to sync when a mandatory photo is missing', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      return http.StreamedResponse(Stream.value(const []), 200);
    });

    final service = GoogleDriveUploadService(httpClient: client);
    final photos = await buildPhotosWithRealFiles();
    photos.removeWhere((p) => p.category == PhotoCategory.busbar);

    await expectLater(
      service.uploadVisit(visit, photos),
      throwsA(isA<PmVisitFailure>().having((f) => f.message, 'message', contains('Busbar'))),
    );
  });
}
