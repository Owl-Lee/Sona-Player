import 'dart:convert';

/// Persistent, idempotent record of Storage objects whose authoritative cloud
/// row has been (or may have been) hard-deleted.
class CloudStorageDeleteOutbox {
  const CloudStorageDeleteOutbox(this.objects);

  const CloudStorageDeleteOutbox.empty() : objects = const <String>{};

  final Set<String> objects;

  bool get isEmpty => objects.isEmpty;

  CloudStorageDeleteOutbox addAll(Iterable<String?> values) {
    final next = <String>{...objects};
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) next.add(normalized);
    }
    return CloudStorageDeleteOutbox(Set<String>.unmodifiable(next));
  }

  CloudStorageDeleteOutbox removeAll(Iterable<String> values) {
    final next = <String>{...objects}..removeAll(values);
    return CloudStorageDeleteOutbox(Set<String>.unmodifiable(next));
  }

  String encode() {
    final sorted = objects.toList(growable: false)..sort();
    return jsonEncode(<String, Object?>{'version': 1, 'objects': sorted});
  }

  factory CloudStorageDeleteOutbox.decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const CloudStorageDeleteOutbox.empty();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != 1) {
        return const CloudStorageDeleteOutbox.empty();
      }
      final objects = (decoded['objects'] as List? ?? const <Object>[])
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet();
      return CloudStorageDeleteOutbox(Set<String>.unmodifiable(objects));
    } on Object {
      return const CloudStorageDeleteOutbox.empty();
    }
  }
}
