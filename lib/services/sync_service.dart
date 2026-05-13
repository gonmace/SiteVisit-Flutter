import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import 'api_client.dart';
import 'local_db_service.dart';

class SyncService {
  final LocalDbService _db;
  final ApiClient      _client;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncing = false;
  DateTime? _lastSyncAttempt;

  SyncService({required LocalDbService db, required ApiClient client})
      : _db = db,
        _client = client;

  void startListening() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _syncAll();
      }
    });
    // Vaciar cola si ya hay red al arrancar, sin esperar un cambio de conectividad.
    Connectivity().checkConnectivity().then((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _syncAll();
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> _syncAll() async {
    if (_syncing) return;
    final now = DateTime.now();
    if (_lastSyncAttempt != null &&
        now.difference(_lastSyncAttempt!).inSeconds < 10) {
      return;
    }
    _lastSyncAttempt = now;
    _syncing = true;
    try {
      await _syncPendingRequests();
      await _syncPendingTracking();
      await _syncPendingPhotos();
    } finally {
      _syncing = false;
    }
  }

  /// Cola genérica: procesa `pending_requests` en orden FIFO.
  /// Resuelve el placeholder `{visit_id}` contra `active_visit.remote_id`.
  Future<void> _syncPendingRequests() async {
    final requests = await _db.getPendingRequests();
    final database = await _db.db;

    for (final req in requests) {
      try {
        var path = req['path_template'] as String;
        final visitLocalId = req['visit_local_id'] as int?;

        if (visitLocalId != null) {
          final avRows = await database.query(
            'active_visit',
            where: 'id = ?',
            whereArgs: [visitLocalId],
            limit: 1,
          );
          if (avRows.isEmpty) continue;
          final remoteId = avRows.first['remote_id'] as int?;
          if (remoteId == null) continue;   // visita aún no sincronizada
          path = path.replaceFirst('{visit_id}', remoteId.toString());
        }

        final body   = jsonDecode(req['body_json'] as String) as Map<String, dynamic>;
        final method = req['method'] as String;

        final resp = method == 'PATCH'
            ? await _client.patch(path, body)
            : await _client.post(path, body);

        if (resp.statusCode == 200 || resp.statusCode == 201) {
          await _db.markRequestUploaded(req['id'] as int);
        }
      } catch (e) {
        debugPrint('SyncService.pendingRequests error (id ${req['id']}): $e');
      }
    }
  }

  Future<void> _syncPendingTracking() async {
    final database = await _db.db;

    final visits = await database.query(
      'active_visit',
      where: 'remote_id IS NOT NULL',
    );

    for (final visit in visits) {
      final remoteId = visit['remote_id'] as int;
      final localId  = visit['id'] as int;

      final points = await database.query(
        'pending_tracking',
        where: 'visit_local_id = ? AND uploaded = 0',
        whereArgs: [localId],
      );

      for (final pt in points) {
        try {
          final resp = await _client.post(
            '${Constants.visitsPath}$remoteId/tracking/',
            {
              'event':     pt['event'],
              'latitude':  pt['latitude'],
              'longitude': pt['longitude'],
              'timestamp': pt['timestamp'],
            },
          );
          if (resp.statusCode == 201) {
            await database.update(
              'pending_tracking',
              {'uploaded': 1},
              where: 'id = ?',
              whereArgs: [pt['id']],
            );
          }
        } catch (e) {
          debugPrint('SyncService.pendingTracking error (id ${pt['id']}): $e');
        }
      }
    }
  }

  Future<void> _syncPendingPhotos() async {
    final database = await _db.db;

    final visits = await database.query(
      'active_visit',
      where: 'remote_id IS NOT NULL',
    );

    for (final visit in visits) {
      final remoteId = visit['remote_id'] as int;
      final localId  = visit['id'] as int;

      final photos = await database.query(
        'pending_photos',
        where: 'visit_local_id = ? AND uploaded = 0',
        whereArgs: [localId],
      );

      for (final photo in photos) {
        final localPath = photo['local_path'] as String;

        if (!File(localPath).existsSync()) {
          debugPrint('SyncService.pendingPhotos: archivo no encontrado (id ${photo['id']}), descartando');
          await database.update(
            'pending_photos',
            {'uploaded': 1},
            where: 'id = ?',
            whereArgs: [photo['id']],
          );
          continue;
        }

        try {
          final fields = <String, String>{
            'photo_type': photo['photo_type'] as String,
            'taken_at':   photo['taken_at'] as String? ?? DateTime.now().toUtc().toIso8601String(),
          };
          if (photo['latitude'] != null) {
            fields['latitude']  = photo['latitude'].toString();
            fields['longitude'] = photo['longitude'].toString();
          }
          if (photo['description'] != null) {
            fields['description'] = photo['description'] as String;
          }

          final resp = await _client.multipart(
            '${Constants.visitsPath}$remoteId/photos/',
            fields,
            {'image': localPath},
          );
          if (resp.statusCode == 201) {
            await database.update(
              'pending_photos',
              {'uploaded': 1},
              where: 'id = ?',
              whereArgs: [photo['id']],
            );
          }
        } catch (e) {
          debugPrint('SyncService.pendingPhotos error (id ${photo['id']}): $e');
        }
      }
    }
  }
}
