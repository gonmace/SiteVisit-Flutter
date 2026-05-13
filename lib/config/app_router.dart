import 'package:go_router/go_router.dart';

import '../models/login_result.dart';
import '../repositories/auth_repository.dart';
import '../views/auth/activation_screen.dart';
import '../views/auth/login_screen.dart';
import '../views/auth/pending_approval_screen.dart';
import '../views/auth/register_screen.dart';
import '../views/dashboard/dashboard_screen.dart';
import '../views/location_gate/location_gate_screen.dart';
import '../views/location_gate/location_required_screen.dart';
import '../views/visits/visit_execution_screen.dart';
import '../views/visits/visits_list_screen.dart';

class AppRouter {
  static GoRouter router(AuthRepository authRepo) {
    const publicRoutes = {
      '/',
      '/login',
      '/register',
      '/activate',
      '/pending-approval',
      '/location-required',
    };
    return GoRouter(
      initialLocation: '/',
      refreshListenable: authRepo,
      redirect: (context, state) {
        if (authRepo.status == AuthStatus.unauthenticated &&
            !publicRoutes.contains(state.matchedLocation)) {
          return '/login';
        }
        if (authRepo.isPendingApproval &&
            state.matchedLocation == '/login') {
          return '/visits';
        }
        return null;
      },
      routes: [
      GoRoute(
        path: '/',
        builder: (ctx, state) => const LocationGateScreen(),
      ),
      GoRoute(
        path: '/location-required',
        builder: (ctx, state) => LocationRequiredScreen(
          isPermanent: state.extra as bool? ?? false,
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (ctx, state) => LoginScreen(initialEmail: state.extra as String?),
      ),
      GoRoute(
        path: '/register',
        builder: (ctx, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/activate',
        builder: (ctx, state) {
          final info = state.extra as LoginDeviceNotRegistered;
          return ActivationScreen(deviceInfo: info);
        },
      ),
      GoRoute(
        path: '/pending-approval',
        builder: (ctx, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: '/visits',
        builder: (ctx, state) => const VisitsListScreen(),
      ),
      GoRoute(
        path: '/visits/execute',
        builder: (ctx, state) => const VisitExecutionScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (ctx, state) => const DashboardScreen(),
      ),
    ],
    );
  }
}
