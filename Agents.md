# Agents.md — Convenciones para agentes de IA

Guía de referencia rápida para agentes trabajando en este repositorio Flutter.

## Regla crítica: Material en todo widget visual

**Todo contenedor con color, borde, sombra o texto debe usar `Material` como raíz**, no `Container` directamente.
Sin `Material` ancestro, Flutter muestra subrayado amarillo de debug en todos los textos.

```dart
// CORRECTO — tarjeta:
Material(
  color: AppTheme.surf(context),
  borderRadius: BorderRadius.circular(12),
  elevation: 1,
  child: Container(padding: ..., decoration: BoxDecoration(border: ...), child: ...),
)

// CORRECTO — interactivo:
Material(
  color: AppTheme.surf(context),
  borderRadius: BorderRadius.circular(12),
  child: InkWell(onTap: ..., borderRadius: BorderRadius.circular(12),
    child: Container(padding: ..., decoration: BoxDecoration(border: ...), child: ...)),
)

// CORRECTO — circular:
Material(color: color, shape: const CircleBorder(), child: SizedBox(width: 44, height: 44, child: ...))

// INCORRECTO — nunca hacer esto:
GestureDetector(onTap: ..., child: Container(decoration: BoxDecoration(...), child: Text(...)))
Container(decoration: BoxDecoration(color: ..., borderRadius: ...), child: Text(...))
```

## Arquitectura

```
Views (Widgets)  →  Repositories (ChangeNotifier)  →  Services (HTTP / sqflite)
```

- Widgets usan `context.watch<Repo>()` solo. Nunca llaman a Services directamente.
- Providers construidos en `main.dart` via `MultiProvider`.

## Autenticación

- `ApiClient` intercepta 401, reintenta con refresh token, llama `onAuthFailed` si falla.
- `AuthRepository` es `refreshListenable` de `GoRouter`.
- Login devuelve sealed class `LoginResult` con 5 subclases.

## Navegación

- Rutas en `lib/config/app_router.dart`.
- Rutas privadas redirigen a `/login` si `AuthStatus.unauthenticated`.
- Datos entre rutas via `state.extra` con cast explícito.

## Base de datos local (sqflite)

- `LocalDbService` — versión actual **3**. Al agregar columnas: incrementar versión + bloque `if (oldVersion < N)`.
- Tablas: `active_visit`, `pending_photos`, `pending_tracking`.
- `SyncService` sincroniza al reconectar en orden: visitas pendientes → tracking → fotos.

## Paleta de colores (`AppTheme`)

| Token | Color |
|---|---|
| `primary` | Rojo WOM `#FF3B30` |
| `success` | Verde `#34D399` |
| `info` | Azul `#38BDF8` |
| `warning` | Amarillo `#FBBF24` |
| `error` | Rojo claro `#F87171` |
| `surf(ctx)` | Superficie de tarjeta (adaptativo claro/oscuro) |
| `bg(ctx)` | Fondo de pantalla |
| `sep(ctx)` | Color de separadores/bordes |

## Modelos clave

- `VisitModel` — usa `copyWith`. Campo `status` es `VisitStatus` enum.
- `VisitStatus` enum en `lib/models/visit.dart` — estados: `programada`, `enCamino`, `llegada`, `trabajando`, `completada`, `cancelada`, `rechazada`, `pendienteAprobacion`.
- `LoginResult` — sealed: `LoginSuccess`, `LoginDeviceNotRegistered`, `LoginPendingApproval`, `LoginDeviceUnauthorized`, `LoginError`.

## Widgets reutilizables

- `LoadingOverlay` — spinner bloqueante sobre cualquier widget.
- `PhotoTile` — captura de foto con watermark y GPS.
- `ConnectivityBanner` — franja roja flotante cuando no hay red.
- `PendingOverlay` — modal de "cuenta en revisión" que bloquea la UI.
