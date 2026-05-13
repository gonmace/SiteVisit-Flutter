# Plan: Soporte Offline Completo (Criterion-driven)

## Contexto

La app tiene infraestructura offline parcialmente construida (sqflite, SyncService, tabla `sites`)
pero **completamente desconectada**: `SyncService` nunca se instancia, los repositories nunca leen
ni escriben en SQLite, y no existe caché de visitas. El objetivo es conectar todo y cubrir los
4 criterios del usuario: login persistente, caché de GETs, cola de POSTs/PATCHes offline (incluyendo
fotos), y sincronización automática al recuperar señal.

---

## Evaluación de los criterios

| Criterio | Estado actual | Veredicto |
|---|---|---|
| **1. Login sin red** | Tokens en SecureStorage, router depende de `AuthStatus` local | ✅ Ya funciona — no tocar |
| **2. Caché de sitios** | Tabla `sites` existe, `upsertSites/getSites` implementados, pero nunca se llaman | 🔧 Solo hay que cablear |
| **3. Caché de visitas** | No existe tabla ni métodos | 🔧 Agregar tabla + cablear |
| **4. Cola offline de POSTs** | Tablas `active_visit`, `pending_photos`, `pending_tracking` existen y `SyncService` sabe subirlas, pero los repositories nunca escriben en ellas | 🔧 Cablear repositories + agregar status/notas |
| **SyncService** | Nunca se instancia en `main.dart` | 🔧 Inicializar |

**Riesgos identificados:**
- **Rutas de fotos offline**: Las fotos deben guardarse en el directorio permanente de la app (documents), no en `/tmp`. Verificar que `CameraService` ya lo hace; si no, corregir antes de escribir en `pending_photos`.
- **Visita creada offline + ejecutada offline**: El sync debe ordenarse: (1) crear visita → obtener `remote_id`, (2) subir requests dependientes (status/notas), (3) subir fotos/tracking.
- **IDs temporales**: Visitas creadas offline usan el `id` autoincrement de SQLite como ID local. En el modelo en memoria se representan con `id = -localId` (negativo) para distinguirlas de IDs del servidor. Se reemplazan al sincronizar.

---

## Issues encontrados en revisión del plan

Antes de implementar, los siguientes problemas reales del diseño previo fueron detectados y corregidos en las secciones de abajo:

1. **🔴 `pending_requests.path` con visit.id negativo no funcionaba** — `'/api/v1/visits/-5/status/'` es URL inválida. **Fix**: agregar columna `visit_local_id` y placeholder `{visit_id}` en `path`, resolver al momento del sync con `active_visit.remote_id`.
2. **🔴 Visitas del servidor no tenían fila en `active_visit`** — `pending_photos.visit_local_id` referencia `active_visit.id`, pero solo se insertaba en `active_visit` para visitas creadas offline. Fotos y tracking de visitas del servidor quedaban huérfanos. **Fix**: `setActiveVisit(visit)` siempre inserta (o reusa) fila en `active_visit`.
3. **🟡 `ConnectivityRepository` partía como `_isOnline = true` (falso positivo al arrancar offline)** — **Fix**: empezar como `null` (estado "desconocido") hasta que `checkConnectivity()` resuelva.
4. **🟡 Visitas creadas offline no se mostraban tras cerrar la app** — `fetchVisits()` solo leía de tabla `visits`, no de `active_visit`. **Fix**: en fallback offline, mergear `getVisits()` con las filas de `active_visit` que tengan `remote_id IS NULL`.
5. **🟡 Tabla `visits` cache no incluía campo `notas`** que sí está en `VisitModel.fromJson`. **Fix**: agregar columna.
6. **🟡 Pérdida de cola si refresh token expira mientras offline** — al reconectar, el primer request 401 → refresh falla → `onAuthFailed` → logout → `_storage.clearAll()` borra tokens pero NO la SQLite. La cola permanece pero sin sesión para enviarla. **Fix (mínimo)**: documentar este caso; agregar verificación previa en `_syncAll()` para no perder visibilidad. No requiere cambio estructural — la cola se conserva en SQLite y reanuda al re-loguear.
7. **🟢 Paths hardcodeados** — usar `Constants.visitsPath` en vez de `/api/v1/visits/` literal.

---

## Arquitectura revisada — módulo `OfflineManager`

En lugar de distribuir la lógica offline en cada repository, un único `OfflineManager`
actúa como proxy centralizado entre los repositories y los datos.

