import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sitevisit_app/repositories/auth_repository.dart';
import 'package:sitevisit_app/repositories/connectivity_repository.dart';
import 'package:sitevisit_app/repositories/theme_repository.dart';
import 'package:sitevisit_app/repositories/site_repository.dart';
import 'package:sitevisit_app/repositories/visit_repository.dart';
import 'package:sitevisit_app/services/secure_storage_service.dart';
import 'package:sitevisit_app/services/auth_service.dart';
import 'package:sitevisit_app/services/device_service.dart';
import 'package:sitevisit_app/services/local_db_service.dart';
import 'package:sitevisit_app/services/offline_manager.dart';
import 'package:sitevisit_app/services/site_service.dart';
import 'package:sitevisit_app/services/visit_service.dart';
import 'package:sitevisit_app/services/theme_service.dart';
import 'package:sitevisit_app/services/api_client.dart';
import 'package:sitevisit_app/config/app_router.dart';
import 'package:sitevisit_app/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    final storage        = SecureStorageService();
    final apiClient      = ApiClient(storage: storage);
    final deviceSvc      = DeviceService();
    final localDb        = LocalDbService();
    final connectivityRepo = ConnectivityRepository();

    final offlineManager = OfflineManager(
      siteService:  SiteService(client: apiClient),
      visitService: VisitService(client: apiClient),
      db:           localDb,
      connectivity: connectivityRepo,
    );

    final authRepo  = AuthRepository(
      authService:   AuthService(client: apiClient),
      storage:       storage,
      deviceService: deviceSvc,
    );
    final siteRepo  = SiteRepository(offlineManager: offlineManager);
    final visitRepo = VisitRepository(offlineManager: offlineManager);
    final themeRepo = ThemeRepository(service: ThemeService(client: apiClient));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConnectivityRepository>.value(value: connectivityRepo),
          ChangeNotifierProvider<AuthRepository>.value(value: authRepo),
          ChangeNotifierProvider<SiteRepository>.value(value: siteRepo),
          ChangeNotifierProvider<VisitRepository>.value(value: visitRepo),
          ChangeNotifierProvider<ThemeRepository>.value(value: themeRepo),
        ],
        child: SiteVisitApp(router: AppRouter.router(authRepo)),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('SiteVisit'), findsOneWidget);
  });
}
