class OpenToolDto {
  OpenToolDto({
    required this.name,
    required this.description,
    this.version = '0.1.0',
  });

  final String name;
  final String description;
  final String version;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'version': version,
  };
}
