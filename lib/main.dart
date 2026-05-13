import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';

import 'config/app_router.dart';
import 'repositories/auth_repository.dart';
import 'repositories/connectivity_repository.dart';
import 'repositories/site_repository.dart';
import 'repositories/theme_repository.dart';
import 'repositories/visit_repository.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/camera_service.dart';
import 'services/watermark_service.dart';
import 'services/device_service.dart';
import 'services/local_db_service.dart';
import 'services/offline_manager.dart';
import 'services/secure_storage_service.dart';
import 'services/site_service.dart';
import 'services/sync_service.dart';
import 'services/theme_service.dart';
import 'services/visit_service.dart';
import 'views/auth/pending_overlay.dart';
import 'widgets/connectivity_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase Crashlytics — activo solo cuando firebase_options.dart está configurado
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Firebase no configurado (ejecuta flutterfire configure): $e');
  }

  final storage   = SecureStorageService();
  final apiClient = ApiClient(storage: storage);
  final deviceSvc = DeviceService();

  final authSvc  = AuthService(client: apiClient);
  final siteSvc  = SiteService(client: apiClient);
  final visitSvc = VisitService(client: apiClient);
  final themeSvc = ThemeService(client: apiClient);

  final localDb          = LocalDbService();
  final connectivityRepo = ConnectivityRepository();

  final offlineManager = OfflineManager(
    siteService:  siteSvc,
    visitService: visitSvc,
    db:           localDb,
    connectivity: connectivityRepo,
  );

  final syncSvc = SyncService(db: localDb, client: apiClient);
  syncSvc.startListening();

  final authRepo  = AuthRepository(
    authService:   authSvc,
    storage:       storage,
    deviceService: deviceSvc,
  );
  final siteRepo  = SiteRepository(offlineManager: offlineManager);
  final visitRepo = VisitRepository(offlineManager: offlineManager);
  final themeRepo = ThemeRepository(service: themeSvc);

  apiClient.onAuthFailed = authRepo.logout;

  final router = AppRouter.router(authRepo);

  runApp(
    MultiProvider(
      providers: [
        Provider<SecureStorageService>.value(value: storage),
        Provider<ApiClient>.value(value: apiClient),
        Provider<DeviceService>.value(value: deviceSvc),
        Provider<LocalDbService>.value(value: localDb),
        Provider<OfflineManager>.value(value: offlineManager),
        Provider<GoRouter>.value(value: router),
        Provider<CameraService>(create: (_) => CameraService()),
        Provider<WatermarkService>(create: (_) => WatermarkService()),
        ChangeNotifierProvider<ConnectivityRepository>.value(value: connectivityRepo),
        ChangeNotifierProvider<AuthRepository>.value(value: authRepo),
        ChangeNotifierProvider<SiteRepository>.value(value: siteRepo),
        ChangeNotifierProvider<VisitRepository>.value(value: visitRepo),
        ChangeNotifierProvider<ThemeRepository>.value(value: themeRepo),
      ],
      child: SiteVisitApp(router: router),
    ),
  );
}

class SiteVisitApp extends StatelessWidget {
  final GoRouter router;

  const SiteVisitApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    final themeRepo = context.watch<ThemeRepository>();
    return MaterialApp.router(
      title: 'SiteVisit',
      theme: themeRepo.themeFor(Brightness.light),
      darkTheme: themeRepo.themeFor(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (ctx, child) => Column(
        children: [
          Expanded(child: PendingOverlay(child: child!)),
          const ConnectivityBanner(),
        ],
      ),
    );
  }
}
