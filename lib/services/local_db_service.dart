import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/site.dart';
import '../models/visit.dart';

class LocalDbService {
  static Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'sitevisit.db');
    return openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE active_visit (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id        INTEGER,
        remote_id       INTEGER,
        status          TEXT    NOT NULL,
        site_id         INTEGER,
        site_code       TEXT,
        reason          TEXT,
        scheduled_date  TEXT,
        hora_inicio           TEXT,
        hora_fin              TEXT,
        sync_pending          INTEGER NOT NULL DEFAULT 1,
        session_photos_json   TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_photos (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_local_id  INTEGER NOT NULL,
        photo_type      TEXT    NOT NULL,
        local_path      TEXT    NOT NULL,
        latitude        REAL,
        longitude       REAL,
        description     TEXT,
        taken_at        TEXT,
        uploaded        INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_tracking (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_local_id  INTEGER NOT NULL,
        event           TEXT    NOT NULL,
        latitude        REAL    NOT NULL,
        longitude       REAL    NOT NULL,
        timestamp       TEXT    NOT NULL,
        uploaded        INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _createSitesTable(db);
    await _createVisitsTable(db);
    await _createPendingRequestsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createSitesTable(db);
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE sites ADD COLUMN operator_code TEXT NOT NULL DEFAULT ''",
      );
    }
    if (oldVersion < 4) {
      await _createVisitsTable(db);
      await _createPendingRequestsTable(db);
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE pending_photos ADD COLUMN description TEXT');
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE active_visit ADD COLUMN session_photos_json TEXT');
      } catch (_) {
        // La columna ya existe en instalaciones que tuvieron un _onCreate previo.
      }
    }
  }

  Future<void> _createSitesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sites (
        id            INTEGER PRIMARY KEY,
        code          TEXT    NOT NULL,
        operator_code TEXT    NOT NULL DEFAULT '',
        name          TEXT    NOT NULL,
        latitude      REAL    NOT NULL DEFAULT 0,
        longitude     REAL    NOT NULL DEFAULT 0,
        company       TEXT    NOT NULL DEFAULT ''
      )
    ''');
  }

  Future<void> _createVisitsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visits (
        id                  INTEGER PRIMARY KEY,
        site_id             INTEGER,
        site_code           TEXT    NOT NULL DEFAULT '',
        site_operator_code  TEXT    NOT NULL DEFAULT '',
        site_name           TEXT    NOT NULL DEFAULT '',
        status              TEXT    NOT NULL DEFAULT 'programada',
        reason              TEXT    NOT NULL DEFAULT '',
        scheduled_date      TEXT    NOT NULL DEFAULT '',
        eta                 TEXT,
        hora_inicio         TEXT,
        hora_fin            TEXT,
        notas               TEXT    NOT NULL DEFAULT ''
      )
    ''');
  }

  Future<void> _createPendingRequestsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_requests (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        method          TEXT    NOT NULL,
        path_template   TEXT    NOT NULL,
        visit_local_id  INTEGER,
        body_json       TEXT    NOT NULL,
        created_at      TEXT    NOT NULL,
        uploaded        INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // ── Sites ──────────────────────────────────────────────────────────────────

  Future<void> upsertSites(List<SiteModel> sites) async {
    final d = await db;
    final batch = d.batch();
    for (final s in sites) {
      batch.insert(
        'sites',
        {
          'id':            s.id,
          'code':          s.code,
          'operator_code': s.operatorCode,
          'name':          s.name,
          'latitude':      s.latitude,
          'longitude':     s.longitude,
          'company':       s.company,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<SiteModel>> getSites() async {
    final d = await db;
    final rows = await d.query('sites', orderBy: 'code');
    return rows.map((r) => SiteModel(
      id:           r['id'] as int,
      code:         r['code'] as String,
      operatorCode: r['operator_code'] as String? ?? '',
      name:         r['name'] as String,
      latitude:     (r['latitude'] as num).toDouble(),
      longitude:    (r['longitude'] as num).toDouble(),
      company:      r['company'] as String,
    )).toList();
  }

  // ── Visits cache ───────────────────────────────────────────────────────────

  Future<void> upsertVisits(List<VisitModel> visits) async {
    final d = await db;
    final batch = d.batch();
    for (final v in visits) {
      batch.insert(
        'visits',
        {
          'id':                 v.id,
          'site_id':            v.siteId,
          'site_code':          v.siteCode,
          'site_operator_code': v.siteOperatorCode,
          'site_name':          v.siteName,
          'status':             v.status.apiName,
          'reason':             v.reason,
          'scheduled_date':     v.scheduledDate,
          'eta':                v.eta,
          'hora_inicio':        v.horaInicioTrabajos?.toUtc().toIso8601String(),
          'hora_fin':           v.horaFinTrabajos?.toUtc().toIso8601String(),
          'notas':              v.notas,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<VisitModel>> getVisits() async {
    final d = await db;
    final rows = await d.query('visits', orderBy: 'scheduled_date DESC');
    return rows.map(_visitFromRow).toList();
  }

  VisitModel _visitFromRow(Map<String, dynamic> r) => VisitModel(
    id:               r['id'] as int,
    siteId:           (r['site_id'] as int?) ?? 0,
    siteCode:         r['site_code'] as String? ?? '',
    siteOperatorCode: r['site_operator_code'] as String? ?? '',
    siteName:         r['site_name'] as String? ?? '',
    status:           VisitStatus.fromString(r['status'] as String? ?? 'programada'),
    reason:           r['reason'] as String? ?? '',
    scheduledDate:    r['scheduled_date'] as String? ?? '',
    eta:              r['eta'] as String?,
    horaInicioTrabajos: r['hora_inicio'] != null
        ? DateTime.tryParse(r['hora_inicio'] as String)
        : null,
    horaFinTrabajos: r['hora_fin'] != null
        ? DateTime.tryParse(r['hora_fin'] as String)
        : null,
    notas: r['notas'] as String? ?? '',
  );

  // ── Active visit ───────────────────────────────────────────────────────────

  /// Garantiza (idempotente) que exista una fila active_visit para la visita.
  /// Para visitas del servidor [remoteId] es el ID real; para offline es null.
  /// Devuelve active_visit.id (localId).
  Future<int> ensureActiveVisit({
    required int?   remoteId,
    required int    siteId,
    required String reason,
    required String scheduledDate,
    required String status,
  }) async {
    final d = await db;
    if (remoteId != null) {
      final existing = await d.query(
        'active_visit',
        where: 'remote_id = ?',
        whereArgs: [remoteId],
        limit: 1,
      );
      if (existing.isNotEmpty) return existing.first['id'] as int;
    }
    return d.insert('active_visit', {
      'remote_id':     remoteId,
      'status':        status,
      'site_id':       siteId,
      'reason':        reason,
      'scheduled_date': scheduledDate,
      'sync_pending':  remoteId == null ? 1 : 0,
    });
  }

  Future<void> setActiveVisitRemoteId(int localId, int remoteId) async {
    final d = await db;
    await d.update(
      'active_visit',
      {'remote_id': remoteId, 'sync_pending': 0},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> updateActiveVisitStatus(int localId, String status) async {
    final d = await db;
    await d.update(
      'active_visit',
      {'status': status},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Mantiene la caché `visits` sincronizada con los cambios de ejecución
  /// para que el fallback offline muestre el estado correcto tras un reinicio.
  Future<void> updateCachedVisitStatus(
    int visitId,
    String status, {
    DateTime? horaInicio,
    DateTime? horaFin,
    String?   eta,
  }) async {
    if (visitId <= 0) return;
    final d = await db;
    final values = <String, dynamic>{'status': status};
    if (horaInicio != null) values['hora_inicio'] = horaInicio.toUtc().toIso8601String();
    if (horaFin    != null) values['hora_fin']    = horaFin.toUtc().toIso8601String();
    if (eta        != null) values['eta']         = eta;
    await d.update('visits', values, where: 'id = ?', whereArgs: [visitId]);
  }

  Future<List<Map<String, dynamic>>> getPendingVisits() async {
    final d = await db;
    return d.query(
      'active_visit',
      where: 'sync_pending = 1 AND remote_id IS NULL',
    );
  }

  Future<List<Map<String, dynamic>>> getActiveVisits() async {
    final d = await db;
    return d.query('active_visit');
  }

  // ── Pending photos ─────────────────────────────────────────────────────────

  Future<void> insertPendingPhoto(Map<String, dynamic> row) async {
    final d = await db;
    await d.insert('pending_photos', row);
  }

  // ── Pending tracking ───────────────────────────────────────────────────────

  Future<void> insertPendingTracking(Map<String, dynamic> row) async {
    final d = await db;
    await d.insert('pending_tracking', row);
  }

  // ── Pending requests (cola genérica JSON) ──────────────────────────────────

  Future<void> enqueuePendingRequest({
    required String method,
    required String pathTemplate,
    required Map<String, dynamic> body,
    int? visitLocalId,
  }) async {
    final d = await db;
    await d.insert('pending_requests', {
      'method':         method,
      'path_template':  pathTemplate,
      'visit_local_id': visitLocalId,
      'body_json':      jsonEncode(body),
      'created_at':     DateTime.now().toUtc().toIso8601String(),
      'uploaded':       0,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final d = await db;
    return d.query(
      'pending_requests',
      where: 'uploaded = 0',
      orderBy: 'id ASC',
    );
  }

  Future<void> markRequestUploaded(int id) async {
    final d = await db;
    await d.update(
      'pending_requests',
      {'uploaded': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Session photos (recuperación tras cierre de app) ───────────────────────

  Future<void> saveSessionPhotos(int localId, String json) async {
    final d = await db;
    await d.update(
      'active_visit',
      {'session_photos_json': json},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<String?> getSessionPhotosJson(int localId) async {
    final d = await db;
    final rows = await d.query(
      'active_visit',
      columns: ['session_photos_json'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['session_photos_json'] as String?;
  }
}
