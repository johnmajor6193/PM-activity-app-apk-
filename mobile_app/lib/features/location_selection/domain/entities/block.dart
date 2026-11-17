class Block {
  const Block({required this.id, required this.name, required this.districtId});

  final int id;
  final String name;
  final int districtId;

  @override
  bool operator ==(Object other) => other is Block && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