```
Views (Widgets)
      ↓
Repositories (ChangeNotifier — solo lógica de negocio y estado UI)
      ↓
OfflineManager  ←── decide: ¿online? → API  |  ¿offline? → SQLite/cola
      ↓             ↓
 ApiClient    LocalDbService
      ↓
  Backend
```

**Beneficios:**
- Lógica offline en UN solo lugar — fácil de modificar o testear
- Repositories quedan limpios: llaman `offlineManager.fetchVisits()` en vez de `if (online) ... else ...`
- Añadir un nuevo endpoint offline-capable es solo agregar un método a `OfflineManager`

## Archivos a modificar / crear

| Archivo | Cambio |
|---|---|
| `lib/services/local_db_service.dart` | Tablas nuevas, métodos CRUD públicos, versión DB → 4 |
| `lib/services/offline_manager.dart` | **NUEVO** — proxy central: cache reads + cola offline de writes |
| `lib/services/sync_service.dart` | Sync de `pending_requests`; notificación al terminar |
| `lib/repositories/site_repository.dart` | Inyectar `OfflineManager`; delegar fetch/cache |
| `lib/repositories/visit_repository.dart` | Inyectar `OfflineManager`; delegar toda operación |
| `lib/repositories/connectivity_repository.dart` | **NUEVO** — ChangeNotifier que expone `isOnline` |
| `lib/widgets/connectivity_banner.dart` | **NUEVO** — banner visual global (rojo = sin red) |
| `lib/main.dart` | Instanciar `LocalDbService`, `OfflineManager`, `SyncService`, `ConnectivityRepository` |

---

## Paso 1 — `LocalDbService` (versión DB 4)

**Nueva tabla `visits`** (caché del GET /api/v1/visits/):
```sql
CREATE TABLE visits (
  id                  INTEGER PRIMARY KEY,
  site_id             INTEGER,
  site_code           TEXT,
  site_operator_code  TEXT,
  site_name           TEXT,
  status              TEXT,
  reason              TEXT,
  scheduled_date      TEXT,
  eta                 TEXT,
  hora_inicio         TEXT,
  hora_fin            TEXT,
  notas               TEXT NOT NULL DEFAULT ''
)
```

**Nueva tabla `pending_requests`** (cola genérica JSON para cualquier POST/PATCH sin red):
```sql
CREATE TABLE pending_requests (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  method          TEXT NOT NULL,       -- 'POST' o 'PATCH'
  path_template   TEXT NOT NULL,       -- ej: '${visitsPath}{visit_id}/status/'
  visit_local_id  INTEGER,             -- opcional: si está set, {visit_id} se resuelve con active_visit.remote_id
  body_json       TEXT NOT NULL,       -- JSON exacto que se enviará al servidor
  created_at      TEXT NOT NULL,       -- timestamp de cuando el usuario hizo la acción (OFFLINE)
  uploaded        INTEGER NOT NULL DEFAULT 0
)
```

> **Resolución del placeholder `{visit_id}` al sincronizar:**
> - Si `visit_local_id` es NULL → el path va literal (visita ya tenía remote_id al encolar).
> - Si `visit_local_id` está set → buscar `active_visit.remote_id` con `id = visit_local_id`:
>    - si remote_id es NULL → **skip** (la visita aún no se sincronizó; reintentar luego)
>    - si tiene remote_id → reemplazar `{visit_id}` en `path_template` y enviar.

> **Clave de diseño**: el `body_json` ya contiene el timestamp correcto (el momento de la
> acción del usuario, capturado con `DateTime.now()` antes de escribir en la cola).
> Cuando el sync lo envía, manda ese JSON sin modificarlo — la fecha nunca se sobreescribe.

Las tablas `pending_photos` y `pending_tracking` **se mantienen como están** — ya funcionan
en `SyncService` y ya capturan el timestamp en el momento del registro.

