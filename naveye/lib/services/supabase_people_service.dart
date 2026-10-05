import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/person_model.dart';
import 'database_service.dart';
import 'sync_queue_service.dart';

class SupabasePeopleService {
  static final SupabasePeopleService instance = SupabasePeopleService._();

  SupabasePeopleService._();

  Timer? _retryTimer;
  bool _syncRunning = false;
  bool _started = false;

  void startBackgroundSync() {
    if (_started) return;
    _started = true;
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await syncPendingPeople();
    });
    debugPrint('Supabase sync queue started');
  }

  void stopBackgroundSync() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _started = false;
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final connectivity = Connectivity();
      final state = await connectivity.checkConnectivity();
      if (state.contains(ConnectivityResult.none)) return false;
      final result = await InternetAddress.lookup('supabase.co');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncPersonToSupabase({
    required Person person,
    required String? imagePath,
    required List<double>? embedding,
  }) async {
    if (person.id == null) return;
    try {
      final now = DateTime.now();
      final client = Supabase.instance.client;
      if (imagePath == null || imagePath.isEmpty) {
        debugPrint('Supabase sync skipped: no image path for ${person.name}');
        await DatabaseService.instance.updatePersonMeta(
          personId: person.id!,
          syncStatus: 'pending',
          lastSyncAttempt: now,
          lastSyncError: 'missing image path',
        );
        return;
      }

      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('Supabase sync skipped: image missing for ${person.name}');
        await DatabaseService.instance.updatePersonMeta(
          personId: person.id!,
          syncStatus: 'pending',
          lastSyncAttempt: now,
          lastSyncError: 'image missing locally',
        );
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = person.name.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
      final storagePath = person.storagePath ?? 'people/$safeName-$timestamp-${p.basename(imagePath)}';

      if (!await _hasInternetConnection()) {
        debugPrint('Supabase sync deferred offline for ${person.name}');
        await DatabaseService.instance.updatePersonMeta(
          personId: person.id!,
          syncStatus: 'pending',
          storagePath: storagePath,
          imageUrl: person.imageUrl,
          retryCount: (person.retryCount + 1),
          lastSyncAttempt: now,
          lastSyncError: 'offline',
        );
        return;
      }

      final bytes = await file.readAsBytes();
      await client.storage.from('person_faces').uploadBinary(
        storagePath,
        bytes,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/jpeg',
        ),
      );

      final signed = await client.storage.from('person_faces').createSignedUrl(
        storagePath,
        60 * 60 * 24,
      );
      final imageUrl = signed;

      final row = {
        'name': person.name,
        'storage_path': storagePath,
        'image_url': imageUrl,
        'local_person_id': person.id,
        'created_at': person.createdAt.toUtc().toIso8601String(),
        'embedding_json': embedding == null || embedding.isEmpty ? null : jsonEncode(embedding),
        'sync_status': 'synced',
        'source': 'naveye_local',
        'consent_status': person.consentStatus,
        'consent_timestamp': person.consentTimestamp?.toUtc().toIso8601String(),
        'last_seen_at': person.lastSeenAt?.toUtc().toIso8601String(),
        'last_seen_latitude': person.lastSeenLatitude,
        'last_seen_longitude': person.lastSeenLongitude,
      };

      await client.from('people').upsert(
        row,
        onConflict: 'local_person_id',
      );

      await DatabaseService.instance.updatePersonMeta(
        personId: person.id!,
        syncStatus: 'synced',
        retryCount: 0,
        storagePath: storagePath,
        imageUrl: imageUrl,
        lastSyncedAt: now,
        lastSyncAttempt: now,
        lastSyncError: null,
      );

      debugPrint('Supabase sync complete for ${person.name}');
    } catch (e, st) {
      debugPrint('Supabase sync failed for ${person.name}: $e');
      debugPrint('Supabase sync stack: $st');
      if (person.id != null) {
        final nextRetry = person.retryCount + 1;
        await DatabaseService.instance.updatePersonMeta(
          personId: person.id!,
          syncStatus: 'failed',
          retryCount: nextRetry,
          lastSyncAttempt: DateTime.now(),
          lastSyncError: e.toString(),
        );
      }
    }
  }

  Future<void> syncPendingPeople() async {
    if (_syncRunning) return;
    _syncRunning = true;
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.query(
        'persons',
        where: 'sync_status IN (?, ?)',
        whereArgs: ['pending', 'failed'],
      );
      for (final row in rows) {
        final person = Person.fromMap(row);
        if (person.imagePath.isEmpty || person.syncStatus == 'synced') continue;
        final lastAttempt = person.lastSyncAttempt;
        final retryDelayMs = SyncQueueService.retryDelaySeconds(person.retryCount) * 1000;
        if (lastAttempt != null && DateTime.now().difference(lastAttempt).inMilliseconds < retryDelayMs) {
          continue;
        }
        await syncPersonToSupabase(
          person: person,
          imagePath: person.imagePath,
          embedding: person.embedding,
        );
      }
      await syncPendingEncounters();
      await syncPendingEvents();
    } catch (e) {
      debugPrint('Supabase pending sync error: $e');
    } finally {
      _syncRunning = false;
    }
  }

  Future<void> syncPendingEncounters() async {
    try {
      if (!await _hasInternetConnection()) return;
      final pending = await DatabaseService.instance.getAllPendingEncounters();
      if (pending.isEmpty) return;
      final client = Supabase.instance.client;

      for (final row in pending) {
        final id = row['id'] as int;
        final personId = row['person_id'] as int;
        final retryCount = (row['retry_count'] as int?) ?? 0;
        final lastAttempt = row['last_sync_attempt'] != null
            ? DateTime.tryParse(row['last_sync_attempt'] as String)
            : null;
        final retryDelayMs = SyncQueueService.retryDelaySeconds(retryCount) * 1000;
        if (lastAttempt != null && DateTime.now().difference(lastAttempt).inMilliseconds < retryDelayMs) {
          continue;
        }

        try {
          await client.from('person_encounters').upsert({
            'local_encounter_id': id,
            'local_person_id': personId,
            'timestamp': row['timestamp'],
            'latitude': row['latitude'],
            'longitude': row['longitude'],
            'confidence': row['confidence'],
            'source': row['source'] ?? 'naveye',
          }, onConflict: 'local_encounter_id');

          await DatabaseService.instance.updateEncounterSyncStatus(
            encounterId: id,
            syncStatus: 'synced',
            retryCount: 0,
            lastSyncedAt: DateTime.now(),
          );
        } catch (e) {
          debugPrint('Sync encounter $id failed: $e');
          await DatabaseService.instance.updateEncounterSyncStatus(
            encounterId: id,
            syncStatus: 'failed',
            retryCount: retryCount + 1,
            lastSyncAttempt: DateTime.now(),
            lastSyncError: e.toString(),
          );
        }
      }
    } catch (e) {
      debugPrint('Sync pending encounters error: $e');
    }
  }

  Future<void> syncPendingEvents() async {
    try {
      if (!await _hasInternetConnection()) return;
      final pending = await DatabaseService.instance.getAllPendingEvents();
      if (pending.isEmpty) return;
      final client = Supabase.instance.client;

      for (final row in pending) {
        final id = row['id'] as int;
        final retryCount = (row['retry_count'] as int?) ?? 0;
        final lastAttempt = row['last_sync_attempt'] != null
            ? DateTime.tryParse(row['last_sync_attempt'] as String)
            : null;
        final retryDelayMs = SyncQueueService.retryDelaySeconds(retryCount) * 1000;
        if (lastAttempt != null && DateTime.now().difference(lastAttempt).inMilliseconds < retryDelayMs) {
          continue;
        }

        try {
          await client.from('event_history').upsert({
            'local_event_id': id,
            'event_type': row['event_type'],
            'description': row['description'],
            'zone': row['zone'],
            'distance': row['distance'],
            'latitude': row['latitude'],
            'longitude': row['longitude'],
            'timestamp': row['timestamp'],
          }, onConflict: 'local_event_id');

          await DatabaseService.instance.updateEventSyncStatus(
            eventId: id,
            syncStatus: 'synced',
            retryCount: 0,
            lastSyncedAt: DateTime.now(),
          );
        } catch (e) {
          debugPrint('Sync event $id failed: $e');
          await DatabaseService.instance.updateEventSyncStatus(
            eventId: id,
            syncStatus: 'failed',
            retryCount: retryCount + 1,
            lastSyncAttempt: DateTime.now(),
            lastSyncError: e.toString(),
          );
        }
      }
    } catch (e) {
      debugPrint('Sync pending events error: $e');
    }
  }
}
