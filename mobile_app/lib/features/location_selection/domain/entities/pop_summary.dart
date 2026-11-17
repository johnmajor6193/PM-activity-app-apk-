/// A POP as listed under a GP.
///
/// No latitude/longitude/geofence fields: the official POP coordinate
/// master data has not been supplied yet, and this app does not use
/// fake coordinates. GPS capture happens per-photo in the PM visit
/// module (a later step); POP geofence validation is deferred until
/// real POP coordinates are available.
class PopSummary {
  const PopSummary({
    required this.id,
    required this.popCode,
    required this.name,
    required this.isActive,
    required this.gpId,
  });

  final int id;
  final String popCode;
  final String? name;
  final bool isActive;
  final int gpId;

  @override
  bool operator ==(Object other) => other is PopSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