**Nuevos métodos públicos** a agregar:
```dart
Future<void> upsertVisits(List<VisitModel> visits)
Future<List<VisitModel>> getVisits()

// Garantiza (idempotente) que exista active_visit para esta visita.
// Para visitas del servidor: visit_id = remote_id = visit.id, sync_pending = 0.
// Para visitas offline:     visit_id se genera local, remote_id = null, sync_pending = 1.
// Devuelve active_visit.id (el localId que usa pending_photos / pending_tracking / pending_requests).
Future<int>  ensureActiveVisit({
  required int?    remoteId,            // null si fue creada offline
  required int     siteId,
  required String  reason,
  required String  scheduledDate,
  required String  status,
})
Future<void> setActiveVisitRemoteId(int localId, int remoteId)
Future<void> updateActiveVisitStatus(int localId, String status)
Future<List<Map<String, dynamic>>> getPendingVisits()            // sync_pending=1 AND remote_id IS NULL
Future<List<Map<String, dynamic>>> getActiveVisits()             // todas, para mergear con visits cache

Future<void> enqueuePendingRequest({
  required String method,
  required String pathTemplate,        // puede contener {visit_id}
  required Map<String, dynamic> body,  // se serializa a JSON internamente
  int? visitLocalId,                   // si está set, {visit_id} se resuelve al sincronizar
})
Future<List<Map<String, dynamic>>> getPendingRequests()          // uploaded=0, ORDER BY id ASC
Future<void> markRequestUploaded(int id)

// (métodos existentes ya usados por SyncService — sin cambios)
Future<void> insertPendingPhoto(Map<String, dynamic> row)
Future<void> insertPendingTracking(Map<String, dynamic> row)
```

Migración `onUpgrade`: añadir bloque `if (oldVersion < 4)` que crea las 2 tablas nuevas.

---

## Paso 2 — `OfflineManager` (nuevo)

Archivo: `lib/services/offline_manager.dart`

Recibe `ApiClient`, `LocalDbService` y `ConnectivityRepository`. Es el ÚNICO lugar donde
se decide si leer de red o de caché, y si escribir directamente o encolar.

```dart
class OfflineManager {
  final ApiClient          _client;
  final LocalDbService     _db;
  final ConnectivityRepository _connectivity;

  OfflineManager({
    required ApiClient client,
    required LocalDbService db,
    required ConnectivityRepository connectivity,
  })  : _client = client,
        _db = db,
        _connectivity = connectivity;

  bool get _online => _connectivity.isOnline;

  // ── READS (network-first, SQLite fallback) ─────────────────────────────────

  Future<List<SiteModel>> fetchSites() async {
    try {
      final sites = await _fetchSitesFromApi();   // llama a SiteService
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
      final visits = await _fetchVisitsFromApi();  // llama a VisitService
      await _db.upsertVisits(visits);
      return visits;
    } catch (_) {
      final cached  = await _db.getVisits();
      final pending = await _db.getPendingVisits();  // creadas offline, aún no sincronizadas
      final tempVisits = pending.map(_pendingRowToVisitModel).toList();
      return [...tempVisits, ...cached];
    }
  }

  // ── WRITES (directo si online, cola si offline) ────────────────────────────

  Future<VisitModel> createVisit({
    required int siteId, required String reason,
    required String scheduledDate, String? eta,
  }) async {
    if (_online) {
      final visit = await _callCreateVisit(siteId, reason, scheduledDate, eta);
      await _db.upsertVisits([visit]);
      return visit;
    } else {
      final localId = await _db.ensureActiveVisit(
        remoteId: null, siteId: siteId,
        reason: reason, scheduledDate: scheduledDate, status: 'programada',
      );
      return _tempVisitModel(localId: localId, siteId: siteId,
                             reason: reason, scheduledDate: scheduledDate);
    }
  }

  /// Garantiza la fila active_visit y devuelve el localId.
  /// Llamar antes de cualquier write de ejecución.
  Future<int> ensureActiveVisit(VisitModel visit) async {
    return _db.ensureActiveVisit(
      remoteId:      visit.id > 0 ? visit.id : null,
      siteId:        visit.siteId,
      reason:        visit.reason,
      scheduledDate: visit.scheduledDate,
      status:        visit.status.apiName,
    );
  }

  Future<VisitModel?> updateStatus({
    required int visitId, required int localId,
    required String newStatus,
    double? latitude, double? longitude,
    required DateTime timestamp, String? eta,
  }) async {
    final now = timestamp.toUtc().toIso8601String();  // preservar timestamp del evento
    await _db.updateActiveVisitStatus(localId, newStatus);
    if (_online) {
      return _callUpdateStatus(visitId, newStatus, latitude, longitude, now, eta);
    } else {
      await _db.enqueuePendingRequest(
        method: 'POST',
        pathTemplate: '${Constants.visitsPath}{visit_id}/status/',
        visitLocalId: localId,
        body: {
          'status': newStatus,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          'timestamp': now,
          if (eta != null) 'eta': eta,
        },
      );
      return null;   // repositorio aplica copyWith en memoria
    }
  }

  Future<VisitModel?> updateNotas({
    required int visitId, required int localId, required String notas,
  }) async {
    if (_online) {
      return _callUpdateNotas(visitId, notas);
    } else {
      await _db.enqueuePendingRequest(
        method: 'PATCH',
        pathTemplate: '${Constants.visitsPath}{visit_id}/notas/',
        visitLocalId: localId,
        body: {'notas': notas},
      );
      return null;
    }
  }

  Future<void> uploadPhoto({
    required int visitId, required int localId,
    required String photoType, required String imagePath,
    double? latitude, double? longitude,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    if (_online) {
      await _callUploadPhoto(visitId, photoType, imagePath, latitude, longitude, now);
    } else {
      await _db.insertPendingPhoto({
        'visit_local_id': localId,
        'photo_type':     photoType,
        'local_path':     imagePath,
        'latitude':       latitude,
        'longitude':      longitude,
        'taken_at':       now,
        'uploaded':       0,
      });
    }
  }

  Future<void> uploadTrackingPoint({
    required int visitId, required int localId, required String event,
    required double latitude, required double longitude,
    required DateTime timestamp,
  }) async {
    final ts = timestamp.toUtc().toIso8601String();  // preservar timestamp del evento
    if (_online) {
      await _callUploadTracking(visitId, event, latitude, longitude, ts);
    } else {
      await _db.insertPendingTracking({
        'visit_local_id': localId,
        'event':          event,
        'latitude':       latitude,
        'longitude':      longitude,
        'timestamp':      ts,
        'uploaded':       0,
      });
    }
  }

  // ── Helpers privados (delegan a ApiClient/Services) ────────────────────────
  // _fetchSitesFromApi, _fetchVisitsFromApi, _callCreateVisit, _callUpdateStatus,
  // _callUpdateNotas, _callUploadPhoto, _callUploadTracking
  // (implementados llamando directamente a _client o recibiendo los services por inyección)
}
```

