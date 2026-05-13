import 'dart:convert';

import 'package:flutter/cupertino.dart';

import '../models/visit.dart';
import '../services/offline_manager.dart';

class VisitRepository extends ChangeNotifier {
  final OfflineManager _offline;

  VisitRepository({required OfflineManager offlineManager})
      : _offline = offlineManager;

  List<VisitModel> _visits = [];
  List<VisitModel> get visits => _visits;

  VisitModel? _activeVisit;
  VisitModel? get activeVisit => _activeVisit;

  // localId de la fila active_visit en SQLite para la visita activa.
  // Necesario para todas las operaciones de ejecución offline.
  int? _activeLocalId;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Future<void> fetchVisits() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _visits = await _offline.fetchVisits();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setActiveVisit(VisitModel visit) async {
    _activeLocalId = await _offline.ensureActiveVisit(visit);
    _activeVisit = visit;
    notifyListeners();
  }

  Future<void> updateVisitStatus({
    required int visitId,
    required String newStatus,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    String? eta,
  }) async {
    final localId = _activeLocalId ?? await _offline.ensureActiveVisit(_activeVisit!);
    final ts = timestamp ?? DateTime.now();
    final updated = await _offline.updateStatus(
      visitId:   visitId,
      localId:   localId,
      newStatus: newStatus,
      latitude:  latitude,
      longitude: longitude,
      timestamp: ts,
      eta:       eta,
    );
    if (updated != null) {
      _patchVisitInList(updated);
      _activeVisit = updated;
    } else {
      // offline: aplicar cambio en memoria con el timestamp correcto
      final status = VisitStatus.fromString(newStatus);
      final patched = _activeVisit!.copyWith(
        status: status,
        horaInicioTrabajos: status == VisitStatus.trabajando ? ts : _activeVisit!.horaInicioTrabajos,
        horaFinTrabajos:    status == VisitStatus.completada ? ts : _activeVisit!.horaFinTrabajos,
      );
      _patchVisitInList(patched);
      _activeVisit = patched;
    }
    notifyListeners();
  }

  Future<void> updateNotas({required int visitId, required String notas}) async {
    final localId = _activeLocalId ?? await _offline.ensureActiveVisit(_activeVisit!);
    final updated = await _offline.updateNotas(
      visitId: visitId, localId: localId, notas: notas,
    );
    if (updated != null) {
      _patchVisitInList(updated);
      _activeVisit = updated;
    } else {
      final patched = _activeVisit!.copyWith(notas: notas);
      _patchVisitInList(patched);
      _activeVisit = patched;
    }
    notifyListeners();
  }

  Future<void> uploadPhoto({
    required int visitId,
    required String photoType,
    required String imagePath,
    double? latitude,
    double? longitude,
    String? description,
  }) async {
    final localId = _activeLocalId ?? await _offline.ensureActiveVisit(_activeVisit!);
    await _offline.uploadPhoto(
      visitId:     visitId,
      localId:     localId,
      photoType:   photoType,
      imagePath:   imagePath,
      latitude:    latitude,
      longitude:   longitude,
      description: description,
    );
  }

  Future<void> uploadTrackingPoint({
    required int visitId,
    required String event,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
  }) async {
    final localId = _activeLocalId ?? await _offline.ensureActiveVisit(_activeVisit!);
    await _offline.uploadTrackingPoint(
      visitId:   visitId,
      localId:   localId,
      event:     event,
      latitude:  latitude,
      longitude: longitude,
      timestamp: timestamp,
    );
  }

  void _patchVisitInList(VisitModel updated) {
    final idx = _visits.indexWhere((v) => v.id == updated.id);
    if (idx != -1) _visits[idx] = updated;
  }

  // ── Persistencia de fotos de sesión (recuperación tras cierre de app) ─────

  Future<void> persistSessionPhoto(
    String type,
    String path, {
    double? lat,
    double? lon,
  }) async {
    final id = _activeLocalId;
    if (id == null) return;
    final raw = await _offline.getSessionPhotosJson(id);
    final map = raw != null
        ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
        : <String, dynamic>{};
    map[type] = {'path': path, 'lat': lat, 'lon': lon};
    await _offline.saveSessionPhotos(id, jsonEncode(map));
  }

  Future<Map<String, dynamic>> loadSessionPhotos() async {
    final id = _activeLocalId;
    if (id == null) return {};
    final raw = await _offline.getSessionPhotosJson(id);
    if (raw == null || raw.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> clearSessionPhotos() async {
    final id = _activeLocalId;
    if (id == null) return;
    await _offline.saveSessionPhotos(id, '{}');
  }
}
