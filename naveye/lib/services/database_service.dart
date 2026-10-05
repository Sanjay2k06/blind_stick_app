import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/person_model.dart';
import 'sync_queue_service.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('naveye.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE persons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        image_path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        embedding TEXT,
        last_seen_at TEXT,
        last_seen_latitude REAL,
        last_seen_longitude REAL,
        consent_status TEXT DEFAULT 'unknown',
        consent_timestamp TEXT,
        sync_status TEXT DEFAULT 'pending',
        retry_count INTEGER DEFAULT 0,
        last_sync_attempt TEXT,
        last_sync_error TEXT,
        storage_path TEXT,
        image_url TEXT,
        last_synced_at TEXT,
        reference_images TEXT,
        location_name TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE person_encounters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        confidence REAL,
        source TEXT DEFAULT 'naveye',
        created_at TEXT NOT NULL,
        sync_status TEXT DEFAULT 'pending',
        retry_count INTEGER DEFAULT 0,
        last_sync_attempt TEXT,
        last_sync_error TEXT,
        last_synced_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE event_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        description TEXT,
        zone TEXT,
        distance REAL,
        latitude REAL,
        longitude REAL,
        timestamp TEXT NOT NULL,
        sync_status TEXT DEFAULT 'pending',
        retry_count INTEGER DEFAULT 0,
        last_sync_attempt TEXT,
        last_sync_error TEXT,
        last_synced_at TEXT
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE persons ADD COLUMN embedding TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE persons ADD COLUMN last_seen_at TEXT');
      await db.execute('ALTER TABLE persons ADD COLUMN last_seen_latitude REAL');
      await db.execute('ALTER TABLE persons ADD COLUMN last_seen_longitude REAL');
      await db.execute('ALTER TABLE persons ADD COLUMN consent_status TEXT DEFAULT "unknown"');
      await db.execute('ALTER TABLE persons ADD COLUMN consent_timestamp TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS person_encounters (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          person_id INTEGER NOT NULL,
          timestamp TEXT NOT NULL,
          latitude REAL,
          longitude REAL,
          confidence REAL,
          source TEXT DEFAULT 'naveye',
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE persons ADD COLUMN sync_status TEXT DEFAULT "pending"');
      await db.execute('ALTER TABLE persons ADD COLUMN storage_path TEXT');
      await db.execute('ALTER TABLE persons ADD COLUMN image_url TEXT');
      await db.execute('ALTER TABLE persons ADD COLUMN last_synced_at TEXT');
      await db.execute('ALTER TABLE person_encounters ADD COLUMN sync_status TEXT DEFAULT "pending"');
      await db.execute('ALTER TABLE person_encounters ADD COLUMN last_synced_at TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE persons ADD COLUMN retry_count INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE persons ADD COLUMN last_sync_attempt TEXT');
      await db.execute('ALTER TABLE persons ADD COLUMN last_sync_error TEXT');
      await db.execute('ALTER TABLE person_encounters ADD COLUMN retry_count INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE person_encounters ADD COLUMN last_sync_attempt TEXT');
      await db.execute('ALTER TABLE person_encounters ADD COLUMN last_sync_error TEXT');
      await db.execute('UPDATE persons SET sync_status = ? WHERE sync_status IS NULL OR sync_status = ?', ['pending', '']);
      await db.execute('UPDATE person_encounters SET sync_status = ? WHERE sync_status IS NULL OR sync_status = ?', ['pending', '']);
      await db.execute('UPDATE persons SET sync_status = ? WHERE sync_status NOT IN (?, ?, ?, ?)', ['pending', 'pending', 'syncing', 'synced', 'failed']);
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS event_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          event_type TEXT NOT NULL,
          description TEXT,
          zone TEXT,
          distance REAL,
          latitude REAL,
          longitude REAL,
          timestamp TEXT NOT NULL,
          sync_status TEXT DEFAULT 'pending',
          retry_count INTEGER DEFAULT 0,
          last_sync_attempt TEXT,
          last_sync_error TEXT,
          last_synced_at TEXT
        )
      ''');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE persons ADD COLUMN reference_images TEXT');
      await db.execute('ALTER TABLE persons ADD COLUMN location_name TEXT');
    }
  }

  Future<Person> insertPerson(Person person) async {
    final db = await database;
    final row = person.toMap();
    row['sync_status'] = row['sync_status'] ?? 'pending';
    final id = await db.insert('persons', row);
    return person.copyWith(id: id);
  }

  Future<void> updatePerson(Person person) async {
    if (person.id == null) return;
    final db = await database;
    await db.update('persons', person.toMap(), where: 'id = ?', whereArgs: [person.id]);
  }

  Future<Person?> getPersonByName(String name) async {
    final db = await database;
    final rows = await db.query(
      'persons',
      where: 'LOWER(name) = ?',
      whereArgs: [name.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Person.fromMap(rows.first);
  }

  Future<void> updateEmbedding(int id, List<double> embedding) async {
    final db = await database;
    // Use the same jsonEncode path as Person.toMap() to keep encoding consistent.
    await db.update(
      'persons',
      {'embedding': jsonEncode(embedding)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Person>> getAllPersons() async {
    final db = await database;
    final result = await db.query('persons', orderBy: 'created_at DESC');
    return result.map((map) => Person.fromMap(map)).toList();
  }

  Future<void> deletePerson(int id) async {
    final db = await database;
    // Fetch image path and reference images first to delete files cleanly
    final rows = await db.query('persons', columns: ['image_path', 'reference_images'],
        where: 'id = ?', whereArgs: [id]);
    await db.delete('persons', where: 'id = ?', whereArgs: [id]);
    await db.delete('person_encounters', where: 'person_id = ?', whereArgs: [id]);
    
    // Delete photo files securely — prevents storage leak on delete
    if (rows.isNotEmpty) {
      final path = rows.first['image_path'] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      final refStr = rows.first['reference_images'] as String?;
      if (refStr != null && refStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(refStr);
          if (decoded is List) {
            for (final p in decoded) {
              if (p is String && p.isNotEmpty) {
                try {
                  final f = File(p);
                  if (await f.exists()) await f.delete();
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }
    }
  }

  Future<void> updatePersonMeta({
    required int personId,
    DateTime? lastSeenAt,
    double? latitude,
    double? longitude,
    String consentStatus = 'unknown',
    DateTime? consentTimestamp,
    String syncStatus = '',
    int? retryCount,
    DateTime? lastSyncAttempt,
    String? lastSyncError,
    String? storagePath,
    String? imageUrl,
    DateTime? lastSyncedAt,
  }) async {
    final db = await database;
    await db.update(
      'persons',
      {
        if (lastSeenAt != null) 'last_seen_at': lastSeenAt.toIso8601String(),
        if (latitude != null) 'last_seen_latitude': latitude,
        if (longitude != null) 'last_seen_longitude': longitude,
        if (consentStatus.isNotEmpty) 'consent_status': consentStatus,
        if (consentTimestamp != null) 'consent_timestamp': consentTimestamp.toIso8601String(),
        if (syncStatus.isNotEmpty) 'sync_status': SyncQueueService.normaliseStatus(syncStatus),
        if (retryCount != null) 'retry_count': retryCount,
        if (lastSyncAttempt != null) 'last_sync_attempt': lastSyncAttempt.toIso8601String(),
        if (lastSyncError != null) 'last_sync_error': lastSyncError,
        if (storagePath != null) 'storage_path': storagePath,
        if (imageUrl != null) 'image_url': imageUrl,
        if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [personId],
    );
  }

  Future<void> logEncounter({
    required int personId,
    required DateTime timestamp,
    double? latitude,
    double? longitude,
    double? confidence,
    String source = 'naveye',
    String syncStatus = 'pending',
  }) async {
    final db = await database;
    final encounterTime = timestamp.toIso8601String();
    await db.insert('person_encounters', {
      'person_id': personId,
      'timestamp': encounterTime,
      'latitude': latitude,
      'longitude': longitude,
      'confidence': confidence,
      'source': source,
      'created_at': DateTime.now().toIso8601String(),
      'sync_status': SyncQueueService.normaliseStatus(syncStatus),
    });

    await db.update(
      'persons',
      {
        'last_seen_at': encounterTime,
        if (latitude != null) 'last_seen_latitude': latitude,
        if (longitude != null) 'last_seen_longitude': longitude,
      },
      where: 'id = ?',
      whereArgs: [personId],
    );
  }

  Future<List<Map<String, dynamic>>> getRecentEncounters(int personId, {int limit = 10}) async {
    final db = await database;
    return await db.query(
      'person_encounters',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<void> renamePerson(int personId, String newName) async {
    final db = await database;
    await db.update('persons', {'name': newName}, where: 'id = ?', whereArgs: [personId]);
  }

  // ── Event History ─────────────────────────────────────────────────────────
  Future<int> logEvent({
    required String eventType,
    String? description,
    String? zone,
    double? distance,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    String syncStatus = 'pending',
  }) async {
    final db = await database;
    final eventTime = (timestamp ?? DateTime.now()).toIso8601String();
    return await db.insert('event_history', {
      'event_type': eventType,
      'description': description,
      'zone': zone,
      'distance': distance,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': eventTime,
      'sync_status': SyncQueueService.normaliseStatus(syncStatus),
      'retry_count': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getRecentEvents({int limit = 50}) async {
    final db = await database;
    return await db.query(
      'event_history',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getAllRecentEncounters({int limit = 50}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        e.id,
        e.person_id,
        e.timestamp,
        e.latitude,
        e.longitude,
        e.confidence,
        e.source,
        e.sync_status,
        p.name AS person_name,
        p.image_path AS person_image_path
      FROM person_encounters e
      LEFT JOIN persons p ON e.person_id = p.id
      ORDER BY e.timestamp DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<Map<String, int>> getEventHistoryStats() async {
    final db = await database;
    final stops = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM event_history WHERE event_type = 'danger_stop'",
    )) ?? 0;

    final reroutes = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM event_history WHERE event_type = 'obstacle_avoidance'",
    )) ?? 0;

    final encounters = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM person_encounters',
    )) ?? 0;

    final pendingSync = (Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM event_history WHERE sync_status = 'pending'",
    )) ?? 0) + (Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM person_encounters WHERE sync_status = 'pending'",
    )) ?? 0);

    return {
      'stops': stops,
      'reroutes': reroutes,
      'encounters': encounters,
      'pendingSync': pendingSync,
    };
  }

  Future<List<Map<String, dynamic>>> getAllPendingEncounters() async {
    final db = await database;
    return await db.query(
      'person_encounters',
      where: 'sync_status IN (?, ?)',
      whereArgs: ['pending', 'failed'],
    );
  }

  Future<void> updateEncounterSyncStatus({
    required int encounterId,
    required String syncStatus,
    int? retryCount,
    DateTime? lastSyncAttempt,
    String? lastSyncError,
    DateTime? lastSyncedAt,
  }) async {
    final db = await database;
    await db.update(
      'person_encounters',
      {
        'sync_status': SyncQueueService.normaliseStatus(syncStatus),
        if (retryCount != null) 'retry_count': retryCount,
        if (lastSyncAttempt != null) 'last_sync_attempt': lastSyncAttempt.toIso8601String(),
        if (lastSyncError != null) 'last_sync_error': lastSyncError,
        if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [encounterId],
    );
  }

  Future<List<Map<String, dynamic>>> getAllPendingEvents() async {
    final db = await database;
    return await db.query(
      'event_history',
      where: 'sync_status IN (?, ?)',
      whereArgs: ['pending', 'failed'],
    );
  }

  Future<void> updateEventSyncStatus({
    required int eventId,
    required String syncStatus,
    int? retryCount,
    DateTime? lastSyncAttempt,
    String? lastSyncError,
    DateTime? lastSyncedAt,
  }) async {
    final db = await database;
    await db.update(
      'event_history',
      {
        'sync_status': SyncQueueService.normaliseStatus(syncStatus),
        if (retryCount != null) 'retry_count': retryCount,
        if (lastSyncAttempt != null) 'last_sync_attempt': lastSyncAttempt.toIso8601String(),
        if (lastSyncError != null) 'last_sync_error': lastSyncError,
        if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
