import '../entities/block.dart';
import '../entities/district.dart';
import '../entities/gp.dart';
import '../entities/pop_detail.dart';
import '../entities/pop_summary.dart';

/// Abstraction over the District → Block → GP → POP master data lookup.
///
/// Implemented by LocationRepositoryImpl (../data/), which calls the
/// backend's /api/v1/locations endpoints. No GPS/geofence methods here —
/// see PopSummary/PopDetail for why.
abstract class LocationRepository {
  Future<List<District>> getDistricts();

  Future<List<Block>> getBlocks(int districtId);

  Future<List<Gp>> getGps(int blockId);

  Future<List<PopSummary>> getPops(int gpId, {bool activeOnly = true});

  Future<PopDetail> getPopDetail(int popId);
}
