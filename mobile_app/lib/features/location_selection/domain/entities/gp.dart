/// A Grama Panchayat (GP) — third level of District → Block → GP → POP.
class Gp {
  const Gp({required this.id, required this.name, required this.blockId});

  final int id;
  final String name;
  final int blockId;

  @override
  bool operator ==(Object other) => other is Gp && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