> Los helpers privados llaman a `SiteService`/`VisitService` o directamente a `_client`.
> Una opción más limpia: inyectar `SiteService` y `VisitService` en `OfflineManager` también,
> para reutilizar su lógica de parsing/errores sin duplicar.

---

## Paso 3 — Repositories (thin layer)

Con `OfflineManager`, los repositories se simplifican a:

**`SiteRepository.fetchSites()`:**
```dart
_sites = await _offlineManager.fetchSites();
notifyListeners();
```

**`VisitRepository` completo:**
```dart
// fetchVisits — delega
_visits = await _offlineManager.fetchVisits();
notifyListeners();

// setActiveVisit — garantiza active_visit y guarda localId
_activeLocalId = await _offlineManager.ensureActiveVisit(visit);
_activeVisit = visit;
notifyListeners();

// createVisit — delega (puede devolver visita temporal offline)
final visit = await _offlineManager.createVisit(...);
_visits = [visit, ..._visits];
notifyListeners();

// updateVisitStatus — delega; aplica copyWith en memoria si offline
final updated = await _offlineManager.updateStatus(
  visitId: visit.id, localId: _activeLocalId!, ...);
if (updated != null) { _patchVisitInList(updated); _activeVisit = updated; }
else { _patchVisitInList(_activeVisit!.copyWith(status: ...)); }
notifyListeners();

// uploadPhoto / uploadTrackingPoint / updateNotas — delega sin lógica adicional
```

> Los repositories ya no tienen `if (online) ... else ...`. Toda esa lógica
> vive en `OfflineManager`.

---

## Paso 4 — `SyncService`

Agregar **`_syncPendingRequests()`** que procesa `pending_requests` en orden FIFO,
resolviendo `{visit_id}` con el `remote_id` de `active_visit` cuando sea necesario:

```
requests = getPendingRequests()   // ORDER BY id ASC, uploaded=0
for each request:
  // 1. Resolver el path si tiene placeholder
  path = request.path_template
  if request.visit_local_id != null:
    av = active_visit WHERE id = request.visit_local_id
    if av.remote_id == null:
      continue   // skip: la visita aún no se ha sincronizado, reintentar luego
    path = path.replace('{visit_id}', av.remote_id.toString())

  // 2. Enviar request preservando body_json intacto (timestamp original)
  try:
    body = jsonDecode(request.body_json)
    if request.method == 'POST':   resp = _client.post(path, body)
    elif request.method == 'PATCH': resp = _client.patch(path, body)
    if resp.statusCode in [200, 201]:
      markRequestUploaded(request.id)
  catch: // silenciar, reintentar en próximo evento de conectividad
```

