import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/features/pm_visit/data/watermark_service.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/gps_reading.dart';
import 'package:mobile_app/features/pm_visit/domain/entities/photo_category.dart';
import 'package:mobile_app/features/pm_visit/domain/pm_visit_failure.dart';

/// These tests exercise the real `package:image` pixel operations — no
/// fakes/mocks involved, unlike the camera/GPS plugin tests elsewhere in
/// this module. This is possible because watermarking is pure Dart with
/// no platform channel, so it is one of the few pieces of this feature
/// that can be verified end-to-end (file in, file out, real pixels) in
/// this environment, without a device, emulator, or Android toolchain.
void main() {
  late Directory tempDir;
  late WatermarkService service;

  const testGps = GpsReading(latitude: 11.123456, longitude: 77.654321, accuracyMeters: 4.2);
  final testCapturedAt = DateTime(2026, 2, 14, 9, 30, 15);
  final backgroundColor = img.ColorRgba8(10, 120, 200, 255); // not a const constructor

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('watermark_test_');
    service = WatermarkService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // Written as PNG (lossless) so the pixel-level assertions below aren't
  // affected by JPEG compression artifacts from this test fixture itself
  // — applyWatermark's own JPEG re-encode is still exercised for real.
  Future<String> writeSolidTestImage({int width = 400, int height = 600}) async {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: backgroundColor);
    final path = '${tempDir.path}/original.png';
    await File(path).writeAsBytes(img.encodePng(image));
    return path;
  }

  // The watermarked output is re-encoded as JPEG (quality 90), which is
  // lossy, so pixel checks against it use a small tolerance rather than
  // exact equality.
  bool approxEqual(num a, num b, {num tolerance = 10}) => (a - b).abs() <= tolerance;

  test('writes a separate watermarked file and leaves the original byte-for-byte untouched', () async {
    final originalPath = await writeSolidTestImage();
    final originalBytesBefore = await File(originalPath).readAsBytes();

    final watermarkedPath = await service.applyWatermark(
      originalFilePath: originalPath,
      popCode: 'POP-CHN-001',
      category: PhotoCategory.popRack,
      capturedAt: testCapturedAt,
      gps: testGps,
    );

    expect(watermarkedPath, isNot(originalPath));
    expect(watermarkedPath, endsWith('_watermarked.jpg'));
    expect(await File(watermarkedPath).exists(), isTrue);

    final originalBytesAfter = await File(originalPath).readAsBytes();
    expect(originalBytesAfter, equals(originalBytesBefore));
  });

  test('keeps image dimensions unchanged and does not obscure the top of the photo', () async {
    final originalPath = await writeSolidTestImage(width: 400, height: 600);

    final watermarkedPath = await service.applyWatermark(
      originalFilePath: originalPath,
      popCode: 'POP-CHN-001',
      category: PhotoCategory.popRack,
      capturedAt: testCapturedAt,
      gps: testGps,
    );

    final watermarked = img.decodeImage(await File(watermarkedPath).readAsBytes())!;
    expect(watermarked.width, 400);
    expect(watermarked.height, 600);

    // The subject of a PM photo is expected in the upper/central area;
    // the watermark banner must not reach up there. Tolerance accounts
    // for JPEG re-encoding, not a behavior change.
    final topPixel = watermarked.getPixel(10, 10);
    expect(approxEqual(topPixel.r, backgroundColor.r), isTrue);
    expect(approxEqual(topPixel.g, backgroundColor.g), isTrue);
    expect(approxEqual(topPixel.b, backgroundColor.b), isTrue);
  });

  test('draws a visibly different banner near the bottom of the photo', () async {
    final originalPath = await writeSolidTestImage(width: 400, height: 600);

    final watermarkedPath = await service.applyWatermark(
      originalFilePath: originalPath,
      popCode: 'POP-CHN-001',
      category: PhotoCategory.popRack,
      capturedAt: testCapturedAt,
      gps: testGps,
    );

    final watermarked = img.decodeImage(await File(watermarkedPath).readAsBytes())!;
    final bottomPixel = watermarked.getPixel(5, watermarked.height - 5);

    // The banner is a dark semi-transparent fill; a pixel inside it
    // should no longer match the bright, solid background color.
    final changed =
        bottomPixel.r != backgroundColor.r ||
        bottomPixel.g != backgroundColor.g ||
        bottomPixel.b != backgroundColor.b;
    expect(changed, isTrue);
  });

  test('watermark lines contain exactly the required fields, formatted from the given GPS', () {
    final lines = service.watermarkLines(
      popCode: 'POP-CHN-001',
      category: PhotoCategory.popRack,
      capturedAt: testCapturedAt,
      gps: testGps,
    );

    expect(lines[0], 'TANFINET');
    expect(lines[1], 'POP ID: POP-CHN-001');
    expect(lines[2], 'POP Rack');
    expect(lines[3], '2026-02-14  09:30:15');
    expect(lines[4], 'Lat: 11.123456  Lng: 77.654321');
    expect(lines[5], 'GPS Accuracy: ±4.2 m');
  });

  test('watermark GPS fields exactly match the GpsReading values passed in', () {
    const gps = GpsReading(latitude: -8.5, longitude: 150.25, accuracyMeters: 12.75);

    final lines = service.watermarkLines(
      popCode: 'POP-MDU-002',
      category: PhotoCategory.busbar,
      capturedAt: testCapturedAt,
      gps: gps,
    );

    expect(lines, contains('Lat: ${gps.latitude.toStringAsFixed(6)}  Lng: ${gps.longitude.toStringAsFixed(6)}'));
    expect(lines, contains('GPS Accuracy: ±${gps.accuracyMeters.toStringAsFixed(1)} m'));
  });

  test('formatting is identical in structure for all 5 mandatory categories', () {
    for (final category in mandatoryPhotoCategories) {
      final lines = service.watermarkLines(
        popCode: 'POP-CHN-001',
        category: category,
        capturedAt: testCapturedAt,
        gps: testGps,
      );

      expect(lines.length, 6, reason: '${category.label} should have 6 watermark lines');
      expect(lines[0], 'TANFINET');
      expect(lines[1], 'POP ID: POP-CHN-001');
      expect(lines[2], category.label);
    }
  });

  test('throws PmVisitFailure for a file that is not a decodable image', () async {
    final badPath = '${tempDir.path}/not_an_image.jpg';
    await File(badPath).writeAsBytes([1, 2, 3, 4, 5]);

    expect(
      () => service.applyWatermark(
        originalFilePath: badPath,
        popCode: 'POP-CHN-001',
        category: PhotoCategory.popRack,
        capturedAt: testCapturedAt,
        gps: testGps,
      ),
      throwsA(isA<PmVisitFailure>()),
    );
  });
}
