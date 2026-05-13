import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/login_result.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/visit_repository.dart';

class PendingOverlay extends StatefulWidget {
  final Widget child;
  const PendingOverlay({super.key, required this.child});

  @override
  State<PendingOverlay> createState() => _PendingOverlayState();
}

class _PendingOverlayState extends State<PendingOverlay> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final authRepo = context.watch<AuthRepository>();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          if (authRepo.isPendingApproval)
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.grey,
                BlendMode.saturation,
              ),
              child: widget.child,
            )
          else
            widget.child,
          if (authRepo.isPendingApproval) _buildModal(context, authRepo),
        ],
      ),
    );
  }

  Widget _buildModal(BuildContext context, AuthRepository authRepo) {
    return Positioned.fill(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: AppTheme.secondary.withValues(alpha: 0.75),
          child: Center(
            child: Material(
              color: AppTheme.surf(context),
              borderRadius: BorderRadius.circular(20),
              elevation: 8,
              shadowColor: AppTheme.secondary.withValues(alpha: 0.2),
              child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.access_time_filled,
                      size: 38,
                      color: AppTheme.info,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cuenta en revisión',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tu cuenta está pendiente de aprobación por el coordinador. '
                    'Podrás usar la aplicación una vez que sea habilitada.',
                    style: TextStyle(
                      color: AppTheme.textSec(context),
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _loading ? null : () => _retry(context, authRepo),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Reintentar',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : () => authRepo.logout(),
                    child: Text(
                      'Cerrar sesión',
                      style: TextStyle(
                        color: AppTheme.textSec(context),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retry(BuildContext context, AuthRepository authRepo) async {
    setState(() => _loading = true);
    final result = await authRepo.retryLogin();
    if (!mounted) return;
    setState(() => _loading = false);

    if (result is LoginSuccess) {
      await context.read<VisitRepository>().fetchVisits();
      if (!mounted) return;
      context.read<GoRouter>().go(result.role == 'viewer' ? '/dashboard' : '/visits');
    }
  }
}
