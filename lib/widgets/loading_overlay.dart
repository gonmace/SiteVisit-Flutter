import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Overlay de carga reutilizable.
/// Envuelve cualquier widget y muestra un spinner bloqueante cuando [isLoading] es true.
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: AbsorbPointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Material(
                    color: AppTheme.surf(context),
                    borderRadius: BorderRadius.circular(20),
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.18),
                    child: const Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(
                        color: AppTheme.primary,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
