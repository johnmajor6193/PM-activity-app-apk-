/// The 5 mandatory PM visit photo categories, in capture/checklist order.
/// This list is fixed — adding more categories is out of scope for this
/// module.
enum PhotoCategory { popRack, upsBattery, busbar, earthPitChamber, earthPitOpenWithRod }

const List<PhotoCategory> mandatoryPhotoCategories = PhotoCategory.values;

extension PhotoCategoryX on PhotoCategory {
  String get label {
    switch (this) {
      case PhotoCategory.popRack:
        return 'POP Rack';
      case PhotoCategory.upsBattery:
        return 'UPS & Battery';
      case PhotoCategory.busbar:
        return 'Busbar';
      case PhotoCategory.earthPitChamber:
        return 'Earth Pit Chamber';
      case PhotoCategory.earthPitOpenWithRod:
        return 'Earth Pit Open with Rod';
    }
  }

  /// Stable key used in local storage (and later, the backend) —
  /// independent of [label], which is free to change.
  String get storageKey {
    switch (this) {
      case PhotoCategory.popRack:
        return 'pop_rack';
      case PhotoCategory.upsBattery:
        return 'ups_battery';
      case PhotoCategory.busbar:
        return 'busbar';
      case PhotoCategory.earthPitChamber:
        return 'earth_pit_chamber';
      case PhotoCategory.earthPitOpenWithRod:
        return 'earth_pit_open_with_rod';
    }
  }
}

PhotoCategory photoCategoryFromStorageKey(String key) {
  return PhotoCategory.values.firstWhere((category) => category.storageKey == key);
}
