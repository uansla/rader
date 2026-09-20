class LibraryFolder {
  final int? id;
  final String path;
  final bool enabled;

  LibraryFolder({this.id, required this.path, this.enabled = true});

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'path': path,
      'enabled': enabled ? 1 : 0,
    };
  }

  factory LibraryFolder.fromMap(Map<String, Object?> map) {
    return LibraryFolder(
      id: map['id'] as int?,
      path: map['path'] as String,
      enabled: (map['enabled'] as int?) == 1,
    );
  }
}
