import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/location_selection/domain/entities/block.dart';
import 'package:mobile_app/features/location_selection/domain/entities/district.dart';
import 'package:mobile_app/features/location_selection/domain/entities/gp.dart';
import 'package:mobile_app/features/location_selection/domain/entities/pop_detail.dart';
import 'package:mobile_app/features/location_selection/domain/entities/pop_summary.dart';
import 'package:mobile_app/features/location_selection/domain/repositories/location_repository.dart';
import 'package:mobile_app/features/location_selection/presentation/pop_selection_controller.dart';

/// Stands in for the real LocationRepository so the controller's
/// cascading-selection logic can be tested without a network call.
class _FakeLocationRepository implements LocationRepository {
  final district = const District(id: 1, name: 'Chennai');
  final block = const Block(id: 10, name: 'Sholinganallur', districtId: 1);
  final gp = const Gp(id: 100, name: 'Semmancheri GP', blockId: 10);
  final pop = const PopSummary(
    id: 1000,
    popCode: 'POP-CHN-001',
    name: 'Semmancheri POP 1',
    isActive: true,
    gpId: 100,
  );

  @override
  Future<List<District>> getDistricts() async => [district];

  @override
  Future<List<Block>> getBlocks(int districtId) async =>
      districtId == district.id ? [block] : [];

  @override
  Future<List<Gp>> getGps(int blockId) async => blockId == block.id ? [gp] : [];

  @override
  Future<List<PopSummary>> getPops(int gpId, {bool activeOnly = true}) async =>
      gpId == gp.id ? [pop] : [];

  @override
  Future<PopDetail> getPopDetail(int popId) async => PopDetail(
        id: pop.id,
        popCode: pop.popCode,
        name: pop.name,
        isActive: pop.isActive,
        gpId: pop.gpId,
        gpName: gp.name,
        blockName: block.name,
        districtName: district.name,
      );
}

void main() {
  test('loadDistricts populates the district list', () async {
    final controller = PopSelectionController(repository: _FakeLocationRepository());

    await controller.loadDistricts();

    expect(controller.districtsStatus, LoadStatus.loaded);
    expect(controller.districts, hasLength(1));
    expect(controller.districts.first.name, 'Chennai');
  });

  test('selecting a district loads its blocks and resets lower levels', () async {
    final fake = _FakeLocationRepository();
    final controller = PopSelectionController(repository: fake);
    await controller.loadDistricts();

    await controller.selectDistrict(fake.district);

    expect(controller.blocksStatus, LoadStatus.loaded);
    expect(controller.blocks, [fake.block]);
    expect(controller.selectedBlock, isNull);
    expect(controller.gps, isEmpty);
    expect(controller.pops, isEmpty);
  });

  test('selecting a POP loads its details with full hierarchy names', () async {
    final fake = _FakeLocationRepository();
    final controller = PopSelectionController(repository: fake);
    await controller.loadDistricts();

    await controller.selectDistrict(fake.district);
    await controller.selectBlock(fake.block);
    await controller.selectGp(fake.gp);
    await controller.selectPop(fake.pop);

    expect(controller.popDetailStatus, LoadStatus.loaded);
    expect(controller.selectedPopDetail?.districtName, 'Chennai');
    expect(controller.selectedPopDetail?.blockName, 'Sholinganallur');
    expect(controller.selectedPopDetail?.gpName, 'Semmancheri GP');
  });

  test('clearing the district selection resets everything downstream', () async {
    final fake = _FakeLocationRepository();
    final controller = PopSelectionController(repository: fake);
    await controller.loadDistricts();

    await controller.selectDistrict(fake.district);
    await controller.selectBlock(fake.block);
    await controller.selectGp(fake.gp);
    await controller.selectPop(fake.pop);

    await controller.selectDistrict(null);

    expect(controller.selectedBlock, isNull);
    expect(controller.selectedGp, isNull);
    expect(controller.selectedPopSummary, isNull);
    expect(controller.selectedPopDetail, isNull);
    expect(controller.blocks, isEmpty);
    expect(controller.gps, isEmpty);
    expect(controller.pops, isEmpty);
  });
}
