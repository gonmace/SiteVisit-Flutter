# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Comandos

```bash
flutter pub get          # instalar dependencias
flutter run              # correr en dispositivo/emulador conectado
flutter analyze          # lint (flutter_lints)
flutter test             # suite de tests
flutter build apk        # APK de release (requiere key.properties)
```

### Build de producción

```bash
# Release APK firmado + URL de producción
flutter build apk --release \
  --dart-define=API_BASE_URL=https://sitevisit.btspti.com \
  --dart-define=APP_ENV=production

# Dev en emulador (default si no se pasa --dart-define)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8010
```

### Keystore de release (solo se hace una vez)

1. Generar keystore:
   ```bash
   keytool -genkey -v -keystore android/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Crear `android/key.properties` (gitignored):
   ```properties
   storePassword=<contraseña del keystore>
   keyPassword=<contraseña del alias>
   keyAlias=upload
   storeFile=../upload-keystore.jks
   ```

### Conectar al backend local

| Entorno | `--dart-define=API_BASE_URL=` | Requisito |
|---|---|---|
| Emulador Android | `http://10.0.2.2:8010` | ninguno |
| Dispositivo Android real | `http://localhost:8010` | `adb reverse tcp:8010 tcp:8010` |
| Dispositivo iOS real | `http://<IP-LAN>:8010` | misma red WiFi |

## Arquitectura

```
Views (Widgets — solo context.watch)
    ↓
Repositories (ChangeNotifier — fuente de verdad, notifyListeners)
    ↓
Services (stateless — HTTP o sqflite, devuelven datos)
```

**Regla estricta:** los Widgets nunca llaman a Services directamente. Todo pasa por el Repository correspondiente.

Los providers se construyen en `main.dart` y se inyectan vía `MultiProvider`. `ApiClient` recibe un callback `onAuthFailed` apuntando a `authRepo.logout` para logout automático en fallos de refresh.

### Autenticación y JWT

`ApiClient` (`lib/services/api_client.dart`) intercepta 401 automáticamente, intenta un refresh con el token guardado en `SecureStorageService`, y reintenta la petición original una vez. Si el refresh falla, llama a `onAuthFailed` y limpia el storage.

`AuthRepository` es `ChangeNotifier` y actúa como `refreshListenable` de `GoRouter` — cualquier cambio en `AuthStatus` dispara una re-evaluación del redirect.

### Login — sealed class `LoginResult`

El resultado del login tiene 5 subclases (`LoginSuccess`, `LoginDeviceNotRegistered`, `LoginPendingApproval`, `LoginDeviceUnauthorized`, `LoginError`). La pantalla de login hace `switch` exhaustivo sobre este tipo.

### Offline-first

**sqflite** (`lib/services/local_db_service.dart`) — 3 tablas:
- `active_visit` — visita activa con `sync_pending` y `remote_id` (null hasta que se sincronice)
- `pending_photos` — fotos con `uploaded = 0/1`
- `pending_tracking` — puntos GPS con `uploaded = 0/1`

**SyncService** (`lib/services/sync_service.dart`) — escucha `connectivity_plus` y sincroniza en orden:
1. `active_visit` sin `remote_id` → POST al backend
2. `pending_tracking` con `visit_local_id` que ya tenga `remote_id`
3. `pending_photos` ídem

El servicio se inicia en `main.dart` con `syncSvc.startListening()` antes de `runApp`.

**WorkManager** + **flutter_background_service** — iniciados en `BackgroundSyncService.init()` (llamado antes de `runApp`). Mantienen un foreground service Android activo durante la visita con notificación persistente.

### Navegación

Rutas en `lib/config/app_router.dart`. Las rutas públicas (`/`, `/login`, `/register`, `/activate`, `/pending-approval`, `/location-required`) no requieren autenticación. Cualquier ruta privada redirige a `/login` si `AuthStatus.unauthenticated`.

Para pasar datos entre rutas se usa `state.extra` (tipado con cast explícito, p. ej. `state.extra as LoginDeviceNotRegistered`).

### Base de datos local — migraciones

`LocalDbService` maneja versiones con `onUpgrade`. La versión actual es **3**. Al agregar columnas nuevas, incrementar la versión y agregar un bloque `if (oldVersion < N)` en `_onUpgrade`.

## Convenciones del proyecto

- UI construida con widgets **Material**. Se usan Cupertino solo para pickers de tiempo/fecha (`CupertinoDatePicker`, `showCupertinoModalPopup`). El tema dinámico viene de `ThemeRepository` → `ThemeService` → endpoint `/api/v1/theme/`.
- Los modelos usan `copyWith` para mutaciones inmutables (ver `VisitModel`).
- `VisitStatus` es un enum en `lib/models/visit.dart`; los estados válidos son los definidos ahí.
- El fingerprint del dispositivo se genera en `DeviceService` como SHA256 y se envía en el login para el binding dispositivo-usuario.

### Regla estricta: Material obligatorio para todo widget con estilo visual

**Todo contenedor con color de fondo, borde, sombra o texto debe usar `Material` como widget raíz**, nunca `Container` directamente. Esto previene el subrayado amarillo de Flutter en texto sin ancestro `Material`, y habilita efectos de tinta (`InkWell`).

Patrones obligatorios:

```dart
// Tarjeta con sombra:
Material(
  color: AppTheme.surf(context),
  borderRadius: BorderRadius.circular(12),
  elevation: 1,
  shadowColor: Colors.black.withValues(alpha: 0.04),
  child: Container(                  // solo para borde o padding
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.sep(context)),
    ),
    child: ...,
  ),
)

// Elemento interactivo:
Material(
  color: AppTheme.surf(context),
  borderRadius: BorderRadius.circular(12),
  child: InkWell(
    onTap: ...,
    borderRadius: BorderRadius.circular(12),
    child: Container(               // solo para borde o padding
      padding: ...,
      decoration: BoxDecoration(border: ...),
      child: ...,
    ),
  ),
)

// Elemento circular (avatares, badges):
Material(
  color: AppTheme.primary.withValues(alpha: 0.15),
  shape: const CircleBorder(),
  child: SizedBox(width: 44, height: 44, child: Center(child: Text(...))),
)
```

**Nunca usar `GestureDetector` + `Container` para elementos con texto o contenido visual**. Usar `Material` + `InkWell`.
