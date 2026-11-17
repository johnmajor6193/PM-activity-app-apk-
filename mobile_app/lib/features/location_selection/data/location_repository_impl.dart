import '../domain/entities/block.dart';
import '../domain/entities/district.dart';
import '../domain/entities/gp.dart';
import '../domain/entities/pop_detail.dart';
import '../domain/entities/pop_summary.dart';
import '../domain/repositories/location_repository.dart';
import 'location_api_client.dart';

/// [LocationRepository] backed by the backend's /api/v1/locations
/// endpoints.
class LocationRepositoryImpl implements LocationRepository {
  LocationRepositoryImpl({LocationApiClient? apiClient})
      : _apiClient = apiClient ?? LocationApiClient();

  final LocationApiClient _apiClient;

  @override
  Future<List<District>> getDistricts() async {
    final json = await _apiClient.getDistricts();
    return json
        .map((item) => District(id: item['id'] as int, name: item['name'] as String))
        .toList();
  }

  @override
  Future<List<Block>> getBlocks(int districtId) async {
    final json = await _apiClient.getBlocks(districtId);
    return json
        .map(
          (item) => Block(
            id: item['id'] as int,
            name: item['name'] as String,
            districtId: item['district_id'] as int,
          ),
        )
        .toList();
  }

  @override
  Future<List<Gp>> getGps(int blockId) async {
    final json = await _apiClient.getGps(blockId);
    return json
        .map(
          (item) => Gp(
            id: item['id'] as int,
            name: item['name'] as String,
            blockId: item['block_id'] as int,
          ),
        )
        .toList();
  }

  @override
  Future<List<PopSummary>> getPops(int gpId, {bool activeOnly = true}) async {
    final json = await _apiClient.getPops(gpId, activeOnly: activeOnly);
    return json
        .map(
          (item) => PopSummary(
            id: item['id'] as int,
            popCode: item['pop_code'] as String,
            name: item['name'] as String?,
            isActive: item['is_active'] as bool,
            gpId: item['gp_id'] as int,
          ),
        )
        .toList();
  }

  @override
  Future<PopDetail> getPopDetail(int popId) async {
    final json = await _apiClient.getPopDetail(popId);
    return PopDetail(
      id: json['id'] as int,
      popCode: json['pop_code'] as String,
      name: json['name'] as String?,
      isActive: json['is_active'] as bool,
      gpId: json['gp_id'] as int,
      gpName: json['gp_name'] as String,
      blockName: json['block_name'] as String,
      districtName: json['district_name'] as String,
    );
  }
}
