import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../domain/entities/gps_reading.dart';
import '../domain/entities/photo_category.dart';
import '../domain/pm_visit_failure.dart';

/// Burns a visible GPS/metadata watermark into a copy of a captured PM
/// visit photo, leaving the original file untouched.
///
/// This is pure-Dart image manipulation (`package:image`) — no platform
/// channel is involved, so unlike the camera/GPS services, this can run
/// (and be tested) without an Android toolchain, emulator, or device.
///
/// The watermark layout (bottom banner, field order, font, colors) is
/// fixed and identical for all 5 photo categories (see
/// `_watermarkLines`), so every confirmed photo looks consistent.
class WatermarkService {
  // img.ColorRgba8 and img.arial24 are not const constructors/values, so
  // these are `static final` rather than `static const`.
  static final _bannerColor = img.ColorRgba8(0, 0, 0, 170);
  static final _textColor = img.ColorRgba8(255, 255, 255, 255);
  static const _horizontalMargin = 16;
  static const _verticalPadding = 10;
  static const _lineSpacing = 4;
  static final _font = img.arial24;

  /// Reads the photo at [originalFilePath], draws the watermark
  /// described by the other parameters onto a copy, and writes the
  /// result to a sibling `<name>_watermarked.jpg` file. Returns the new
  /// file's path. [originalFilePath] itself is never modified.
  ///
  /// Throws [PmVisitFailure] if the file cannot be read as an image.
  Future<String> applyWatermark({
    required String originalFilePath,
    required String popCode,
    required PhotoCategory category,
    required DateTime capturedAt,
    required GpsReading gps,
  }) async {
    final bytes = await File(originalFilePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const PmVisitFailure(
        'Could not read the captured photo to add the GPS watermark.',
      );
    }

    final watermarked = _drawWatermark(
      decoded,
      watermarkLines(popCode: popCode, category: category, capturedAt: capturedAt, gps: gps),
    );

    final destinationPath = _watermarkedPathFor(originalFilePath);
    await File(destinationPath).writeAsBytes(img.encodeJpg(watermarked, quality: 90));
    return destinationPath;
  }

  /// The exact text lines rendered into the watermark, in order. Exposed
  /// (not private) so tests can assert the GPS values shown here match
  /// what is stored in the photo record for the same capture.
  List<String> watermarkLines({
    required String popCode,
    required PhotoCategory category,
    required DateTime capturedAt,
    required GpsReading gps,
  }) {
    final local = capturedAt.toLocal();
    final date = '${_pad4(local.year)}-${_pad2(local.month)}-${_pad2(local.day)}';
    final time = '${_pad2(local.hour)}:${_pad2(local.minute)}:${_pad2(local.second)}';

    return [
      'TANFINET',
      'POP ID: $popCode',
      category.label,
      '$date  $time',
      'Lat: ${gps.latitude.toStringAsFixed(6)}  Lng: ${gps.longitude.toStringAsFixed(6)}',
      'GPS Accuracy: ±${gps.accuracyMeters.toStringAsFixed(1)} m',
    ];
  }

  /// Draws a solid banner across the bottom of [source] and the given
  /// [lines] of text on top of it, then returns [source] (mutated in
  /// place — `package:image` draw operations work this way). The banner
  /// is sized to fit the text and anchored to the bottom edge only, so
  /// it never reaches into the upper/central part of the photo where the
  /// equipment being inspected is expected to be.
  img.Image _drawWatermark(img.Image source, List<String> lines) {
    final lineHeight = _font.lineHeight + _lineSpacing;
    final bannerHeight = (_verticalPadding * 2) + (lines.length * lineHeight);
    final top = (source.height - bannerHeight).clamp(0, source.height);

    img.fillRect(
      source,
      x1: 0,
      y1: top,
      x2: source.width,
      y2: source.height,
      color: _bannerColor,
    );

    var y = top + _verticalPadding;
    for (final line in lines) {
      img.drawString(source, line, font: _font, x: _horizontalMargin, y: y, color: _textColor);
      y += lineHeight;
    }

    return source;
  }

  String _watermarkedPathFor(String originalFilePath) {
    final dir = p.dirname(originalFilePath);
    final nameWithoutExt = p.basenameWithoutExtension(originalFilePath);
    return p.join(dir, '${nameWithoutExt}_watermarked.jpg');
  }

  String _pad2(int value) => value.toString().padLeft(2, '0');

  String _pad4(int value) => value.toString().padLeft(4, '0');
}
