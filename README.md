# SiteVisit — App Flutter

App Android para técnicos de campo. Gestiona el ciclo completo de visitas técnicas a sitios de telecomunicaciones con fotos georreferenciadas, watermark GPS, tracking de estados y soporte offline-first.

---

## Stack

| Componente | Tecnología |
|---|---|
| Framework | Flutter (Dart ≥ 3.4) |
| UI | Material 3 |
| Estado | Provider (ChangeNotifier) |
| Navegación | go_router v14 |
| API | HTTP + JWT con auto-refresh |
| Almacenamiento seguro | flutter_secure_storage (Android Keystore) |
| BD local | sqflite (offline queue) |
| GPS | geolocator + permission_handler |
| Cámara | image_picker |
| Procesamiento de imágenes | dart:ui Canvas + image (isolate) |
| Conectividad | connectivity_plus |
| Crash reporting | Firebase Crashlytics |
| Android mínimo | API 26 (Android 8.0 Oreo) |
| Android target | API 34 (Android 14) |

---

## Quick Start

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8010
```

El emulador Android mapea `10.0.2.2` al `localhost` del host.
Para dispositivo físico usa `adb reverse tcp:8010 tcp:8010` y apunta a `http://localhost:8010`.

---

## Build de producción

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://sitevisit.btspti.com \
  --dart-define=APP_ENV=production
```

> Requiere keystore configurado. Ver sección **Firma del APK** más abajo.

---

## Arquitectura

```
Views (Widgets — context.watch)
    │
    ▼
Repositories (ChangeNotifier — fuente de verdad, notifyListeners)
    │
    ▼
Services (stateless — HTTP o sqflite)
```

- **Views** solo leen del Repository vía `context.watch`. Nunca llaman servicios directamente.
- **Repositories** son la fuente de verdad. Notifican widgets con `notifyListeners()`.
- **Services** son stateless: ejecutan la llamada HTTP o la operación SQLite y devuelven datos.

Providers montados en `main.dart` vía `MultiProvider`. `ApiClient` recibe `onAuthFailed → authRepo.logout` para logout automático en fallos de refresh.

---

## Flujo de autenticación

```
App inicia
    │
    ▼
LocationGateScreen
    ├── GPS denegado → LocationRequiredScreen (bloqueo)
    └── GPS ok → AuthRepository.initialize()
                    ├── Token válido → /visits  (o /dashboard si viewer)
                    └── Sin token   → /login
                                        │
                                LoginScreen
                                        │
                        POST /api/token/ + device_fingerprint
                                        │
              ┌─────────────────────────┼────────────────────┐
              │                         │                     │
         LoginSuccess          DeviceNotRegistered     PendingApproval
              │                         │                     │
           /visits            ActivationScreen      PendingApprovalScreen
                           (foto + fingerprint)
                                        │
                           POST /api/v1/users/{id}/activate/
                                        │
                           202 → espera aprobación del manager
