import 'package:flutter/foundation.dart';

import '../data/location_repository_impl.dart';
import '../domain/entities/block.dart';
import '../domain/entities/district.dart';
import '../domain/entities/gp.dart';
import '../domain/entities/pop_detail.dart';
import '../domain/entities/pop_summary.dart';
import '../domain/location_failure.dart';
import '../domain/repositories/location_repository.dart';

enum LoadStatus { idle, loading, loaded, error }

/// Drives the cascading District → Block → GP → POP selection and loads
/// the chosen POP's basic details. Depends only on [LocationRepository].
///
/// Call [loadDistricts] once (e.g. from the screen's initState) to
/// populate the first dropdown.
class PopSelectionController extends ChangeNotifier {
  PopSelectionController({LocationRepository? repository})
      : _repository = repository ?? LocationRepositoryImpl();

  final LocationRepository _repository;

  LoadStatus districtsStatus = LoadStatus.idle;
  LoadStatus blocksStatus = LoadStatus.idle;
  LoadStatus gpsStatus = LoadStatus.idle;
  LoadStatus popsStatus = LoadStatus.idle;
  LoadStatus popDetailStatus = LoadStatus.idle;
  String? errorMessage;

  List<District> districts = [];
  List<Block> blocks = [];
  List<Gp> gps = [];
  List<PopSummary> pops = [];

  District? selectedDistrict;
  Block? selectedBlock;
  Gp? selectedGp;
  PopSummary? selectedPopSummary;
  PopDetail? selectedPopDetail;

  Future<void> loadDistricts() async {
    districtsStatus = LoadStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      districts = await _repository.getDistricts();
      districtsStatus = LoadStatus.loaded;
    } on LocationFailure catch (failure) {
      errorMessage = failure.message;
      districtsStatus = LoadStatus.error;
    }
    notifyListeners();
  }

  Future<void> selectDistrict(District? district) async {
    selectedDistrict = district;
    _resetFrom(_Level.block);
    notifyListeners();

    if (district == null) {
      return;
    }

    blocksStatus = LoadStatus.loading;
    notifyListeners();
    try {
      blocks = await _repository.getBlocks(district.id);
      blocksStatus = LoadStatus.loaded;
    } on LocationFailure catch (failure) {
      errorMessage = failure.message;
      blocksStatus = LoadStatus.error;
    }
    notifyListeners();
  }

  Future<void> selectBlock(Block? block) async {
    selectedBlock = block;
    _resetFrom(_Level.gp);
    notifyListeners();

    if (block == null) {
      return;
    }

    gpsStatus = LoadStatus.loading;
    notifyListeners();
    try {
      gps = await _repository.getGps(block.id);
      gpsStatus = LoadStatus.loaded;
    } on LocationFailure catch (failure) {
      errorMessage = failure.message;
      gpsStatus = LoadStatus.error;
    }
    notifyListeners();
  }

  Future<void> selectGp(Gp? gp) async {
    selectedGp = gp;
    _resetFrom(_Level.pop);
    notifyListeners();

    if (gp == null) {
      return;
    }

    popsStatus = LoadStatus.loading;
    notifyListeners();
    try {
      pops = await _repository.getPops(gp.id);
      popsStatus = LoadStatus.loaded;
    } on LocationFailure catch (failure) {
      errorMessage = failure.message;
      popsStatus = LoadStatus.error;
    }
    notifyListeners();
  }

  Future<void> selectPop(PopSummary? pop) async {
    selectedPopSummary = pop;
    selectedPopDetail = null;
    popDetailStatus = LoadStatus.idle;
    errorMessage = null;
    notifyListeners();

    if (pop == null) {
      return;
    }

    popDetailStatus = LoadStatus.loading;
    notifyListeners();
    try {
      selectedPopDetail = await _repository.getPopDetail(pop.id);
      popDetailStatus = LoadStatus.loaded;
    } on LocationFailure catch (failure) {
      errorMessage = failure.message;
      popDetailStatus = LoadStatus.error;
    }
    notifyListeners();
  }

  /// Clears selections/lists at and below [level] whenever a higher-level
  /// dropdown changes, so stale lower-level choices are never shown.
  void _resetFrom(_Level level) {
    errorMessage = null;
    if (level.index <= _Level.block.index) {
      selectedBlock = null;
      blocks = [];
      blocksStatus = LoadStatus.idle;
    }
    if (level.index <= _Level.gp.index) {
      selectedGp = null;
      gps = [];
      gpsStatus = LoadStatus.idle;
    }
    if (level.index <= _Level.pop.index) {
      selectedPopSummary = null;
      selectedPopDetail = null;
      pops = [];
      popsStatus = LoadStatus.idle;
      popDetailStatus = LoadStatus.idle;
    }
  }
}

enum _Level { block, gp, pop }
