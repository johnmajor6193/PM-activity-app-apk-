class District {
  const District({required this.id, required this.name});

  final int id;
  final String name;

  @override
  bool operator ==(Object other) => other is District && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
