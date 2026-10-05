import 'dart:convert';

class Person {
  final int? id;
  final String name;
  final String imagePath;
  final DateTime createdAt;
  final List<double> embedding; // face embedding vector
  final DateTime? lastSeenAt;
  final double? lastSeenLatitude;
  final double? lastSeenLongitude;
  final String consentStatus;
  final DateTime? consentTimestamp;
  final String syncStatus;
  final int retryCount;
  final DateTime? lastSyncAttempt;
  final String? lastSyncError;
  final String? storagePath;
  final String? imageUrl;
  final DateTime? lastSyncedAt;
  final List<String> referenceImages;
  final String? locationName;

  Person({
    this.id,
    required this.name,
    required this.imagePath,
    required this.createdAt,
    this.embedding = const [],
    this.lastSeenAt,
    this.lastSeenLatitude,
    this.lastSeenLongitude,
    this.consentStatus = 'unknown',
    this.consentTimestamp,
    this.syncStatus = 'pending',
    this.retryCount = 0,
    this.lastSyncAttempt,
    this.lastSyncError,
    this.storagePath,
    this.imageUrl,
    this.lastSyncedAt,
    this.referenceImages = const [],
    this.locationName,
  });

  Person copyWith({
    int? id,
    String? name,
    String? imagePath,
    DateTime? createdAt,
    List<double>? embedding,
    DateTime? lastSeenAt,
    double? lastSeenLatitude,
    double? lastSeenLongitude,
    String? consentStatus,
    DateTime? consentTimestamp,
    String? syncStatus,
    int? retryCount,
    DateTime? lastSyncAttempt,
    String? lastSyncError,
    String? storagePath,
    String? imageUrl,
    DateTime? lastSyncedAt,
    List<String>? referenceImages,
    String? locationName,
  }) {
    return Person(
      id: id ?? this.id,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      embedding: embedding ?? this.embedding,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastSeenLatitude: lastSeenLatitude ?? this.lastSeenLatitude,
      lastSeenLongitude: lastSeenLongitude ?? this.lastSeenLongitude,
      consentStatus: consentStatus ?? this.consentStatus,
      consentTimestamp: consentTimestamp ?? this.consentTimestamp,
      syncStatus: syncStatus ?? this.syncStatus,
      retryCount: retryCount ?? this.retryCount,
      lastSyncAttempt: lastSyncAttempt ?? this.lastSyncAttempt,
      lastSyncError: lastSyncError ?? this.lastSyncError,
      storagePath: storagePath ?? this.storagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      referenceImages: referenceImages ?? this.referenceImages,
      locationName: locationName ?? this.locationName,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'image_path': imagePath,
      'created_at': createdAt.toIso8601String(),
      'embedding': embedding.isEmpty ? null : jsonEncode(embedding),
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'last_seen_latitude': lastSeenLatitude,
      'last_seen_longitude': lastSeenLongitude,
      'consent_status': consentStatus,
      'consent_timestamp': consentTimestamp?.toIso8601String(),
      'sync_status': syncStatus,
      'retry_count': retryCount,
      'last_sync_attempt': lastSyncAttempt?.toIso8601String(),
      'last_sync_error': lastSyncError,
      'storage_path': storagePath,
      'image_url': imageUrl,
      'last_synced_at': lastSyncedAt?.toIso8601String(),
      'reference_images': referenceImages.isEmpty ? null : jsonEncode(referenceImages),
      'location_name': locationName,
    };
  }

  factory Person.fromMap(Map<String, dynamic> map) {
    List<double> emb = [];
    if (map['embedding'] != null) {
      final decoded = jsonDecode(map['embedding'] as String) as List;
      emb = decoded.map((e) => (e as num).toDouble()).toList();
    }
    List<String> refImgs = [];
    if (map['reference_images'] != null) {
      try {
        final decoded = jsonDecode(map['reference_images'] as String);
        if (decoded is List) {
          refImgs = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return Person(
      id: map['id'],
      name: map['name'],
      imagePath: map['image_path'],
      createdAt: DateTime.parse(map['created_at']),
      embedding: emb,
      lastSeenAt: map['last_seen_at'] != null ? DateTime.tryParse(map['last_seen_at'] as String) : null,
      lastSeenLatitude: map['last_seen_latitude'] is num ? (map['last_seen_latitude'] as num).toDouble() : null,
      lastSeenLongitude: map['last_seen_longitude'] is num ? (map['last_seen_longitude'] as num).toDouble() : null,
      consentStatus: map['consent_status'] as String? ?? 'unknown',
      consentTimestamp: map['consent_timestamp'] != null ? DateTime.tryParse(map['consent_timestamp'] as String) : null,
      syncStatus: map['sync_status'] as String? ?? 'pending',
      retryCount: map['retry_count'] is num ? (map['retry_count'] as num).toInt() : 0,
      lastSyncAttempt: map['last_sync_attempt'] != null ? DateTime.tryParse(map['last_sync_attempt'] as String) : null,
      lastSyncError: map['last_sync_error'] as String?,
      storagePath: map['storage_path'] as String?,
      imageUrl: map['image_url'] as String?,
      lastSyncedAt: map['last_synced_at'] != null ? DateTime.tryParse(map['last_synced_at'] as String) : null,
      referenceImages: refImgs,
      locationName: map['location_name'] as String?,
    );
  }
}
