import '../config/constants.dart';
import '../models/site.dart';
import '../models/visit.dart';
import '../repositories/connectivity_repository.dart';
import 'local_db_service.dart';
import 'site_service.dart';
import 'visit_service.dart';

/// Proxy central de offline-first.
/// Los repositories delegan aquí toda decisión de red vs. caché.
/// Regla: si hay red → API; si no → SQLite / cola `pending_requests`.
class OfflineManager {
  final SiteService             _siteService;
  final VisitService            _visitService;
  final LocalDbService          _db;
  final ConnectivityRepository  _connectivity;

  OfflineManager({
    required SiteService            siteService,
    required VisitService           visitService,
    required LocalDbService         db,
    required ConnectivityRepository connectivity,
  })  : _siteService  = siteService,
        _visitService = visitService,
        _db           = db,
        _connectivity = connectivity;

  bool get _online => _connectivity.isOnline;

  // ── Reads (network-first, SQLite fallback) ─────────────────────────────────

  Future<List<SiteModel>> fetchSites() async {
    try {
      final sites = await _siteService.fetchSites();
      await _db.upsertSites(sites);
      return sites;
    } catch (_) {
      final cached = await _db.getSites();
      if (cached.isEmpty) rethrow;
      return cached;
    }
  }

  Future<List<VisitModel>> fetchVisits() async {
    try {
      final visits = await _visitService.fetchVisits();
      await _db.upsertVisits(visits);
      return visits;
    } catch (_) {
      final cached = await _db.getVisits();
      if (cached.isEmpty) rethrow;
      return cached;
    }
  }

  // ── Writes (directo si online, cola si offline) ────────────────────────────

  /// Garantiza la fila active_visit para la visita y devuelve su localId.
  /// Llamar antes de cualquier operación de ejecución (status, notas, foto, tracking).
  Future<int> ensureActiveVisit(VisitModel visit) {
    return _db.ensureActiveVisit(
      remoteId:      visit.id > 0 ? visit.id : null,
      siteId:        visit.siteId,
      reason:        visit.reason,
      scheduledDate: visit.scheduledDate,
      status:        visit.status.apiName,
    );
  }

  /// Devuelve el [VisitModel] actualizado si estaba online, null si fue encolado.
  Future<VisitModel?> updateStatus({
    required int      visitId,
    required int      localId,
    required String   newStatus,
    double?           latitude,
    double?           longitude,
    required DateTime timestamp,
    String?           eta,
  }) async {
    final now = timestamp.toUtc().toIso8601String();
    await _db.updateActiveVisitStatus(localId, newStatus);

    // Actualizar caché visits para que el fallback offline refleje el estado real.
    final vs = VisitStatus.fromString(newStatus);
    await _db.updateCachedVisitStatus(
      visitId,
      newStatus,
      horaInicio: vs == VisitStatus.trabajando ? timestamp : null,
      horaFin:    vs == VisitStatus.completada ? timestamp : null,
      eta:        eta,
    );

    if (_online) {
      return _visitService.updateStatus(
        visitId:   visitId,
        newStatus: newStatus,
        latitude:  latitude,
        longitude: longitude,
        timestamp: timestamp,
        eta:       eta,
      );
    }
    await _db.enqueuePendingRequest(
      method:       'POST',
      pathTemplate: '${Constants.visitsPath}{visit_id}/status/',
      visitLocalId: localId,
      body: {
        'status': newStatus,
        if (latitude  != null) 'latitude':  latitude,
        if (longitude != null) 'longitude': longitude,
        'timestamp': now,
        if (eta != null && eta.isNotEmpty) 'eta': eta,
      },
    );
    return null;
  }

  /// Devuelve el [VisitModel] actualizado si estaba online, null si fue encolado.
  Future<VisitModel?> updateNotas({
    required int    visitId,
    required int    localId,
    required String notas,
  }) async {
    // Persistir notas en caché para sobrevivir reinicios offline.
    if (visitId > 0) {
      final d = await _db.db;
      await d.update('visits', {'notas': notas}, where: 'id = ?', whereArgs: [visitId]);
    }
    if (_online) {
      return _visitService.updateNotas(visitId: visitId, notas: notas);
    }
    await _db.enqueuePendingRequest(
      method:       'PATCH',
      pathTemplate: '${Constants.visitsPath}{visit_id}/notas/',
      visitLocalId: localId,
      body:         {'notas': notas},
    );
    return null;
  }

  Future<void> uploadPhoto({
    required int    visitId,
    required int    localId,
    required String photoType,
    required String imagePath,
    double?         latitude,
    double?         longitude,
    String?         description,
  }) async {
    final capturedAt = DateTime.now().toUtc();
    if (_online) {
      await _visitService.uploadPhoto(
        visitId:     visitId,
        photoType:   photoType,
        imagePath:   imagePath,
        latitude:    latitude,
        longitude:   longitude,
        description: description,
        takenAt:     capturedAt,
      );
    } else {
      await _db.insertPendingPhoto({
        'visit_local_id': localId,
        'photo_type':     photoType,
        'local_path':     imagePath,
        'latitude':       latitude,
        'longitude':      longitude,
        'description':    description,
        'taken_at':       capturedAt.toIso8601String(),
        'uploaded':       0,
      });
    }
  }

  // ── Session photos ────────────────────────────────────────────────────────

  Future<void> saveSessionPhotos(int localId, String json) =>
      _db.saveSessionPhotos(localId, json);

  Future<String?> getSessionPhotosJson(int localId) =>
      _db.getSessionPhotosJson(localId);

  // ─────────────────────────────────────────────────────────────────────────

  Future<void> uploadTrackingPoint({
    required int      visitId,
    required int      localId,
    required String   event,
    required double   latitude,
    required double   longitude,
    required DateTime timestamp,
  }) async {
    if (_online) {
      await _visitService.uploadTrackingPoint(
        visitId:   visitId,
        event:     event,
        latitude:  latitude,
        longitude: longitude,
        timestamp: timestamp,
      );
    } else {
      await _db.insertPendingTracking({
        'visit_local_id': localId,
        'event':          event,
        'latitude':       latitude,
        'longitude':      longitude,
        'timestamp':      timestamp.toUtc().toIso8601String(),
        'uploaded':       0,
      });
    }
  }

}