**Orden final de `_syncAll()` (importante — respetar dependencias):**
1. `_syncPendingVisits()` — crea visitas offline → obtiene `remote_id`
2. `_syncPendingRequests()` — status / notas (placeholder resuelto contra remote_id ya asignado)
3. `_syncPendingTracking()` — puntos GPS
4. `_syncPendingPhotos()` — multipart

> El `body_json` se envía sin modificar — el timestamp original se preserva.
> Si una visita aún no se sincronizó (creada offline), los requests dependientes se posponen
> al siguiente ciclo de sync sin perderse.

Opcionalmente, al terminar `_syncAll()` emitir un `Stream<void>` o callback para que
`VisitRepository` haga un `fetchVisits()` y refresque la UI con los IDs reales.

---

## Paso 5 — Indicador de conectividad (global)

### `lib/repositories/connectivity_repository.dart` (nuevo)
```dart
class ConnectivityRepository extends ChangeNotifier {
  // null = aún no se hizo la primera verificación.
  // Iniciar como null evita el falso positivo "online" al arrancar sin red.
  bool? _isOnline;
  bool get isOnline => _isOnline ?? false;        // pesimista por defecto
  bool get isUnknown => _isOnline == null;        // útil para el banner inicial

  ConnectivityRepository() {
    Connectivity().checkConnectivity().then(_update);
    Connectivity().onConnectivityChanged.listen(_update);
  }

  void _update(dynamic result) {
    final results = result is List ? result : [result];
    final online = (results as List).any((r) => r != ConnectivityResult.none);
    if (online != _isOnline) {
      _isOnline = online;
      notifyListeners();
    }
  }
}
```

### `lib/widgets/connectivity_banner.dart` (nuevo)
Banner estándar: franja delgada (~28 px) anclada arriba del contenido.
- **Online** → no muestra nada (desaparece suavemente con `AnimatedSize`)
- **Offline** → franja **roja** con ícono de WiFi apagado y texto `"Sin conexión"`
- **Sync en curso** → franja **amarilla** `"Sincronizando…"` (opcional, segunda fase)

```dart
// Uso en SiteVisitApp.builder (main.dart)
builder: (ctx, child) => Column(
  children: [
    ConnectivityBanner(),   // aparece/desaparece automáticamente
    Expanded(child: PendingOverlay(child: child!)),
  ],
),
```

Esto lo inyecta en **todas las pantallas** sin modificar cada una individualmente.
`ConnectivityBanner` hace `context.watch<ConnectivityRepository>()` para reaccionar en tiempo real.

---

## Paso 6 — `main.dart`

```dart
final localDb          = LocalDbService();
final connectivityRepo = ConnectivityRepository();

final offlineManager = OfflineManager(
  client:       apiClient,
  db:           localDb,
  connectivity: connectivityRepo,
  siteService:  siteSvc,
  visitService: visitSvc,
);

final syncSvc = SyncService(db: localDb, client: apiClient);
syncSvc.startListening();

final siteRepo  = SiteRepository(offlineManager: offlineManager);
final visitRepo = VisitRepository(offlineManager: offlineManager);
```

Agregar al `MultiProvider`:
```dart
ChangeNotifierProvider<ConnectivityRepository>.value(value: connectivityRepo),
Provider<LocalDbService>.value(value: localDb),
Provider<OfflineManager>.value(value: offlineManager),
```

---

## Verificación

1. **Indicador visual**: Desconectar WiFi/datos → verificar que aparece franja roja en la parte superior de cualquier pantalla. Reconectar → franja desaparece.
2. **Caché de sitios**: Con red, ir a crear visita → desconectar → cerrar app → abrir → verificar que los sitios siguen apareciendo en el selector.
3. **Caché de visitas**: Con red, abrir lista de visitas → desconectar → reabrir app → verificar que la lista carga desde local.
4. **Crear visita offline**: Desconectar → crear visita → debe aparecer en lista marcada como "pendiente". Reconectar → verificar que aparece en el backend con ID real.
5. **Fotos offline**: Con visita activa y sin red → tomar foto → sin error. Reconectar → verificar que la foto aparece en el backend.
6. **Tracking offline**: Registrar punto GPS sin red → sync automático al reconectar → verificar en backend.
7. **Status update offline**: Cambiar estado de visita sin red → cambio visible en UI inmediatamente con timestamp del momento de la acción → sync al reconectar → verificar timestamp correcto en backend.