```

### JWT y auto-refresh

`ApiClient` intercepta 401, intenta un refresh con el token de `SecureStorageService`, y reintenta la petición original. Si el refresh falla llama a `onAuthFailed` y limpia el storage.

---

## Pantallas

| Pantalla | Ruta | Descripción |
|---|---|---|
| `LocationGateScreen` | `/` | Verifica GPS, restaura sesión |
| `LocationRequiredScreen` | `/location-required` | Bloqueo sin permiso GPS |
| `LoginScreen` | `/login` | Email + password |
| `RegisterScreen` | `/register` | Registro de nuevo técnico |
| `ActivationScreen` | `/activate` | Foto + binding de dispositivo (1 sola vez) |
| `PendingApprovalScreen` | `/pending-approval` | Espera aprobación del manager |
| `VisitsListScreen` | `/visits` | Lista de visitas del técnico |
| `VisitExecutionScreen` | `/visits/execute` | 4 etapas: traslado → llegada → servicio → cierre |
| `DashboardScreen` | `/dashboard` | Métricas de solo lectura (rol viewer) |

---

## VisitExecutionScreen — etapas

| Etapa | Estado backend | Requisito para avanzar |
|---|---|---|
| Traslado | `en_camino` | ETA seleccionada |
| Llegada | `llegada` | Fotos: sitio + vehículo |
| Servicio | `trabajando` | Mínimo 2 fotos de trabajo |
| Cierre | `completada` | GPS capturado + notas |

El cronómetro corre desde `hora_inicio_trabajos`. Se restaura automáticamente si el usuario cierra y reabre la app.

---

## Fotos y watermark

Cada foto pasa por la siguiente cadena:

1. **Captura** — `image_picker` con `imageQuality: 85`
2. **GPS** — intento de 5 s alta precisión + fallback a última posición conocida
3. **Watermark** — `dart:ui` Canvas aplica lat/lon + logo sobre la imagen reducida a 1600px
4. **Encode** — JPEG q85 (foto completa) + JPEG q70 (thumbnail 200px) generados en `compute()` (background isolate)
5. **Thumbnail** — mostrado inmediatamente en UI con `cacheWidth: 104`
6. **Upload** — multipart de la foto completa al backend; si no hay red, se encola en `pending_photos`

---

## Offline-first

**sqflite — tablas:**
- `active_visit` — estado de la visita con `sync_pending` y `remote_id`
- `pending_photos` — fotos por subir (`uploaded = 0/1`)
- `pending_tracking` — puntos GPS por subir (`uploaded = 0/1`)

**SyncService:** escucha `connectivity_plus`. Al reconectar sincroniza en orden:
1. Visita sin `remote_id` → POST al backend
2. Tracking points pendientes de visitas ya sincronizadas
3. Fotos pendientes de visitas ya sincronizadas

Incluye debounce de 10 s para evitar sync storms en redes inestables.

---

## Estructura de archivos

```
lib/
├── main.dart                    ← Bootstrap Firebase + providers + runApp
├── firebase_options.dart        ← Generado por flutterfire configure
├── config/
│   ├── constants.dart           ← baseUrl (dart-define), rutas de API
│   ├── app_theme.dart           ← Paleta Material + helpers adaptativos dark/light
│   └── app_router.dart          ← GoRouter con redirect de autenticación
├── models/
│   ├── login_result.dart        ← sealed class LoginResult (5 subclases)
│   ├── user.dart
│   ├── site.dart
│   └── visit.dart               ← VisitModel, VisitStatus enum
├── services/
│   ├── api_client.dart          ← HTTP con JWT interceptor + auto-refresh
│   ├── auth_service.dart
│   ├── site_service.dart
│   ├── visit_service.dart
│   ├── theme_service.dart
│   ├── sync_service.dart        ← Cola offline → backend (con debounce)
│   ├── camera_service.dart      ← image_picker wrapper
│   ├── watermark_service.dart   ← Watermark GPS + JPEG encode en isolate
│   ├── device_service.dart      ← Fingerprint SHA256
│   ├── local_db_service.dart    ← sqflite (3 tablas, migraciones)
│   ├── offline_manager.dart     ← Orquestador offline
│   └── secure_storage_service.dart
├── repositories/
│   ├── auth_repository.dart     ← AuthStatus, currentUser, login/logout
│   ├── site_repository.dart
│   ├── visit_repository.dart    ← activeVisit + offline queue
│   ├── connectivity_repository.dart
│   └── theme_repository.dart    ← Tema dinámico desde backend
└── views/
    ├── location_gate/
    ├── auth/
    ├── visits/
    └── dashboard/
```

---

## Permisos Android

Declarados en `android/app/src/main/AndroidManifest.xml`:

| Permiso | Uso |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Comunicación con backend |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | GPS para watermark y tracking de visita |
| `CAMERA` | Captura de fotos |

---

## Firma del APK

### 1. Generar keystore (solo una vez)

```bash
keytool -genkey -v -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### 2. Crear `android/key.properties` (gitignored)

```properties
storePassword=<contraseña del keystore>
keyPassword=<contraseña del alias>
keyAlias=upload
storeFile=../upload-keystore.jks
```

### 3. Build release

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://sitevisit.btspti.com \
  --dart-define=APP_ENV=production
```

El APK firmado queda en `build/app/outputs/flutter-apk/app-release.apk`.

---

## Firebase Crashlytics

### Setup inicial (solo una vez por entorno)

**Requisito previo:** tener un proyecto en [Firebase Console](https://console.firebase.google.com) con la app Android registrada con `applicationId = cl.sitevisit.app`.

```bash
# 1. Instalar FlutterFire CLI
dart pub global activate flutterfire_cli

# 2. Autenticarse en Firebase
firebase login

# 3. Generar firebase_options.dart y descargar google-services.json
flutterfire configure --project=<nombre-de-tu-proyecto-firebase>
```

Este comando:
- Genera `lib/firebase_options.dart` (reemplaza el placeholder actual)
- Descarga `android/app/google-services.json`

> `google-services.json` y `firebase_options.dart` son gitignored. Cada desarrollador debe ejecutar `flutterfire configure` en su entorno.

### Cómo funciona

En `main.dart`, Firebase se inicializa antes de `runApp`. Si `firebase_options.dart` no está configurado, la app lo advierte en consola y continúa sin Crashlytics (safe fallback para desarrollo).

En producción, todos los errores no capturados se reportan automáticamente a Firebase Crashlytics con stack trace completo.

---

## Variables de entorno (dart-define)

| Variable | Dev (default) | Producción |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:8010` | `https://sitevisit.btspti.com` |
| `APP_ENV` | `dev` | `production` |

---

## Conectar al backend local

| Entorno | Comando |
|---|---|
| Emulador Android | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8010` |
| Dispositivo real | `adb reverse tcp:8010 tcp:8010` → mismo comando que emulador |

---

## Base de datos local — migraciones

`LocalDbService` maneja versiones con `onUpgrade`. Versión actual: **3**.  
Al añadir columnas: incrementar versión y agregar bloque `if (oldVersion < N)` en `_onUpgrade`.
