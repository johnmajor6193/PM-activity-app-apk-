/// A single POP's basic details, with its District/Block/GP names
/// resolved for display.
///
/// No latitude/longitude/geofence fields — see pop_summary.dart for why.
class PopDetail {
  const PopDetail({
    required this.id,
    required this.popCode,
    required this.name,
    required this.isActive,
    required this.gpId,
    required this.gpName,
    required this.blockName,
    required this.districtName,
  });

  final int id;
  final String popCode;
  final String? name;
  final bool isActive;
  final int gpId;
  final String gpName;
  final String blockName;
  final String districtName;
}
